"""MaskablePPO + perte légère de Self-Imitation Learning.

Ce fichier est isolé du training principal. Le corps de ``train()`` reprend la
version installée de ``sb3_contrib.ppo_mask.ppo_mask.MaskablePPO`` puis ajoute
une petite behavior cloning loss sur des transitions d'épisodes gagnants.
"""

from __future__ import annotations

from typing import Any

import numpy as np
import torch as th
from gymnasium import spaces
from sb3_contrib import MaskablePPO
from stable_baselines3.common.utils import explained_variance
from torch.nn import functional as F

from self_imitation_buffer import SelfImitationBuffer


class SelfImitationPPO(MaskablePPO):
    """Sous-classe isolée de MaskablePPO avec BC loss capée."""

    def __init__(
        self,
        *args: Any,
        self_imitation_buffer: SelfImitationBuffer | None = None,
        bc_coef: float = 0.001,
        bc_batch_size: int = 128,
        bc_effective_loss_cap: float = 0.005,
        disable_self_imitation: bool = False,
        **kwargs: Any,
    ) -> None:
        if bc_coef < 0:
            raise ValueError("bc_coef doit être >= 0")
        if bc_batch_size <= 0:
            raise ValueError("bc_batch_size doit être positif")
        if bc_effective_loss_cap < 0:
            raise ValueError("bc_effective_loss_cap doit être >= 0")
        self.self_imitation_buffer = self_imitation_buffer
        self.bc_coef = float(bc_coef)
        self.bc_batch_size = int(bc_batch_size)
        self.bc_effective_loss_cap = float(bc_effective_loss_cap)
        self.disable_self_imitation = bool(disable_self_imitation)
        super().__init__(*args, **kwargs)

    def set_self_imitation_buffer(self, buffer: SelfImitationBuffer | None) -> None:
        self.self_imitation_buffer = buffer

    def _excluded_save_params(self) -> list[str]:
        excluded = super()._excluded_save_params()
        return [*excluded, "self_imitation_buffer"]

    def _compute_bc_losses(self) -> tuple[th.Tensor | None, th.Tensor | None]:
        if (
            self.disable_self_imitation
            or self.bc_coef <= 0.0
            or self.self_imitation_buffer is None
            or not self.self_imitation_buffer.bc_active
        ):
            return None, None

        batch = self.self_imitation_buffer.sample(self.bc_batch_size)
        if batch is None:
            return None, None

        observations = th.as_tensor(batch.observations, dtype=th.float32, device=self.device)
        actions = th.as_tensor(batch.actions, dtype=th.long, device=self.device).flatten()
        action_masks = th.as_tensor(batch.action_masks, dtype=th.float32, device=self.device)

        _values, log_prob, _entropy = self.policy.evaluate_actions(
            observations,
            actions,
            action_masks=action_masks,
        )
        bc_loss = -log_prob.mean()
        weighted = self.bc_coef * bc_loss
        if self.bc_effective_loss_cap > 0:
            weighted = th.clamp(weighted, max=self.bc_effective_loss_cap)
        return bc_loss, weighted

    def train(self) -> None:
        """Update policy using PPO plus optional capped BC loss."""

        # Switch to train mode (this affects batch norm / dropout)
        self.policy.set_training_mode(True)
        # Update optimizer learning rate
        self._update_learning_rate(self.policy.optimizer)
        # Compute current clip range
        clip_range = self.clip_range(self._current_progress_remaining)  # type: ignore[operator]
        # Optional: clip range for the value function
        if self.clip_range_vf is not None:
            clip_range_vf = self.clip_range_vf(self._current_progress_remaining)  # type: ignore[operator]

        entropy_losses = []
        pg_losses, value_losses = [], []
        clip_fractions = []
        bc_losses: list[float] = []
        bc_effective_losses: list[float] = []

        continue_training = True

        # train for n_epochs epochs
        for epoch in range(self.n_epochs):
            approx_kl_divs = []
            # Do a complete pass on the rollout buffer
            for rollout_data in self.rollout_buffer.get(self.batch_size):
                actions = rollout_data.actions
                if isinstance(self.action_space, spaces.Discrete):
                    # Convert discrete action from float to long
                    actions = rollout_data.actions.long().flatten()

                values, log_prob, entropy = self.policy.evaluate_actions(
                    rollout_data.observations,
                    actions,
                    action_masks=rollout_data.action_masks,
                )

                values = values.flatten()
                # Normalize advantage
                advantages = rollout_data.advantages
                if self.normalize_advantage:
                    advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)

                # ratio between old and new policy, should be one at the first iteration
                ratio = th.exp(log_prob - rollout_data.old_log_prob)

                # clipped surrogate loss
                policy_loss_1 = advantages * ratio
                policy_loss_2 = advantages * th.clamp(ratio, 1 - clip_range, 1 + clip_range)
                policy_loss = -th.min(policy_loss_1, policy_loss_2).mean()

                # Logging
                pg_losses.append(policy_loss.item())
                clip_fraction = th.mean((th.abs(ratio - 1) > clip_range).float()).item()
                clip_fractions.append(clip_fraction)

                if self.clip_range_vf is None:
                    # No clipping
                    values_pred = values
                else:
                    # Clip the different between old and new value
                    # NOTE: this depends on the reward scaling
                    values_pred = rollout_data.old_values + th.clamp(
                        values - rollout_data.old_values, -clip_range_vf, clip_range_vf
                    )
                # Value loss using the TD(gae_lambda) target
                value_loss = F.mse_loss(rollout_data.returns, values_pred)
                value_losses.append(value_loss.item())

                # Entropy loss favor exploration
                if entropy is None:
                    # Approximate entropy when no analytical form
                    entropy_loss = -th.mean(-log_prob)
                else:
                    entropy_loss = -th.mean(entropy)

                entropy_losses.append(entropy_loss.item())

                loss = policy_loss + self.ent_coef * entropy_loss + self.vf_coef * value_loss

                bc_loss, bc_effective_loss = self._compute_bc_losses()
                if bc_loss is not None and bc_effective_loss is not None:
                    loss = loss + bc_effective_loss
                    bc_losses.append(float(bc_loss.detach().cpu().item()))
                    effective = float(bc_effective_loss.detach().cpu().item())
                    bc_effective_losses.append(effective)

                # Calculate approximate form of reverse KL Divergence for early stopping
                # see issue #417: https://github.com/DLR-RM/stable-baselines3/issues/417
                # and discussion in PR #419: https://github.com/DLR-RM/stable-baselines3/pull/419
                # and Schulman blog: http://joschu.net/blog/kl-approx.html
                with th.no_grad():
                    log_ratio = log_prob - rollout_data.old_log_prob
                    approx_kl_div = th.mean((th.exp(log_ratio) - 1) - log_ratio).cpu().numpy()
                    approx_kl_divs.append(approx_kl_div)

                if self.target_kl is not None and approx_kl_div > 1.5 * self.target_kl:
                    continue_training = False
                    if self.verbose >= 1:
                        print(f"Early stopping at step {epoch} due to reaching max kl: {approx_kl_div:.2f}")
                    break

                # Optimization step
                self.policy.optimizer.zero_grad()
                loss.backward()
                # Clip grad norm
                th.nn.utils.clip_grad_norm_(self.policy.parameters(), self.max_grad_norm)
                self.policy.optimizer.step()

            self._n_updates += 1
            if not continue_training:
                break
        explained_var = explained_variance(self.rollout_buffer.values.flatten(), self.rollout_buffer.returns.flatten())

        # Logs
        self.logger.record("train/entropy_loss", np.mean(entropy_losses))
        self.logger.record("train/policy_gradient_loss", np.mean(pg_losses))
        self.logger.record("train/value_loss", np.mean(value_losses))
        self.logger.record("train/approx_kl", np.mean(approx_kl_divs))
        self.logger.record("train/clip_fraction", np.mean(clip_fractions))
        self.logger.record("train/loss", loss.item())
        self.logger.record("train/explained_variance", explained_var)
        self.logger.record("train/n_updates", self._n_updates, exclude="tensorboard")
        self.logger.record("train/clip_range", clip_range)
        if self.clip_range_vf is not None:
            self.logger.record("train/clip_range_vf", clip_range_vf)
        mean_bc_loss = float(np.mean(bc_losses)) if bc_losses else 0.0
        mean_bc_effective_loss = (
            float(np.mean(bc_effective_losses)) if bc_effective_losses else 0.0
        )
        self.logger.record("train/bc_loss", mean_bc_loss)
        self.logger.record(
            "train/bc_effective_loss",
            mean_bc_effective_loss,
        )
        mean_abs_policy_gradient_loss = abs(float(np.mean(pg_losses))) if pg_losses else 0.0
        if mean_abs_policy_gradient_loss > 1e-8:
            self.logger.record(
                "train/bc_ratio_to_policy_loss",
                mean_bc_effective_loss / mean_abs_policy_gradient_loss,
            )
