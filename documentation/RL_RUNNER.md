# RL Runner — environnement self-play headless (phase 2 RL)

`tool/rl_env_runner.dart` expose une partie Dutch'78 comme un environnement de
Reinforcement Learning piloté par un process externe (Python/PPO) via un
protocole **NDJSON** sur stdin/stdout. Le moteur Dart (`GameLogic` + modèles)
reste la seule vérité de jeu ; le runner n'orchestre que la boucle et la
sérialisation.

Voir aussi : [PROMPT_ML_DATASET.md](PROMPT_ML_DATASET.md) (phase 1 supervisée,
générateur de dataset dont le runner reprend la boucle et le schéma d'observation).

## Compilation (obligatoire pour piloter depuis Python)

```bash
dart compile exe tool/rl_env_runner.dart -o tool/rl_env_runner
```

**Toujours piloter l'exécutable compilé `tool/rl_env_runner`, jamais `dart run`.**

Raison : `dart run tool/rl_env_runner.dart` imprime « Running build hooks… » sur
**stdout** au premier build, ce qui corrompt la première ligne du flux NDJSON et
casse un pilote interactif. L'exécutable compilé démarre proprement : sa première
ligne stdout est directement du JSON (vérifié). Il est aussi plus rapide (pas de
recompilation par lancement).

Le binaire `tool/rl_env_runner` est un artefact de build (~6 Mo) : il est dans
`.gitignore`, il faut le recompiler localement / en CI avant usage.

## Protocole NDJSON (un objet JSON par ligne)

| Message | Sens | Le runner bloque ensuite ? |
|---|---|---|
| `{"type":"reset","seed":S,"episode_id":"e","options":{"max_turns":500}}` | Py → Dart | non : répond par une `observation` |
| `{"type":"observation", ...}` / terminal `{"...","done":true,"info":{...}}` | Dart → Py | oui (attend une `action`) sauf si `done:true` |
| `{"type":"action","kind":K,"params":{...}}` | Py → Dart | débloque, applique, ré-émet une `observation` |
| `{"type":"error","code":C,"message":M,"fatal":bool}` | Dart → Py | non |
| `{"type":"close"}` | Py → Dart | termine le process |

Un message d'action **doit** porter `"type":"action"` (un `{"kind":...}` seul est
rejeté en `BAD_PHASE`). Les 9 `kind` : `call_dutch`, `continue_draw`,
`discard_drawn`, `replace{index}`, `power7_look{index}`,
`power10_spy{target_seat,index}`, `powerV_swap{own_index,target_seat,target_index}`,
`powerJoker{target_seat}`, `skip_power`. Chaque observation embarque un
`action_mask` listant les actions légales de la micro-phase courante.

### Pièges côté pilote Python (vérifiés)
- Lire avec `proc.stdout.readline()`, **pas** `for line in proc.stdout` (read-ahead
  bufferisé → deadlock). Côté Dart, chaque émission est suivie d'un `flush`.
- Tolérer un éventuel préfixe non-JSON sur une ligne (extraire à partir du premier
  `{`) — inutile avec l'exe compilé, prudent en `dart run`.

## Granularité, observation, reward (rappel v1)

- Steps : micro-décisions **A** (`call_dutch`/`continue_draw`), **B**
  (`discard_drawn`/`replace`), **C** (pouvoir/`skip_power`). La **réaction (D) est
  exclue** : le siège RL n'y participe jamais (aucune stratégie bot héritée).
- `num_players` aléatoire **2..6** par épisode (aligné sur le vrai jeu, UI 2-6).
- Observation : croyance par-slot (`mentalMap`/`knownCards`/hints) + public de
  table + `spyMemory` ; jamais la `hand` réelle des slots inconnus ni les cartes
  adverses non espionnées.
- Reward terminale rang-normalisée `1 - 2*(rank-1)/(n-1)` via
  `GameState.getFinalRanksWithTies()`. Steps non terminaux = 0, aucun shaping.

`frozenBotMode` (drapeau interne de `RlEnv`) est **réservé aux tests** (#5 parité
avec le générateur) — jamais activé sur le chemin Python.

## Tests de non-régression

```bash
flutter test test/rl/rl_env_runner_test.dart
```

6 groupes : déterminisme seed, masque d'action, absence de leakage (couvre 5-6
joueurs), épisode complet random, **parité byte-à-byte avec `playOneGame` du
générateur** (frozenBotMode, 100 seeds), pouvoirs 7/10/Valet/Joker.
