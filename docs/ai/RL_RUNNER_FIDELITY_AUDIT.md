# RL Runner Fidelity Audit

Audit date: 2026-06-30 (Claude Code)
Scope: fidelity of the headless RL v2 runner (`tool/rl_env_runner.dart`) and
AgentInterface v2 / `legal_action_v2` versus the real Dutch'78 gameplay
(`lib/services/game/game_logic.dart`, `lib/providers/game_provider.dart`,
`lib/providers/managers/solo/reaction_timer_manager.dart`,
`lib/models/game_state.dart`).

This document is an audit only. No gameplay/runner code was changed. Evidence is
grounded in source line numbers and in two short traces collected for this audit
(under `/tmp`, never committed):
- `/tmp/dutch_r2d2_v2_action_trace_smoke.jsonl.gz` (legal_scores, 200 decisions)
- `/tmp/dutch_r2d2_v2_action_trace_full.jsonl.gz` (full, 300 decisions)

## Summary

Severity counts: **BLOCKER: 3**, **HIGH: 2**, **MEDIUM: 3**, **LOW: 3**, plus 3 open questions.

Conclusion: **Do NOT train yet.** The three BLOCKERs all stem from one root cause —
the reaction window is *action-bounded* in the runner instead of *time-bounded*
like the real game, and the reaction `match` path has no terminality guard. This
lets a deterministic greedy policy enter an infinite, non-progressing
`match` loop (observed: 100/100 decisions in episode 0), drains the whole deck
into p0's hand via false matches (a strategy impossible under the real 3s timer),
and never sets `done` even though the game reached `phase=ended`. Training or
evaluating on this environment is unreliable until the reaction window is made
faithful and terminating.

## Blockers

| ID | Area | Divergence | Evidence | Risk | Recommended fix |
|----|------|-----------|----------|------|-----------------|
| B1 | Reaction window (B/M) | Real reaction window is a fixed ~3s wall-clock timer that always closes; the runner re-opens the window after every p0 `match` with **no timer, no tick budget, no match-count cap**. The window only closes if p0 chooses `pass_tick`. | Real timer: `reaction_timer_manager.dart` `Timer.periodic(30ms)` → `onTimerEnd` at `_reactionDurationMs` (default `_currentReactionTimeMs = 3000`, `game_provider.dart:78`). Runner: `rl_env_runner.dart:444-447` match branch returns `_observation()` unconditionally; only `pass_tick` ticks bots/advances (`:593-606`). | Infinite reaction loops; enables "drain the deck via false matches" strategy (deck 28→0, hand 4→33 in one window) that cannot exist in the timed real game. | Add a deterministic reaction-window budget (max ticks/matches mirroring the timer) and close the window when exceeded. |
| B2 | Termination / done (F/M) | After a p0 reaction `match`, the runner never checks `_isTerminal()` / deck-empty / `phase==ended`, so it keeps returning non-terminal observations with `done:false` even after the game logically ended. | `rl_env_runner.dart:444-447` (match branch, no `_isTerminal`/`_finalize`); `_isTerminal()` = `phase==ended || dutchCalled` (`:2028-2029`); non-terminal obs emits `'done': false` (`:1014`). `pass_tick` path *does* finalize on deck-empty (`:603`). Trace: 120/200 decisions at `phase=ended`, `done` never True, both episodes truncated at max_steps. | `done=false` after `phase=ended` (explicit BLOCKER criterion); episodes never terminate naturally; eval `reached_max_steps` polluted. | After any p0 reaction match, check `_isTerminal()` and `_finalize()` if ended; ensure `done` propagates whenever `phase==ended`. |
| B3 | legal_action_v2 (K) | The reaction mask always offers `match` + `pass_tick` keyed on `micro==reaction`, ignoring `_gs.phase`. In `phase=ended` with `deck=0` a false `match` is a guaranteed no-op (penalty cannot be drawn), yet it is exposed as a legal, repeatable action. | Mask: `rl_env_runner.dart:887-893` (no `_gs.phase` gating); legality `_legal`/`_isActionLegal` only bounds-check the slot (`:794-800`, `:839-845`). No-op proof: `applyPenalty` returns without adding a card when deck empty (`game_logic.dart:330-332`); runner records nothing when `hand.length` unchanged (`:724-727`). | `legal_action_v2` proposes a non-progressing action (explicit BLOCKER criterion); the agent can pick an action with zero legal effect indefinitely. | Gate the reaction mask on `!_isTerminal()` and on deck availability; do not offer `match` when it cannot have any legal effect. |

## High severity

| ID | Area | Divergence | Evidence | Risk | Recommended fix |
|----|------|-----------|----------|------|-----------------|
| H1 | Reaction model design (B) | Even once bounded, replacing the wall-clock timer with an action-by-action `pass_tick` loop changes the decision structure: the real player reacts under time pressure within a shared 3s window, whereas the RL agent decides, per tick, how long to keep matching. This can teach reaction-timing strategies that do not transfer to the real game. | `reaction_timer_manager.dart` (shared timed window) vs `rl_env_runner.dart:440-606` (per-tick agent-driven window). | Strategy mismatch between trained policy and real game. | Document the chosen abstraction explicitly; cap window length to approximate the timer; add a test asserting bounded window length. |
| H2 | Rewards (L) | The v2 runner per-step reward is `principal=0` + dense `destab` only; there is **no per-step penalty for a false match** and no per-step reward for a successful match. During a long match loop reward is ~0 every step. | `rl_env_runner.dart:1014-1022` (non-terminal `rewards`: principal 0, destab, win_bonus 0); false match adds no reward term. | With an unbounded window and ~0 reward, the agent gets no gradient signal to leave the loop; it can also learn to stall without penalty. | After fixing B1–B3, decide whether a small false-match step penalty is needed (currently false-match cost is only the implicit future score from penalty cards). |

## Medium / Low

| ID | Area | Sev | Divergence | Evidence | Recommendation |
|----|------|-----|-----------|----------|----------------|
| M1 | Termination/truncation (M) | MEDIUM | Two independent caps: Dart `maxTurns` (default 500, `:214`/`:222`) and Python `max_steps` (truncation). Truncated episodes are not `done`; eval stats mix natural ends and truncations. | `rl_env_runner.dart:454` `_guard < maxTurns`; eval `reached_max_steps` from Python. | After B1–B3, most episodes should end naturally; keep `max_steps` only as a safety net and report truncated vs done separately (evaluate already tracks `reached_max_steps`). |
| M2 | RL seat (N) | MEDIUM | The RL seat is `_players[0]` built as a **bot seat** (`isHuman:false`) and uses bot memory structures (`mentalMap`/`knownCards`/`spyMemory`) as its legal belief state. | `rl_env_runner.dart:290` `_rlSeat = _players[0]`; `_buildPlayers` (`:1967-2025`) creates bot players; observation built from bot memory (`:902-957`). | Acceptable and documented (belief state is legal-only); verify no bot-only heuristic leaks into rewards/legal actions. Keep as documented design. |
| M3 | Opponents / players (N) | LOW | `num_players` random 2–6 per episode (or forced via eval options); opponents are bots of varying skill. Faithful to the UI (2–6 players). | `rl_env_runner.dart:22`, `:172-204`, `_buildPlayers`. | Acceptable; documented. |
| O1 | Observation content (J) | LOW | Observation includes derived/interpretive aggregates (`best_match_probability`, `expected_deck_card_value`, `believed_known_score`, hints) beyond raw public facts. | `rl_env_runner.dart:942-957`, `:978-989`. | Not a rule divergence (extra legal info); flagged in `AGENT_INTERFACE_V2.md` as legacy-ish. Acceptable for now. |
| P1 | Headless approximation (P) | LOW | No animations/UI/real-time delays; bot powers use `skipDelay:true`. | `rl_env_runner.dart:512`, `:557`. | Expected and acceptable for headless training. |

## Detailed audit

### A. Normal turn cycle
- Truth: `GameLogic.drawCard` / `discardDrawnCard` / `replaceCard` (`game_logic.dart:104-228`), `nextPlayer` (`:774`).
- Runner: `dutchOrDraw` → `postDraw` micro-phases; `_playBotTurn` mirrors the dataset generator (`:484-520`); `current_player`/`phase`/`micro_phase` exposed (`:966-969`).
- legal_action_v2: `call_dutch`/`continue_draw` then `discard_drawn`/`replace(slot)` (mask `:851-860`).
- Divergence: **No** (faithful). Severity: —. Evidence: code parity + `test_roundtrip.py` check #1. Recommendation: acceptable.

### B. Collective discard / reaction window
- Truth: timed 3s window (`reaction_timer_manager.dart`), all players may match within it, window always closes (`onTimerEnd`→`_endReactionPhase`, `game_provider.dart:654`).
- Runner: action-bounded window; p0 `match` re-invites with no cap (`:440-447`); bots tick on `pass_tick` (`:542-606`).
- legal_action_v2: `pass_tick` + `match(all slots)` every reaction decision (`:887-893`).
- Divergence: **YES**. Severity: **BLOCKER (B1)** + HIGH (H1). Evidence: see B1. Recommendation: fix required before training.

### C. Successful match
- Truth: `matchCard` success removes the card, adds to discard, queues pending power if in reaction (`game_logic.dart:240-308`).
- Runner: `_applyMatchAndRecord` success path records `match_discard` event (`:706-721`); pending powers resolved after window (`:611-638`).
- Divergence: **No** for the success mechanic itself. Severity: LOW. Recommendation: acceptable (but reachability is governed by the BLOCKER window).

### D. Failed match
- Truth: `matchCard` failure → `applyPenalty`; penalty draws a card from deck, **but returns silently if deck empty after refill** (`game_logic.dart:309-353`, esp. `:330-332`).
- Runner: false match records `match_failure_penalty` only if the hand grew (`:724-727`); with deck empty nothing is recorded and state is unchanged.
- Divergence: **YES** (the no-op false match is reachable and repeatable here). Severity: **BLOCKER (B3)**. Evidence: full trace — `hand_sizes=[33,...]`, `deck=0`, `match_failure_penalty` tail, state frozen for 120 steps. Recommendation: fix required.

### E. Empty deck
- Truth: `drawCard` refills or `endGame` (`:104-127`); `_refillDeck` ends the game (or sets `dutchCalled`) when discard ≤ 1 (`:779-797`).
- Runner: `pass_tick`/turn paths finalize on `deck.isEmpty && discardPile.length<=1` (`:584`,`:603`,`:690`); the **reaction match path does not** (`:444-447`).
- Divergence: **YES** (only via the match path). Severity: **BLOCKER (B2)**. Recommendation: fix required.

### F. Phase ended / done
- Truth: `endGame` sets `phase=ended` and reveals known cards (`game_logic.dart:765-772`); the provider ends immediately on `dutchCalled` (`game_provider.dart:846-847`).
- Runner: `_isTerminal()` = `ended || dutchCalled` (`:2028`), but is bypassed by the reaction match branch; non-terminal obs hardcodes `done:false` (`:1014`).
- legal_action_v2 in `phase=ended`: still offers `match`/`pass_tick` (mask not phase-gated).
- Divergence: **YES**. Severity: **BLOCKER (B2/B3)**. Evidence: trace `phase=ended` with `done=false` ×120. Recommendation: fix required.

### G. Dutch
- Truth: solo `callDutch` ends the game immediately (`game_provider.dart:536-540`); ranking via `getFinalRanksWithTies()` with dutch-caller bonus/penalty (`game_state.dart:360-423`).
- Runner: `_isTerminal()` treats `dutchCalled` as terminal; `_finalize()` uses `_gs.getFinalRanksWithTies()` and the rank-normalized reward `1-2*(rank-1)/(n-1)` + win bonus (`:1039-1083`).
- Divergence: **No** (faithful: immediate end + same scoring function). Severity: —. Recommendation: acceptable.
- Note: `call_dutch` is rarely legal in the observed traces (2/200) only because the agent is trapped in the reaction loop, not because of a Dutch-rule bug.

### H. Normal powers (7 / 10 / Valet / Joker)
- Truth: `_checkSpecialPower` (`game_logic.dart:720-731`), `lookAtCard`/`swapCards`/`jokerEffect` (`:355-718`).
- Runner: power micro-phase masks: `power7_look(own)`, `power10_spy(opponents)`, `powerV_swap(all non-spectator players)`, `powerJoker(non-self)` (`:861-886`); Jack legality requires `a != b` (no same-player swap) and includes p0 as a valid `player_a` (`:818-832`); Joker forbids self-target (`:833-836`).
- Divergence: **No** (matches the documented rules; self-Joker forbidden, same-player Jack forbidden, opponent↔opponent and self-included Jack allowed). Severity: LOW. Recommendation: acceptable; add explicit equivalence tests later.

### I. Powers from a match (pending)
- Truth: `_addPendingMatchPower` queues 7/10/V/JOKER during reaction (`game_logic.dart:733-748`).
- Runner: `_preparePendingMatchPowerQueue` orders 7/10 first, then V/JOKER FIFO (`:616-638`); resolves via `_activateNextPendingPowerOrAdvance`.
- Divergence: **No** (matches HANDOFF/UI ordering). Severity: LOW. Recommendation: acceptable.

### J. Memory / hidden information
- Truth: a player legally knows own `mentalMap`/`knownCards`, spied cards (10), public discards.
- Runner: observation exposes only belief/public/spied (`:902-957`); no real hands/scores/deck order.
- Anti-leak: the trace anti-leak scan found **0 forbidden keys** across 200 records; `action_trace_v2` writer rejects forbidden keys.
- Divergence: **No** observed leak. Severity: LOW. Recommendation: acceptable; keep the trace anti-leak scan.

### K. Legal actions
- See B3. The reaction mask exposes a guaranteed no-op (`match` in `phase=ended`/`deck=0`). Severity: **BLOCKER (B3)**.

### L. Rewards
- See H2. Per-step reward is `principal=0` + dense `destab`; terminal reward is rank-normalized + win bonus (`:1039-1083`). No per-step false-match penalty in the v2 runner. During loops reward ≈ 0. Severity: **HIGH (H2)**.

### M. Termination / truncation
- See B2 and M1. `done` (natural end) vs Python `max_steps` truncation; risk of learning to stall is currently mitigated only by reward≈0 (not by a penalty). Severity: BLOCKER (B2) + MEDIUM (M1).

### N. Opponents / random baseline
- Runner opponents are bots of mixed skill; `num_players` 2–6; p0 = `_players[0]` (bot-typed RL seat). The random baseline uses the same runner with a legal-random policy and terminates normally (~45 steps) because it eventually samples `pass_tick`. Severity: MEDIUM (M2) / LOW (M3).

### O. Seeds / determinism
- `reset` seeds `EngineRandom.seed(seed)` then `_buildPlayers` (`:281-290`); per-episode seeds incremental on the Python side. `test_roundtrip.py` check #3 verifies determinism (same seed → identical observations). Severity: LOW. Recommendation: acceptable.

### P. Performance / headless approximation
- No UI/animations; powers `skipDelay:true`. Severity: LOW. Recommendation: acceptable.

## Required fixes before next training

1. **Make the reaction window terminating and bounded (B1+B2).** After any p0
   reaction `match`, check `_isTerminal()` / `deck.isEmpty && discard<=1` and
   `_finalize()` (propagating `done=true`) when the game has ended. Add a
   deterministic reaction budget (max ticks/matches) that closes the window,
   mirroring the real 3s timer. (File: `tool/rl_env_runner.dart` — out of scope
   for the audit commit.)
2. **Phase-gate the reaction legal actions (B3).** Do not expose `match`/`pass_tick`
   when `_isTerminal()` is true or when a `match` cannot have any legal effect
   (deck empty and false match). (File: `tool/rl_env_runner.dart`, mask `:887-893`.)
3. **Re-check reward shaping after B1–B3 (H2).** Decide whether a small per-step
   false-match penalty is warranted once the no-op loop is impossible.

## Tests to add (with the fix, not now)

- Dart: a runner test reproducing "deck drained by false matches in a single
  reaction window" and asserting the episode reaches `done=true` (no infinite loop).
- Dart: assert the reaction mask offers no `match` once `phase==ended`.
- Dart: assert a reaction-window length bound (max ticks/matches).
- Python: a trace-level invariant test — no traced decision has `phase=="ended"`
  with `done==false`; no decision offers an action with a guaranteed-zero effect.
- Python: `analyze_action_trace_v2` assertion that `match_chain_max_length` stays
  below a sane bound on a short eval after the fix.

## Open questions

- OQ1: What is the intended real-game behavior when the deck empties *during* a
  reaction window? The real timer closes the window and `_refillDeck`/`endGame`
  resolves it; the exact intended RL mapping (terminate vs close-window-then-end)
  should be confirmed before fixing B1/B2.
- OQ2: Should a false `match` carry an explicit per-step RL penalty, or is the
  implicit future-score cost of penalty cards sufficient? (Was reward-only in the
  PPO `dutch_env`; absent in the v2 runner reward.)
- OQ3: Is the bot-typed RL seat (`isHuman:false`) the intended long-term design,
  or should a dedicated human-like seat be used for the AgentInterface v2 agent?

## Current recommendation

- **Do not train until BLOCKER B1, B2, B3 are fixed.** They are facets of one
  root cause (non-faithful, non-terminating reaction window) and are individually
  sufficient to create infinite non-progressing loops and `done=false`-after-`ended`.
- After the fix: run a short `full` trace + eval (2–3 episodes, ≤200 steps) and
  confirm `match_chain_max_length` is bounded and episodes reach `done=true`.
- Then collect with an epsilon-greedy policy (not pure greedy) and only then
  resume a controlled training run.
