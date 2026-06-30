"""Smoke tests for R2D2 v2 annealing schedules.

Run from rl/:
    uv run python test_schedules_v2.py
"""

from __future__ import annotations

import schedules_v2


def test_step_zero_is_start() -> None:
    sched = schedules_v2.LinearScheduleV2(start_value=1.0, end_value=0.0, duration_steps=10)
    if sched.value_at(0) != 1.0:
        raise AssertionError("step 0 should return start_value")


def test_midpoint_interpolates() -> None:
    sched = schedules_v2.LinearScheduleV2(start_value=0.0, end_value=1.0, duration_steps=10)
    if abs(sched.value_at(5) - 0.5) > 1e-9:
        raise AssertionError(f"midpoint interpolation wrong: {sched.value_at(5)}")


def test_after_duration_is_end() -> None:
    sched = schedules_v2.LinearScheduleV2(start_value=1.0, end_value=0.1, duration_steps=10)
    if abs(sched.value_at(10) - 0.1) > 1e-9 or abs(sched.value_at(99) - 0.1) > 1e-9:
        raise AssertionError("value after duration should be end_value")


def test_warmup_holds_start_then_interpolates() -> None:
    sched = schedules_v2.LinearScheduleV2(
        start_value=1.0, end_value=0.0, duration_steps=4, warmup_steps=3
    )
    if sched.value_at(2) != 1.0:
        raise AssertionError("warmup should hold start_value")
    if sched.value_at(3) != 1.0:
        raise AssertionError("first post-warmup step should equal start_value")
    if abs(sched.value_at(5) - 0.5) > 1e-9:
        raise AssertionError(f"interpolation after warmup wrong: {sched.value_at(5)}")
    if abs(sched.value_at(7) - 0.0) > 1e-9:
        raise AssertionError("value at warmup+duration should be end_value")


def test_clamp_keeps_within_bounds() -> None:
    sched = schedules_v2.LinearScheduleV2(start_value=1.0, end_value=0.1, duration_steps=5)
    value = sched.value_at(1000)
    if value < 0.1 or value > 1.0:
        raise AssertionError(f"clamp let value leave bounds: {value}")
    if value != 0.1:
        raise AssertionError("clamped value past duration should be end_value")


def test_clamp_false_extrapolates() -> None:
    sched = schedules_v2.LinearScheduleV2(
        start_value=0.0, end_value=1.0, duration_steps=5, clamp=False
    )
    # progress 10/5 = 2.0 -> value 2.0 (extrapolated, no clamp).
    if abs(sched.value_at(10) - 2.0) > 1e-9:
        raise AssertionError(f"clamp=False should extrapolate: {sched.value_at(10)}")


def test_duration_zero_jumps_to_end() -> None:
    sched = schedules_v2.LinearScheduleV2(start_value=1.0, end_value=0.0, duration_steps=0)
    if sched.value_at(0) != 0.0 or sched.value_at(5) != 0.0:
        raise AssertionError("duration 0 should return end_value")


def test_invalid_parameters_raise() -> None:
    try:
        schedules_v2.LinearScheduleV2(start_value=1.0, end_value=0.0, duration_steps=-1)
    except ValueError:
        pass
    else:
        raise AssertionError("negative duration did not raise")
    try:
        schedules_v2.LinearScheduleV2(
            start_value=1.0, end_value=0.0, duration_steps=1, warmup_steps=-1
        )
    except ValueError:
        pass
    else:
        raise AssertionError("negative warmup did not raise")
    try:
        schedules_v2.LinearScheduleV2(start_value=1.0, end_value=0.0, duration_steps=1).value_at(-1)
    except ValueError:
        pass
    else:
        raise AssertionError("negative step did not raise")


def test_pure_function_matches_dataclass() -> None:
    value = schedules_v2.linear_schedule_value(1.0, 0.0, 4, 2)
    sched = schedules_v2.LinearScheduleV2(start_value=1.0, end_value=0.0, duration_steps=4)
    if value != sched.value_at(2):
        raise AssertionError("pure function diverged from dataclass")


def test_build_optional_schedule_all_none_partial() -> None:
    if schedules_v2.build_optional_schedule(None, None, None, name="x") is not None:
        raise AssertionError("no flags should yield no schedule")
    built = schedules_v2.build_optional_schedule(1.0, 0.0, 5, name="x")
    if built is None or built.duration_steps != 5:
        raise AssertionError("full triple did not build a schedule")
    try:
        schedules_v2.build_optional_schedule(1.0, None, 5, name="x")
    except ValueError as exc:
        if "together" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("partial triple did not raise")


def test_build_optional_schedule_bounds() -> None:
    try:
        schedules_v2.build_optional_schedule(1.5, 0.0, 5, name="epsilon", minimum=0.0, maximum=1.0)
    except ValueError as exc:
        if "<=" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("out-of-range epsilon start did not raise")


def main() -> int:
    tests = [
        test_step_zero_is_start,
        test_midpoint_interpolates,
        test_after_duration_is_end,
        test_warmup_holds_start_then_interpolates,
        test_clamp_keeps_within_bounds,
        test_clamp_false_extrapolates,
        test_duration_zero_jumps_to_end,
        test_invalid_parameters_raise,
        test_pure_function_matches_dataclass,
        test_build_optional_schedule_all_none_partial,
        test_build_optional_schedule_bounds,
    ]
    print("=== test_schedules_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
