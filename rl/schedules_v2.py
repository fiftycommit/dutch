"""Annealing schedules for R2D2 v2 (PER beta, exploration epsilon).

This module is deliberately tiny and dependency-free so it can be shared by the
training loop (beta) and the inference/evaluation policy loop (epsilon) without
pulling torch or the runner at import time.

The schedule is a pure function of a step index; callers own the step counter
(learner step for beta, global policy-decision step for epsilon). Nothing here
reads observations, actions, or game state.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class LinearScheduleV2:
    """Linear interpolation from ``start_value`` to ``end_value``.

    - ``step < warmup_steps`` returns ``start_value``;
    - for ``warmup_steps <= step <= warmup_steps + duration_steps`` the value is
      interpolated linearly;
    - beyond ``warmup_steps + duration_steps`` the value is ``end_value``;
    - ``duration_steps == 0`` jumps straight to ``end_value`` after warmup (no
      ambiguous division);
    - with ``clamp=True`` (default) the returned value never leaves the
      ``[min(start, end), max(start, end)]`` band, even with ``clamp`` opting out
      of the progress clamp the band clamp still bounds it. ``clamp=False``
      disables both, allowing extrapolation.
    """

    start_value: float
    end_value: float
    duration_steps: int
    warmup_steps: int = 0
    clamp: bool = True

    def __post_init__(self) -> None:
        if self.duration_steps < 0:
            raise ValueError("duration_steps must be >= 0")
        if self.warmup_steps < 0:
            raise ValueError("warmup_steps must be >= 0")

    def value_at(self, step: int) -> float:
        if step < 0:
            raise ValueError("step must be >= 0")
        if step < self.warmup_steps:
            return float(self.start_value)

        progress_step = step - self.warmup_steps
        if self.duration_steps == 0:
            return float(self.end_value)

        frac = progress_step / self.duration_steps
        if self.clamp:
            frac = min(max(frac, 0.0), 1.0)
        value = self.start_value + (self.end_value - self.start_value) * frac
        if self.clamp:
            low = min(self.start_value, self.end_value)
            high = max(self.start_value, self.end_value)
            value = min(max(value, low), high)
        return float(value)


def linear_schedule_value(
    start: float,
    end: float,
    duration: int,
    step: int,
    *,
    warmup: int = 0,
    clamp: bool = True,
) -> float:
    """Pure-function form of :class:`LinearScheduleV2`."""

    return LinearScheduleV2(
        start_value=start,
        end_value=end,
        duration_steps=duration,
        warmup_steps=warmup,
        clamp=clamp,
    ).value_at(step)


def build_optional_schedule(
    start: float | None,
    end: float | None,
    steps: int | None,
    *,
    name: str,
    minimum: float | None = None,
    maximum: float | None = None,
    warmup: int = 0,
) -> LinearScheduleV2 | None:
    """Build a schedule from a ``(start, end, steps)`` CLI triple.

    Returns ``None`` when none of the three are provided (constant behaviour
    preserved). Raises a clear error when only some are provided so a half-wired
    schedule can never be silently ignored.
    """

    provided = [value is not None for value in (start, end, steps)]
    if not any(provided):
        return None
    if not all(provided):
        raise ValueError(
            f"{name} schedule requires start, end and steps together "
            f"(got start={start}, end={end}, steps={steps})"
        )
    assert start is not None and end is not None and steps is not None
    if steps < 0:
        raise ValueError(f"{name} steps must be >= 0")
    for label, value in (("start", float(start)), ("end", float(end))):
        if minimum is not None and value < minimum:
            raise ValueError(f"{name} {label} must be >= {minimum}")
        if maximum is not None and value > maximum:
            raise ValueError(f"{name} {label} must be <= {maximum}")
    return LinearScheduleV2(
        start_value=float(start),
        end_value=float(end),
        duration_steps=int(steps),
        warmup_steps=warmup,
    )
