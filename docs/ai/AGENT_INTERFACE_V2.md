# AgentInterface v2 - Specification technique

## Objectif

AgentInterface v2 doit exposer au futur agent Dutch'78 une interface fidele au
vrai jeu, sans etre limitee par `MaskablePPO`, `OBS_DIM=147` ou l'action space
plat actuel.

Le but prioritaire est le win rate et la capacite a apprendre des strategies
complexes dans un POMDP a information cachee. PPO feed-forward et
`rl/encoding.py` restent des elements legacy/baseline tant que le runner v2 et
un encodeur recurrent dedie ne sont pas stabilises.

## Etat actuel

Deja utile pour AgentInterface v2 :

- `micro_phase` expose les decisions principales : debut de tour, post-draw,
  pouvoir, reaction.
- `reaction` est disponible pour p0 avec `pass_tick` et `match(slot)`.
- `pendingMatchPowers` est resolu cote headless.
- Valet complet cote RL : `player_a`, `slot_a`, `player_b`, `slot_b`.
- Joker ne peut plus cibler soi-meme.
- `recent_events` brut est le prochain commit separe attendu. Il expose les
  premiers faits publics : `drawn_discard`, `exchange_discard`,
  `match_discard`, `match_failure_penalty`.
- La main propre connue legalement est exposee via `mentalMap` et `knownCards`.
- Les cartes adverses vues legalement avec un 10 sont exposees via `spyMemory`.
- `top_discard`, tailles de main, discard size, deck size et action masks sont
  disponibles.

Encore legacy PPO :

- `OBS_DIM=147` et vectorisation fixe dans `rl/encoding.py`.
- `N_ACTIONS=6199`, principalement a cause du Valet complet encode a plat.
- Signaux compactes ou interpretatifs dans l'observation :
  `best_match_probability`, `proxy_threat`, `expected_deck_card_value`,
  `believed_total_score_estimate`, `expected_unknown_value_sum`,
  `has_doublon`, `doublon_count`, hints qualitatifs.
- `rl/evaluate_behavior_v3.py`, `rl/dutch_env.py` et `rl/train_parallel.py`
  restent branches sur l'interface PPO actuelle.

Ces elements peuvent rester pour la baseline, mais ne doivent pas definir
l'interface cible.

## Vocabulaire memoire

Ne pas parler de "double memoire" comme si le bot avait deux memoires
separees. Le modele reel est :

- `hand` : vraie main moteur. Elle contient les vraies cartes et ne doit jamais
  etre exposee a la policy si la carte n'est pas legalement connue.
- `mentalMap` : memoire/croyance du joueur. Pour chaque slot, carte que le
  joueur pense avoir.
- `knownCards` : indicateur binaire de validite/confiance par slot. Il dit si le
  joueur considere ce slot comme connu.
- `spyMemory` : cartes adverses vues legalement avec un 10, indexees par
  joueur et slot.
- hints : indices flous sur cartes inconnues. Ils sont utiles pour les bots
  actuels, mais doivent etre documentes comme legacy/heuristiques tant qu'ils
  ne sont pas remplaces par des faits publics ou de la memoire apprise.

AgentInterface v2 doit utiliser les termes `mentalMap`, `knownCards`,
`validity`, `confidence`, `age`, `source` et `invalidation`.

## Structure cible

### 1. `raw_public_state`

Faits publics instantanes, sans interpretation :

```json
{
  "phase": "reaction",
  "micro_phase": "reaction",
  "turn_count": 12,
  "action_count": 48,
  "current_player": "p2",
  "top_discard": {
    "card_visible": true,
    "value": "7",
    "match_value": "7",
    "points": 7
  },
  "discard_size": 18,
  "deck_size": 24,
  "hand_sizes": {"p0": 3, "p1": 4, "p2": 2},
  "dutch_called": false,
  "dutch_caller": null,
  "pending_match_powers": [
    {"owner": "p1", "card_value": "V", "card_points": 11}
  ],
  "active_players": ["p0", "p1", "p2"]
}
```

Interdits dans ce bloc :

- vraies mains adverses ;
- vrais scores adverses ;
- ordre du deck ;
- carte gardee apres exchange ;
- labels de verite.

### 2. `recent_events`

Journal ordonne d'evenements publics. Format minimal :

```json
{
  "step": 42,
  "turn_count": 8,
  "action_count": 31,
  "phase": "reaction",
  "event_type": "discard_visible",
  "actor": "p0",
  "target": null,
  "card_visible": true,
  "card_value": "5",
  "card_match_value": "5",
  "card_points": 5,
  "slot": 1,
  "discard_reason": "match_discard",
  "replaced_slot": null,
  "public_effect": null
}
```

Evenements a supporter par etapes :

- deja prioritaire : `drawn_discard`, `exchange_discard`, `match_discard`,
  `match_failure_penalty`;
- ensuite : `valet_swap`, `joker_shuffle`, `power_7_look`, `power_10_spy`,
  `dutch_call`, `round_end`.

Les informations privees legalement revelees a p0, par exemple une carte vue
avec un 10, peuvent etre emises avec `private_to: "p0"`. Elles restent de la
policy input pour p0, mais pas des faits publics globaux.

### 3. `legal_private_memory`

Ce que p0 sait legalement.

Pour sa propre main :

```json
{
  "own_hand_memory": [
    {
      "slot": 0,
      "known": true,
      "believed_card": {"value": "7", "match_value": "7", "points": 7},
      "validity": 1.0,
      "confidence": 1.0,
      "age_actions": 6,
      "age_turns": 1,
      "source": "power_7",
      "invalidated_by": null
    },
    {
      "slot": 1,
      "known": false,
      "believed_card": null,
      "validity": 0.0,
      "confidence": 0.0,
      "age_actions": null,
      "age_turns": null,
      "source": null,
      "invalidated_by": "exchange"
    }
  ]
}
```

Sources possibles :

- `initial_look`;
- `power_7`;
- `joker_confirm`;
- `retained_memory`;
- `drawn_replace_self`.

Invalidations possibles :

- `exchange`;
- `valet`;
- `joker`;
- `match`;
- `slot_shift`;
- `penalty`;
- `unknown`.

Pour les adversaires :

```json
{
  "opponent_memory": [
    {
      "player_id": "p2",
      "slot": 3,
      "known": true,
      "card": {"value": "R", "match_value": "R", "points": 13},
      "source": "power_10",
      "age_actions": 12,
      "age_turns": 2,
      "validity": 1.0,
      "invalidated_by": null
    }
  ]
}
```

Cette structure vient de `spyMemory`, jamais de la vraie main adverse.

### 4. `slot_stability`

Faits temporels publics, sans interpretation strategique :

```json
{
  "slot_stability": {
    "p2": [
      {
        "slot": 0,
        "present": true,
        "turns_since_slot_last_changed": 4,
        "actions_since_slot_last_changed": 19,
        "slot_changed_this_turn": false,
        "replacements_of_other_slots_since_slot_last_changed": 2,
        "post_draw_opportunities_since_slot_last_changed": 3
      }
    ]
  }
}
```

Un slot est considere change quand :

- le joueur remplace ce slot apres pioche ;
- un Valet touche ce slot ;
- un Joker melange la main du joueur ;
- une carte de ce slot est matchee et retiree ;
- une penalite ou suppression modifie les indices de main.

Ne pas encoder :

- "ce slot est bon" ;
- "il faut viser ce slot" ;
- "le joueur protege cette carte".

### 5. `legal_action_interface`

L'action space plat actuel est acceptable pour PPO legacy, mais il n'est pas
ideal pour AgentInterface v2. Le Valet complet cree un gros bloc sparse dans
`Discrete(6199)`.

Format JSON v2 recommande :

```json
{
  "action_type": "jack_swap",
  "player_a": "p2",
  "slot_a": 4,
  "player_b": "p0",
  "slot_b": 1
}
```

Autres exemples :

```json
{"action_type": "draw"}
{"action_type": "call_dutch"}
{"action_type": "discard_drawn"}
{"action_type": "replace", "own_slot": 2}
{"action_type": "power_7_look", "own_slot": 1}
{"action_type": "power_10_spy", "target_player": "p3", "target_slot": 0}
{"action_type": "joker_shuffle", "target_player": "p4"}
{"action_type": "reaction_pass_tick"}
{"action_type": "reaction_match", "match_slot": 2}
```

Cote reseau, utiliser des tetes factorisees :

- `head_action_type`;
- `head_own_slot`;
- `head_target_player`;
- `head_target_slot`;
- `head_player_a`;
- `head_slot_a`;
- `head_player_b`;
- `head_slot_b`;
- masques par tete selon la phase et l'action choisie.

Un adaptateur legacy peut convertir `action_id` plat vers action v2 et
inversement pendant la transition. Il faudra ajouter des tests d'equivalence
entre les deux formats.

### 6. `debug_eval_labels`

Bloc separe, jamais dans la policy input :

```json
{
  "debug_eval_labels": {
    "true_scores": {"p0": 12, "p1": 18},
    "true_winner": "p0",
    "full_hands": null,
    "hidden_deck": null
  }
}
```

Ces donnees sont reservees a l'evaluation, aux tests anti-fuite ou a des labels
auxiliaires explicitement separes. Elles ne doivent pas etre consommees par la
policy.

## Observation v2 : JSON d'abord, vectorisation ensuite

Deux formats sont possibles.

### A. JSON raw_obs

Avantages :

- fidele au jeu ;
- facile a auditer ;
- compatible event replay et R2D2/DRQN ;
- evolutif sans recalculer un `OBS_DIM` a chaque ajout.

Inconvenients :

- necessite un encodeur separe avant entrainement neural ;
- moins directement compatible avec Stable-Baselines/PPO.

### B. Vectorisation v2

Avantages :

- entree dense pour reseau ;
- masques et tensors predecoupables ;
- compatible batch/replay.

Inconvenients :

- risque de figer trop tot une mauvaise representation ;
- plus difficile a auditer pour les fuites ;
- oblige a definir bornes, padding, normalisation et event windows.

Recommandation : commencer par JSON brut, puis creer un encodeur R2D2 separe de
`rl/encoding.py`.

## Regles anti-fuite

La policy input ne doit jamais contenir :

- mains adverses completes ;
- vrais scores adverses ;
- ordre ou contenu cache du deck ;
- carte piochée gardee apres exchange ;
- carte de penalite cachee ;
- cartes echangees par Valet si elles ne sont pas visibles legalement ;
- resultat final futur ;
- labels auxiliaires ou debug.

La policy input peut contenir :

- cartes visibles en defausse ;
- cartes vues legalement ;
- `mentalMap` et `knownCards` du siege agent ;
- `spyMemory` legal ;
- tailles de main ;
- slot remplace publiquement ;
- evenements publics ;
- Joker/Valet publics comme changements de slots, sans cartes cachees ;
- stabilite des slots ;
- action masks.

## Strategie de migration

1. Committer `recent_events` brut separement.
2. Ajouter `slot_stability` brut dans le runner.
3. Ajouter `legal_private_memory` brut base sur `mentalMap`, `knownCards` et
   `spyMemory`.
4. Ajouter age/source/invalidation de l'information si absent.
5. Ajouter `action_v2` JSON en parallele de l'action id legacy.
6. Ajouter tests d'equivalence `action_id` legacy <-> `action_v2`.
7. Creer un encodeur R2D2/DRQN separe de `rl/encoding.py`.
8. Marquer PPO comme baseline legacy.
9. Ne supprimer PPO qu'apres un runner v2 fonctionnel et teste.

## Tests requis

Tests structurels :

- `raw_public_state` ne contient aucune main adverse.
- `legal_private_memory.own_hand_memory` n'expose `believed_card` que si
  `knownCards[slot] == true`.
- `opponent_memory` ne contient que des cartes issues de `spyMemory`.
- `exchange_discard` expose `replaced_slot`, mais pas la carte gardee.
- `match_failure_penalty` n'expose pas la carte de penalite.
- `valet_swap` n'expose pas les cartes echangees si elles sont cachees.
- `joker_shuffle` n'expose pas les nouveaux emplacements.
- `debug_eval_labels` est absent de la policy input.

Tests action :

- chaque action legacy actuellement legale a une representation `action_v2`
  equivalente ;
- chaque `action_v2` illegale est rejetee ;
- Valet meme joueur reste interdit ;
- Joker self reste interdit ;
- les masques par tete ne proposent pas d'argument illegal.

## Ce qu'on ne fait pas encore

- Pas de refactor gameplay.
- Pas de modification de `GameLogic`.
- Pas de suppression PPO.
- Pas de vectorisation v2 immediate.
- Pas de R2D2/DRQN avant stabilisation de l'interface.
- Pas de labels debug dans la policy input.
