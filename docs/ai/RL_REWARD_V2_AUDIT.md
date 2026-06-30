# RL Reward V2 Audit

Audit date: 2026-06-30 (Codex)
Scope: current reward emitted by the v2 Dart runner and the reward actually
stored/optimized by the R2D2 v2 Python stack.

Patch status: updated after `fix(rl): scalarize v2 rewards` by the follow-up
reward rework. Positive intermediate bonuses are now win-gated; penalties are
independent and immediate. Gameplay code was not changed.

## Summary

- The pre-patch v2 reward was **not healthy for retrain**.
- Can we train now? **Only after the win-gated reward patch tests pass,
  collection/retrain can resume from scratch; do not use the old checkpoint.**
- Pre-patch cause: the only reward stored in `TransitionV2.reward` was
  `rewards.principal`. R2D2 therefore learned almost exclusively from sparse
  terminal rank. Dart `destab` and `win_bonus` were emitted but ignored by
  `rollout_v2`, `collect_rollouts_v2`, and `infer_r2d2_v2`.
- H2 was confirmed and patched: false matches receive an immediate scalar reward
  penalty via `rl/reward_v2.py`.
- Follow-up design correction: positive intermediate signals no longer pay on
  losing episodes. They accumulate as `positive_bonus_potential` and are paid on
  the terminal transition only if `p0` wins.
- The terminal rank reward does use the real final ranking function, so a failed
  Dutch caller is ranked last by the game model. That part is mechanically
  faithful, but the reward does not make the Dutch decision explicit enough.
- Recommendation: collect new data only after this patch; retrain **from
  scratch**. Do not fine-tune the old checkpoint.

## Implemented Patch

Shared scalarization lives in `rl/reward_v2.py` and is used by:

- `rl/rollout_v2.py`
- `rl/collect_rollouts_v2.py`
- `rl/infer_r2d2_v2.py`
- `rl/dataset_v2.py` (JSONL roundtrip for components)
- `rl/evaluate_r2d2_v2.py` (reward total + component metrics)
- `rl/action_trace_v2.py` (optional reward components in traces)

Exact formula:

```text
per-step immediate total =
  immediate_penalty
  + terminal_win_reward
  + terminal_loss_reward
  + terminal_win_bonus
  + terminal_failed_dutch_penalty
  + paid_positive_bonus

positive_bonus_potential =
  successful_match_bonus_potential
  + max(0, clip(destab_raw, 0.0, 2.0)) / 256.0

episode finalization:
  if terminal p0 win:
    terminal paid_positive_bonus = sum(positive_bonus_potential over episode)
  else:
    terminal paid_positive_bonus = 0.0
```

Constants:

| Constant | Value | Reason |
|---|---:|---|
| `WIN_REWARD` | `1.0` | Main objective: winning the round. |
| `TERMINAL_LOSS_REWARD` | `0.0` | Losing has no positive terminal reward; penalties still count. |
| `FALSE_MATCH_PENALTY_REWARD` | `-0.05` | Visible immediate cost for match-spam, smaller than the win objective. |
| `SUCCESSFUL_MATCH_BONUS_POTENTIAL` | `0.02` | Recognizes a useful match, but pays only if the episode is won. |
| `FAILED_DUTCH_PENALTY_REWARD` | `-0.25` | Explicit terminal cost for a failed Dutch call when identifiable. |
| `DESTAB_SCALE` | `1/256` | Keeps dense helper potential tiny and non-dominant. |
| `DESTAB_CAP` | `2.0` | Caps dense potential at `<= 0.0078125` per decision. |

False-match shaping is applied only when:

- selected `action_v2.action_type == "match"`;
- the emitted runner observation contains a current-step public event
  `event_type == "match_failure_penalty"`;
- `actor == "p0"`.

`recent_events` is a rolling buffer, so `reward_v2` filters on
`event["step"] == msg["step"]` to avoid reapplying old penalties. Bot false
matches during `pass_tick` are not charged to p0.

Successful matches are detected from the current-step public
`discard_visible/match_discard` event for `p0`. They add
`SUCCESSFUL_MATCH_BONUS_POTENTIAL` to the episode accumulator but do not change
the current step reward unless the episode later ends in a `p0` win.

`win_bonus` from Dart is consumed only on terminal wins. `destab` is treated as a
positive bonus potential, not direct step reward. `principal` remains stored for
diagnostics/backward audit, but it is not added directly to the optimized total:
the optimized terminal objective is `WIN_REWARD` on win and `0.0` on loss,
with independent penalties preserved.

`TransitionV2.reward` stores the finalized `reward_total`. On a winning episode,
`rollout_v2.finalize_episode_rewards_v2` adds the accumulated positive potential
to the terminal transition. On a losing/truncated episode, the potential is not
paid. `TransitionV2.reward_components` stores the components for JSONL
roundtrip, evaluation and trace reporting.

## Pre-Patch Reward Map

| Event / condition | Current reward | Source file/line | Intended effect | Risk |
|---|---:|---|---|---|
| Non-terminal observation | scalar `reward=0.0`; `rewards.principal=0.0` | `tool/rl_env_runner.dart:1087-1094` | Keep terminal rank dominant. | Every non-terminal action has zero optimized reward in R2D2 unless Python composes extra terms, which it currently does not. |
| Terminal rank | `principal = 1 - 2 * (rank - 1) / (n - 1)` | `tool/rl_env_runner.dart:1118-1120` | Reward winning and rank order. Range is `+1..-1`; for 6p ranks are `+1,+0.6,+0.2,-0.2,-0.6,-1`. | Sparse only; weak credit assignment for Dutch timing, false match avoidance, and match quality. |
| Terminal victory margin bonus | Emitted as `win_bonus`, `0.0..0.30` if `rank==1` | `tool/rl_env_runner.dart:1122-1140` | Reward clean wins without dominating rank. | Ignored by v2 Python reward extraction, so it has no learning effect. |
| Dense destabilization | Emitted as positive decrease in current leader threat | `tool/rl_env_runner.dart:341-365`, `1089-1094` | Small auxiliary pressure against the current threat leader. | Ignored by v2 Python reward extraction; if later enabled without caps/composition tests, it can reintroduce reward hacking. |
| R2D2 transition reward extraction | `float(rewards["principal"])` only | `rl/rollout_v2.py:230-234`, `rl/collect_rollouts_v2.py:228-232`, `rl/infer_r2d2_v2.py:358-362` | Store scalar reward for replay/loss. | Drops `win_bonus`, `destab`, and any future reward component unless each extractor is updated. |
| Replay storage | Batch `rewards[t] = transition.reward` | `rl/replay_buffer_v2.py:326-360` | Feed scalar rewards into sequence batches. | Whatever was lost at extraction cannot be recovered at training time. |
| TD target / loss | n-step target sums `batch.rewards` | `rl/loss_r2d2_v2.py:143-164`, `393-433` | Optimize recurrent Q-learning objective. | Learner optimizes sparse terminal principal only. |
| Evaluation total reward | Sum of `transition.reward` | `rl/evaluate_r2d2_v2.py:229-254` | Report policy return. | Eval reward currently reports principal-only return, not the documented hierarchical reward. |
| Action trace reward | Trace writes the same extracted scalar reward | `rl/action_trace_v2.py:157-170`, `rl/analyze_action_trace_v2.py:111-151` | Diagnose behavior/reward. | Trace can report `match_decisions_with_nonzero_reward=0`, but cannot distinguish false-match penalties because none are composed. |
| `call_dutch` action | Immediate terminal principal only; `win_bonus` emitted but ignored | `tool/rl_env_runner.dart:412-415`, `1111-1158`; Python extractors above | End the round immediately and score the final rank. | Successful Dutch gets `+1` only; failed Dutch gets rank penalty, usually `-1`, but no explicit bad-call component or call-timing shaping. |
| Failed Dutch consequence | Failed Dutch caller ranked last active by game ranking | `lib/models/game_state.dart:379-390` | Faithful rule: bad Dutch is last. | Reward relies on rank only; OK mechanically, but tests should lock this via runner reward. |
| Successful Dutch consequence | Dutch caller that wins is forced to rank 1 | `lib/models/game_state.dart:394-406` | Faithful rule: winning Dutch is sole #1. | Same sparse-credit issue; no explicit `dutch_success` component is stored. |
| Draw / continue | `0.0` immediate optimized reward | `tool/rl_env_runner.dart:417-421`; extractors above | Normal game progression. | No cost for delaying except future rank. Could encourage long episodes if terminal learning is weak. |
| Post-draw discard | `0.0` immediate optimized reward | `tool/rl_env_runner.dart:423-458`; extractors above | Let terminal rank judge quality. | No direct quality signal; acceptable only if terminal reward and exploration are strong enough. |
| Post-draw replace | `0.0` immediate optimized reward | `tool/rl_env_runner.dart:435-458`; extractors above | Let terminal rank judge quality. | No direct hand-improvement signal; avoids cheap shaping, but credit assignment is hard. |
| Power actions `7/10/V/JOKER` / skip | `0.0` immediate optimized reward | `tool/rl_env_runner.dart:460-467`, `797-849`; extractors above | Let terminal rank judge power usage. | Power misuse has no immediate cost. This may be acceptable, but needs behavioral tests. |
| Reaction `pass_tick` | `0.0` immediate optimized reward | `tool/rl_env_runner.dart:469-471`, `639-657`; extractors above | Advance the shared timer. | No living cost; repeated waiting is bounded by runner but not discouraged except opportunity cost. |
| Successful reaction match | `0.0` immediate optimized reward | `tool/rl_env_runner.dart:771-787`; extractors above | Remove a matching hand card; future score/rank should improve. | If later rewarded too much, agent can optimize match count instead of winning. Currently no immediate signal. |
| False reaction match | `0.0` immediate optimized reward; game penalty card is applied | `tool/rl_env_runner.dart:771-792`; `lib/services/game/game_logic.dart:330-353`; extractors above | False match should be costly through added card/future rank. | H2 blocker: no visible immediate RL penalty, so match-spam is weakly discouraged and only through sparse future outcome. |
| Empty deck refill for draw/penalty | No direct reward | `lib/services/game/game_logic.dart:104-127`, `779-797`; runner fix routes through game logic | Gameplay fidelity. | OK as mechanics; no reward issue except avoiding no-op loops, now covered by runner fixes/tests. |

## Gameplay Objective

- True objective: **win the round**, not minimize raw score, hand size, or match
  count in isolation.
- Dutch stops the round immediately (`GameLogic.callDutch` sets
  `phase=dutchCalled`, `lib/services/game/game_logic.dart:750-763`).
- Failed Dutch is last active in the real ranking
  (`lib/models/game_state.dart:379-390`).
- Successful Dutch is sole rank 1 even on equal score
  (`lib/models/game_state.dart:394-406`).
- False match adds a penalty card through `applyPenalty`
  (`lib/services/game/game_logic.dart:330-353`) and must also have a visible RL
  penalty.
- Successful match is a tactic: it removes a card and changes top discard, but
  it is not the objective.

## Problems Found

### BLOCKER

1. **H2 confirmed: false match has no immediate optimized penalty.**
   The runner applies the gameplay penalty, but R2D2 reward remains `0.0` until
   terminal rank. This is too sparse to reliably prevent match-spam.

2. **Documented reward components are not consumed by R2D2 v2.**
   Dart emits `destab` and `win_bonus`; Python stores only `principal`. Current
   training/eval/traces therefore do not match the reward design described in
   the handoff.

3. **No test locks reward composition across Dart -> TransitionV2 -> replay -> loss.**
   A future component can be emitted and silently ignored again.

### HIGH

1. **Dutch success/failure is only implicit through rank.**
   This is faithful enough mechanically, but weak for learning the timing of a
   rare immediate-stop action.

2. **Terminal-only principal creates poor credit assignment.**
   Draw, replace, discard, powers, pass, match, and false match all look the same
   at the immediate reward level.

3. **Evaluation reward is misleading.**
   `average_reward` is principal-only. It does not reflect the documented
   hierarchical reward if `win_bonus`/dense components are expected.

### MEDIUM

1. **Successful match has no direct signal.**
   This avoids over-rewarding match count, which is good, but terminal-only
   learning may underuse valid matches. Prefer a tiny bounded reward or purely
   indirect score/rank credit after false-match penalties are fixed.

2. **No explicit anti-stall/living cost.**
   The runner now bounds reaction windows, so this is not a loop blocker, but
   there is still no small cost for unnecessary extra decisions.

3. **Power actions have no local feedback.**
   This may be acceptable for a strict terminal objective, but should be watched
   in action traces.

### LOW

1. `training_signals` expose useful diagnostics (`dutch_would_win_now`,
   `dutch_margin_now`) but v2 does not consume them. That is fine for audit; do
   not leak them into observation.

2. `destab` can be useful later, but should remain optional, clipped, and
   demonstrably unable to dominate terminal rank.

## Final Reward Design

Design goal: **win the round**. Positive intermediate signals are only useful if
they contribute to a won episode; penalties are mistakes and always count.

Rules:

- Winning terminal: `WIN_REWARD + terminal_win_bonus + paid_positive_bonus`.
- Losing terminal: `0.0` positive terminal reward.
- Positive intermediate events (`successful_match`, clipped positive `destab`)
  accumulate as potential and pay only on terminal wins.
- Independent penalties (`false_match_penalty`, failed Dutch when identifiable)
  are applied immediately/terminally regardless of final outcome.
- `principal` remains a raw diagnostic component; it is not optimized directly
  because rank-based negative loss reward conflicts with the confirmed rule
  “lose = 0 terminal + independent penalties”.

Concrete design:

| Component | Value | When paid | Rationale |
|---|---:|---|---|
| `WIN_REWARD` | `+1.0` | Terminal win | Dominant objective. |
| `terminal_win_bonus` | Dart `win_bonus`, `0.0..0.30` | Terminal win only | Clear wins matter, but only after actual victory. |
| `SUCCESSFUL_MATCH_BONUS_POTENTIAL` | `+0.02` | Accumulated; paid only on win | Recognizes useful matches without allowing losing match-farming. |
| `destab_bonus_potential` | `max(0, clip(destab, 0, 2))/256` | Accumulated; paid only on win | Tiny helper signal, cannot dominate victory. |
| `TERMINAL_LOSS_REWARD` | `0.0` | Terminal loss | Losing receives no positive terminal signal. |
| `FALSE_MATCH_PENALTY_REWARD` | `-0.05` | Immediate | Visible anti-match-spam cost, no terminal double-count. |
| `FAILED_DUTCH_PENALTY_REWARD` | `-0.25` | Terminal failed Dutch when identifiable | Bad Dutch stops the round and ranks the caller last. |

Implementation shape:

- `reward_v2.parse_reward_components_v2` derives immediate penalties and
  positive bonus potential from public/current-step runner data.
- `rollout_v2.finalize_episode_rewards_v2` is the only episode-level finalizer.
  It pays accumulated potential on the terminal transition only if `p0` won.
- `rollout_v2`, `collect_rollouts_v2`, and `infer_r2d2_v2` all use the same
  finalization path. Inference traces are buffered until episode finalization so
  terminal trace reward matches `TransitionV2.reward`.
- Components stay out of the policy observation and contain no hidden game info.

## Tests Added

- Python reward unit tests cover false-match penalties on wins/losses,
  successful-match potential paid only on wins, multiple-match accumulation,
  no losing match farming, zero terminal loss reward, negative losing episodes
  with penalties, wins below `WIN_REWARD` after penalties, failed Dutch penalty,
  no terminal double-count, JSONL roundtrip, dataset loader preservation,
  evaluation reward metrics, import side-effect safety, and anti-leak component
  names.
- Existing rollout, collector, inference, evaluation, trace/analyze and
  roundtrip tests were rerun after the patch.

## Recommendation

- Win-gated reward patch implemented. Do not collect new data or train unless
  the patch tests are green in the target environment.
- Retrain from scratch after patch. Do not fine-tune
  `/tmp/dutch_r2d2_v2_first_run_20260630_192728/checkpoint.pt`.
- The implemented patch is conservative: it consumes terminal `win_bonus`, adds
  an explicit false-match penalty, keeps successful-match reward at zero, clips
  and scales `destab`, and adds composition tests.
