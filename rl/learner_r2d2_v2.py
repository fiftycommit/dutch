"""Learner for AgentInterface v2 recurrent Q models (R2D2 core).

The learner wires ``SequenceBatchV2 -> model -> TD loss -> backward ->
optimizer`` with the full R2D2 training mechanics:
- Double-Q factorized targets (via ``config.double_q``);
- importance-sampling weighting of the loss when the batch carries PER weights;
- per-sequence priority computation ``eta*max|delta| + (1-eta)*mean|delta|`` over
  valid (non burn-in, non padding) positions, written back to the replay buffer;
- grad clipping, hard target sync on an interval, and an available soft update.

It does not own rollout collection, the replay buffer, checkpointing, or a long
training loop; those live in ``train_r2d2_v2`` / ``smoke_r2d2_v2``.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import copy
from typing import Any

import torch

import loss_r2d2_v2
import model_r2d2_v2
from replay_buffer_v2 import SequenceBatchV2


@dataclass(frozen=True)
class LearnerConfigV2:
    gamma: float = 0.99
    n_step: int = 1
    learning_rate: float = 1.0e-4
    grad_clip_norm: float | None = 10.0
    target_update_interval: int = 100
    double_q: bool = False
    priority_eta: float = 0.9
    device: str = "cpu"

    def __post_init__(self) -> None:
        if self.gamma < 0.0:
            raise ValueError("gamma must be >= 0")
        if self.n_step <= 0:
            raise ValueError("n_step must be positive")
        if self.learning_rate <= 0.0:
            raise ValueError("learning_rate must be positive")
        if self.grad_clip_norm is not None and self.grad_clip_norm <= 0.0:
            raise ValueError("grad_clip_norm must be positive or None")
        if self.target_update_interval <= 0:
            raise ValueError("target_update_interval must be positive")
        if not 0.0 <= self.priority_eta <= 1.0:
            raise ValueError("priority_eta must be between 0 and 1")


@dataclass
class LearnerStateV2:
    step: int = 0
    last_loss: float | None = None
    metrics: dict[str, float] = field(default_factory=dict)


class R2D2LearnerV2:
    """Small trainer wrapper for one-step smoke updates."""

    def __init__(
        self,
        *,
        online_model: model_r2d2_v2.R2D2AgentV2 | None = None,
        target_model: model_r2d2_v2.R2D2AgentV2 | None = None,
        optimizer: torch.optim.Optimizer | None = None,
        config: LearnerConfigV2 | None = None,
    ) -> None:
        self.config = config or LearnerConfigV2()
        self.device = torch.device(self.config.device)
        self.online_model = online_model or model_r2d2_v2.R2D2AgentV2()
        self.target_model = target_model or copy.deepcopy(self.online_model)
        self.online_model.to(self.device)
        self.target_model.to(self.device)
        self.target_model.eval()
        self.optimizer = optimizer or torch.optim.Adam(
            self.online_model.parameters(),
            lr=self.config.learning_rate,
        )
        self.state = LearnerStateV2()
        self.sync_target()

    def sync_target(self) -> None:
        self.target_model.load_state_dict(self.online_model.state_dict())
        self.target_model.eval()

    def soft_update_target(self, tau: float) -> None:
        if not 0.0 <= tau <= 1.0:
            raise ValueError("tau must be between 0 and 1")
        with torch.no_grad():
            for target_param, online_param in zip(
                self.target_model.parameters(),
                self.online_model.parameters(),
            ):
                target_param.data.mul_(1.0 - tau).add_(online_param.data, alpha=tau)
        self.target_model.eval()

    def train_step(
        self,
        batch: SequenceBatchV2,
        *,
        replay_buffer: Any | None = None,
    ) -> dict[str, float]:
        """Run one optimization step and return scalar metrics.

        When ``batch`` carries importance-sampling weights (prioritized replay),
        the loss is IS-weighted and the per-sequence priorities are written back
        to ``replay_buffer`` (if provided) using ``batch.sample_indices``.
        """

        self.online_model.train()
        self.target_model.eval()
        self.optimizer.zero_grad(set_to_none=True)

        loss_output = loss_r2d2_v2.compute_td_loss_v2(
            self.online_model,
            self.target_model,
            batch,
            gamma=self.config.gamma,
            n_step=self.config.n_step,
            double_q=self.config.double_q,
            is_weights=batch.is_weights,
        )
        loss_output.loss.backward()
        grad_norm = self._clip_or_measure_grad_norm()
        self._assert_finite_gradients()
        self.optimizer.step()

        priorities, mean_priority, max_priority = self._sequence_priorities(loss_output)
        prioritized = batch.is_weights is not None
        if (
            replay_buffer is not None
            and prioritized
            and batch.sample_indices is not None
        ):
            replay_buffer.update_priorities(batch.sample_indices, priorities)

        self.state.step += 1
        if self.state.step % self.config.target_update_interval == 0:
            self.sync_target()

        loss_value = float(loss_output.loss.detach().cpu().item())
        metrics = {
            **loss_output.metrics,
            "loss": loss_value,
            "weighted_loss": loss_value,
            "mean_td_error": loss_output.metrics["mean_abs_td_error"],
            "max_td_error": loss_output.metrics["max_abs_td_error"],
            "mean_priority": float(mean_priority),
            "max_priority": float(max_priority),
            "grad_norm": float(grad_norm),
            "valid_steps": float(loss_output.valid_mask.sum().detach().cpu().item()),
            "learner_step": float(self.state.step),
            "target_synced": (
                1.0
                if self.state.step % self.config.target_update_interval == 0
                else 0.0
            ),
            "double_q": 1.0 if self.config.double_q else 0.0,
            "prioritized": 1.0 if prioritized else 0.0,
            "priority_eta": float(self.config.priority_eta),
        }
        self.state.last_loss = metrics["loss"]
        self.state.metrics = dict(metrics)
        return metrics

    def _sequence_priorities(
        self,
        loss_output: loss_r2d2_v2.LossOutputV2,
    ) -> tuple[list[float], float, float]:
        """R2D2 priority per sequence: ``eta*max|delta| + (1-eta)*mean|delta|``.

        Computed over valid (non burn-in, non padding) positions only. Rows with
        no valid position get priority 0.0; the replay buffer floors stored
        priorities with ``priority_epsilon`` so no stored priority is ever zero.
        """

        eta = self.config.priority_eta
        abs_td = loss_output.td_error.detach().abs()
        valid = loss_output.valid_mask
        priorities: list[float] = []
        for row in range(abs_td.shape[0]):
            mask = valid[row]
            if not bool(mask.any()):
                priorities.append(0.0)
                continue
            row_abs = abs_td[row][mask]
            priority = eta * float(row_abs.max().item()) + (1.0 - eta) * float(
                row_abs.mean().item()
            )
            priorities.append(priority)
        mean_priority = float(sum(priorities) / len(priorities)) if priorities else 0.0
        max_priority = float(max(priorities)) if priorities else 0.0
        return priorities, mean_priority, max_priority

    def _clip_or_measure_grad_norm(self) -> float:
        parameters = [
            param
            for param in self.online_model.parameters()
            if param.grad is not None
        ]
        if not parameters:
            return 0.0
        if self.config.grad_clip_norm is None:
            norms = [param.grad.detach().norm(2) for param in parameters]
            return float(torch.norm(torch.stack(norms), 2).detach().cpu().item())
        grad_norm = torch.nn.utils.clip_grad_norm_(
            parameters,
            max_norm=self.config.grad_clip_norm,
        )
        return float(grad_norm.detach().cpu().item())

    def _assert_finite_gradients(self) -> None:
        for name, param in self.online_model.named_parameters():
            if param.grad is not None and not torch.isfinite(param.grad).all():
                raise FloatingPointError(f"non-finite gradient in {name}")
