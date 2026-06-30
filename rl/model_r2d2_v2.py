"""PyTorch recurrent Q-network skeleton for AgentInterface v2 batches.

This module defines model plumbing only. It does not implement a learner,
target network, prioritized replay, or any training loop.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import torch
from torch import nn

import encoding_v2
from replay_buffer_v2 import SequenceBatchV2


MASK_VALUE = -1.0e9


@dataclass(frozen=True)
class BatchTensorsV2:
    public_features: torch.Tensor
    private_memory_features: torch.Tensor
    event_features: torch.Tensor
    slot_stability_features: torch.Tensor
    action_type_mask: torch.Tensor
    argument_masks: dict[str, torch.Tensor]
    legacy_action_mask: torch.Tensor | None
    burn_in_mask: torch.Tensor
    train_mask: torch.Tensor
    padding_mask: torch.Tensor


@dataclass(frozen=True)
class R2D2OutputV2:
    action_type_q: torch.Tensor
    own_slot_q: torch.Tensor
    match_slot_q: torch.Tensor
    target_player_q: torch.Tensor
    target_slot_q: torch.Tensor
    jack_player_a_q: torch.Tensor
    jack_slot_a_q: torch.Tensor
    jack_player_b_q: torch.Tensor
    jack_slot_b_q: torch.Tensor
    legacy_q: torch.Tensor | None
    hidden_state: torch.Tensor
    burn_in_mask: torch.Tensor
    train_mask: torch.Tensor
    padding_mask: torch.Tensor


def batch_to_tensors(
    batch: SequenceBatchV2,
    *,
    device: torch.device | str | None = None,
) -> BatchTensorsV2:
    target = torch.device(device) if device is not None else None

    def tensor(value: Any, *, dtype: torch.dtype) -> torch.Tensor:
        return torch.as_tensor(value, dtype=dtype, device=target)

    return BatchTensorsV2(
        public_features=tensor(batch.public_features, dtype=torch.float32),
        private_memory_features=tensor(batch.private_memory_features, dtype=torch.float32),
        event_features=tensor(batch.event_features, dtype=torch.float32),
        slot_stability_features=tensor(batch.slot_stability_features, dtype=torch.float32),
        action_type_mask=tensor(batch.action_type_mask, dtype=torch.bool),
        argument_masks={
            name: tensor(mask, dtype=torch.bool)
            for name, mask in batch.argument_masks.items()
        },
        legacy_action_mask=(
            None
            if batch.legacy_action_mask is None
            else tensor(batch.legacy_action_mask, dtype=torch.bool)
        ),
        burn_in_mask=tensor(batch.burn_in_mask, dtype=torch.bool),
        train_mask=tensor(batch.train_mask, dtype=torch.bool),
        padding_mask=tensor(batch.padding_mask, dtype=torch.bool),
    )


class R2D2AgentV2(nn.Module):
    """Small recurrent Q-network consuming ``SequenceBatchV2``.

    The GRU consumes burn-in steps normally. Later loss code should use
    ``train_mask`` and ``padding_mask`` from the returned output.
    """

    def __init__(
        self,
        *,
        public_dim: int | None = None,
        private_dim: int | None = None,
        event_shape: tuple[int, int] | None = None,
        stability_dim: int | None = None,
        hidden_dim: int = 128,
        embed_dim: int = 64,
        legacy_action_dim: int | None = None,
    ) -> None:
        super().__init__()
        shapes = encoding_v2.shapes_v2()
        self.public_dim = public_dim or shapes["public_features"][0]
        self.private_dim = private_dim or shapes["private_memory_features"][0]
        self.event_shape = event_shape or shapes["event_features"]
        self.event_dim = int(self.event_shape[0] * self.event_shape[1])
        self.stability_dim = stability_dim or shapes["slot_stability_features"][0]
        self.hidden_dim = hidden_dim
        self.legacy_action_dim = legacy_action_dim

        self.public_encoder = _mlp(self.public_dim, embed_dim)
        self.private_encoder = _mlp(self.private_dim, embed_dim)
        self.event_encoder = _mlp(self.event_dim, embed_dim)
        self.stability_encoder = _mlp(self.stability_dim, embed_dim)
        self.core = nn.GRU(
            input_size=embed_dim * 4,
            hidden_size=hidden_dim,
            batch_first=True,
        )

        self.action_type_head = nn.Linear(hidden_dim, len(encoding_v2.ACTION_TYPES))
        self.own_slot_head = nn.Linear(hidden_dim, encoding_v2.MAX_SLOTS)
        self.match_slot_head = nn.Linear(hidden_dim, encoding_v2.MAX_SLOTS)
        self.target_player_head = nn.Linear(hidden_dim, encoding_v2.MAX_PLAYERS)
        self.target_slot_head = nn.Linear(
            hidden_dim,
            encoding_v2.MAX_PLAYERS * encoding_v2.MAX_SLOTS,
        )
        self.jack_player_a_head = nn.Linear(hidden_dim, encoding_v2.MAX_PLAYERS)
        self.jack_slot_a_head = nn.Linear(
            hidden_dim,
            encoding_v2.MAX_PLAYERS * encoding_v2.MAX_SLOTS,
        )
        self.jack_player_b_head = nn.Linear(hidden_dim, encoding_v2.MAX_PLAYERS)
        self.jack_slot_b_head = nn.Linear(
            hidden_dim,
            encoding_v2.MAX_PLAYERS * encoding_v2.MAX_SLOTS,
        )
        self.legacy_head = (
            None
            if legacy_action_dim is None
            else nn.Linear(hidden_dim, int(legacy_action_dim))
        )

    def initial_state(
        self,
        batch_size: int,
        *,
        device: torch.device | str | None = None,
    ) -> torch.Tensor:
        target = torch.device(device) if device is not None else None
        return torch.zeros(1, batch_size, self.hidden_dim, device=target)

    def forward(
        self,
        batch: SequenceBatchV2 | BatchTensorsV2,
        hidden_state: torch.Tensor | None = None,
        *,
        apply_masks: bool = True,
    ) -> R2D2OutputV2:
        tensors = batch if isinstance(batch, BatchTensorsV2) else batch_to_tensors(batch)
        batch_size = tensors.public_features.shape[0]
        if hidden_state is None:
            hidden_state = self.initial_state(
                batch_size,
                device=tensors.public_features.device,
            )

        x = torch.cat(
            [
                self.public_encoder(tensors.public_features),
                self.private_encoder(tensors.private_memory_features),
                self.event_encoder(tensors.event_features.flatten(start_dim=2)),
                self.stability_encoder(tensors.slot_stability_features),
            ],
            dim=-1,
        )
        recurrent, next_hidden = self.core(x, hidden_state)

        target_slot = self.target_slot_head(recurrent).view(
            batch_size,
            -1,
            encoding_v2.MAX_PLAYERS,
            encoding_v2.MAX_SLOTS,
        )
        jack_slot_a = self.jack_slot_a_head(recurrent).view(
            batch_size,
            -1,
            encoding_v2.MAX_PLAYERS,
            encoding_v2.MAX_SLOTS,
        )
        jack_slot_b = self.jack_slot_b_head(recurrent).view(
            batch_size,
            -1,
            encoding_v2.MAX_PLAYERS,
            encoding_v2.MAX_SLOTS,
        )
        legacy_q = None if self.legacy_head is None else self.legacy_head(recurrent)

        output = R2D2OutputV2(
            action_type_q=self.action_type_head(recurrent),
            own_slot_q=self.own_slot_head(recurrent),
            match_slot_q=self.match_slot_head(recurrent),
            target_player_q=self.target_player_head(recurrent),
            target_slot_q=target_slot,
            jack_player_a_q=self.jack_player_a_head(recurrent),
            jack_slot_a_q=jack_slot_a,
            jack_player_b_q=self.jack_player_b_head(recurrent),
            jack_slot_b_q=jack_slot_b,
            legacy_q=legacy_q,
            hidden_state=next_hidden,
            burn_in_mask=tensors.burn_in_mask,
            train_mask=tensors.train_mask,
            padding_mask=tensors.padding_mask,
        )
        return _apply_masks(output, tensors) if apply_masks else output


def _mlp(input_dim: int, output_dim: int) -> nn.Sequential:
    return nn.Sequential(
        nn.Linear(input_dim, output_dim),
        nn.ReLU(),
        nn.Linear(output_dim, output_dim),
        nn.ReLU(),
    )


def _apply_masks(output: R2D2OutputV2, tensors: BatchTensorsV2) -> R2D2OutputV2:
    padding_2d = tensors.padding_mask
    action_type_q = _mask_last_dim(output.action_type_q, tensors.action_type_mask)
    own_slot_q = _mask_last_dim(output.own_slot_q, tensors.argument_masks["own_slot"])
    match_slot_q = _mask_last_dim(
        output.match_slot_q,
        tensors.argument_masks["match_slot"],
    )
    target_player_q = _mask_last_dim(
        output.target_player_q,
        tensors.argument_masks["target_player"],
    )
    target_slot_q = _mask_tensor(output.target_slot_q, tensors.argument_masks["target_slot"])
    jack_player_a_q = _mask_last_dim(
        output.jack_player_a_q,
        tensors.argument_masks["player_a"],
    )
    jack_slot_a_q = _mask_tensor(output.jack_slot_a_q, tensors.argument_masks["slot_a"])
    jack_player_b_q = _mask_last_dim(
        output.jack_player_b_q,
        tensors.argument_masks["player_b"],
    )
    jack_slot_b_q = _mask_tensor(output.jack_slot_b_q, tensors.argument_masks["slot_b"])
    legacy_q = output.legacy_q
    if legacy_q is not None and tensors.legacy_action_mask is not None:
        legacy_q = _mask_last_dim(legacy_q, tensors.legacy_action_mask)

    action_type_q = _mask_padding(action_type_q, padding_2d)
    own_slot_q = _mask_padding(own_slot_q, padding_2d)
    match_slot_q = _mask_padding(match_slot_q, padding_2d)
    target_player_q = _mask_padding(target_player_q, padding_2d)
    target_slot_q = _mask_padding(target_slot_q, padding_2d)
    jack_player_a_q = _mask_padding(jack_player_a_q, padding_2d)
    jack_slot_a_q = _mask_padding(jack_slot_a_q, padding_2d)
    jack_player_b_q = _mask_padding(jack_player_b_q, padding_2d)
    jack_slot_b_q = _mask_padding(jack_slot_b_q, padding_2d)
    if legacy_q is not None:
        legacy_q = _mask_padding(legacy_q, padding_2d)

    return R2D2OutputV2(
        action_type_q=action_type_q,
        own_slot_q=own_slot_q,
        match_slot_q=match_slot_q,
        target_player_q=target_player_q,
        target_slot_q=target_slot_q,
        jack_player_a_q=jack_player_a_q,
        jack_slot_a_q=jack_slot_a_q,
        jack_player_b_q=jack_player_b_q,
        jack_slot_b_q=jack_slot_b_q,
        legacy_q=legacy_q,
        hidden_state=output.hidden_state,
        burn_in_mask=output.burn_in_mask,
        train_mask=output.train_mask,
        padding_mask=output.padding_mask,
    )


def _mask_last_dim(values: torch.Tensor, mask: torch.Tensor) -> torch.Tensor:
    return values.masked_fill(~mask.to(values.device), MASK_VALUE)


def _mask_tensor(values: torch.Tensor, mask: torch.Tensor) -> torch.Tensor:
    return values.masked_fill(~mask.to(values.device), MASK_VALUE)


def _mask_padding(values: torch.Tensor, padding_mask: torch.Tensor) -> torch.Tensor:
    view_shape = list(padding_mask.shape) + [1] * (values.ndim - padding_mask.ndim)
    return values.masked_fill(padding_mask.to(values.device).view(*view_shape), MASK_VALUE)
