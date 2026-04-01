# Refactor bot `Difficile`

Date: 2026-04-01

## Objectif

Remplacer le duo historique `Or` / `Platine` par un seul palier fort appelé
`Difficile`, en gardant le meilleur des deux mondes:

- la précision mécanique et la fiabilité du `Platine`
- les garde-fous stratégiques manquants sur certains coups trop agressifs
- une UX plus simple pour le joueur: `Facile` / `Moyen` / `Difficile`

## Principe retenu

Le refactor ne consiste pas à renommer l'UI.

Le principe appliqué est:

- créer un vrai profil moteur `Difficile`
- faire converger les anciens chemins `gold` et `platinum` vers ce profil
- conserver temporairement `gold` et `platinum` comme alias techniques de
  compatibilité
- supprimer plus tard ces anciens noms du code public et des contrats si
  nécessaire

## Ce qui a été refait

### 1. Nouveau profil fort unique

Dans [lib/services/game/bot/bot_difficulty.dart](/Users/max/projets/dutch/lib/services/game/bot/bot_difficulty.dart),
un nouveau profil `BotDifficulty.difficult` a été créé.

Choix retenu:

- mémoire parfaite
- aucune confusion au swap
- vitesse de réaction maximale
- précision maximale au match

Autrement dit, la base mécanique reste au niveau de l'ancien `Platine`.

Les anciens `gold` et `platinum` pointent désormais vers ce profil comme alias
de compatibilité.

### 2. Fusion du cerveau fort dans la logique de phase

Dans [lib/services/game/bot/bot_config.dart](/Users/max/projets/dutch/lib/services/game/bot/bot_config.dart):

- les anciens bots `gold` et `platinum` utilisent maintenant la même logique
  contextuelle de phase
- `getSkillDifficulty()` convertit `gold` et `platinum` vers
  `BotDifficulty.difficult`

Effet recherché:

- un seul comportement fort réel en partie
- plus de divergence cachée entre deux anciens paliers très proches

### 3. Fusion de la logique de remplacement de cartes

Dans [lib/services/game/bot/bot_card_strategy.dart](/Users/max/projets/dutch/lib/services/game/bot/bot_card_strategy.dart),
les anciens tiers internes `gold` et `platinum` ont été remplacés par un seul
tiers `difficult`.

Le profil `Difficile` garde:

- la priorité forte sur l'information
- la réactivité sur les matchs
- l'opportunisme des bons paliers

Mais il évite certains excès de l'ancien `Platine`.

Garde-fou ajouté:

- si le bot n'a plus qu'un seul inconnu et que sa main connue est déjà très
  basse, il peut jeter une très mauvaise pioche au lieu d'écraser cet inconnu
  avec une grosse carte

Le but est d'éviter les swaps absurdes du type:

- main déjà proche d'un bon Dutch
- une grosse pioche arrive
- le bot remplace quand même son dernier inconnu uniquement pour "résoudre"
  l'information

### 4. Fusion de la logique de Dutch

Dans [lib/services/game/bot/bot_dutch_strategy.dart](/Users/max/projets/dutch/lib/services/game/bot/bot_dutch_strategy.dart),
les anciens tiers `gold` et `platinum` ont aussi été fusionnés en un seul tiers
`difficult`.

Le profil `Difficile` garde:

- la lecture contextuelle avancée
- la gestion de la pression de table
- la logique de course de fin
- le blocage sur incertitude issue d'un Valet non revalidé

Le profil `Difficile` ne garde pas tel quel:

- certains raccourcis trop agressifs de l'ancien `Platine`
- certains auto-Dutch trop permissifs sur des fenêtres faibles

Le nouveau profil est donc:

- plus fin que l'ancien `Or`
- moins punting que certains cas de l'ancien `Platine`

### 5. Alignement des aides annexes

Les composants annexes ont été alignés sur `Difficile`:

- analyse de menace
- mémoire hardcore
- gestion des pouvoirs
- matchmaking bot
- logs

Objectif:

- éviter qu'un bot fort utilise un cerveau fusionné dans un module, mais garde
  encore des seuils d'ancien `Or` ou `Platine` dans un autre

## Ce qui a été adapté dans l'interface

Solo et multijoueur affichent maintenant:

- `Facile`
- `Moyen`
- `Difficile`

Le mode `Mix` est affiché à part dans une bulle dédiée.

Cela a été fait dans:

- [lib/screens/game/game_setup_screen.dart](/Users/max/projets/dutch/lib/screens/game/game_setup_screen.dart)
- [lib/screens/multiplayer/lobby/multiplayer_lobby_screen.dart](/Users/max/projets/dutch/lib/screens/multiplayer/lobby/multiplayer_lobby_screen.dart)
- [lib/screens/menu/ai_profile_widgets.dart](/Users/max/projets/dutch/lib/screens/menu/ai_profile_widgets.dart)
- [lib/screens/menu/rules_screen.dart](/Users/max/projets/dutch/lib/screens/menu/rules_screen.dart)

## Compatibilité temporaire

À ce stade:

- `gold` et `platinum` existent encore dans certains chemins techniques
- mais ils sont rabattus vers le nouveau palier `Difficile`

Cela permet:

- de ne pas casser les anciennes préférences utilisateur
- de ne pas casser certains flux SBMM ou sérialisations existantes
- de migrer progressivement sans régression produit immédiate

## État actuel

Ce qui est vrai maintenant:

- le palier fort utilisé en jeu est un vrai profil fusionné
- l'UI n'expose plus `Or`
- le cerveau fort n'est plus séparé en deux branches concurrentes `gold` /
  `platinum`

Ce qui reste à faire plus tard:

- supprimer définitivement les anciens noms `gold` et `platinum` des enums,
  compatibilités et contrats si on veut un nettoyage complet

## Validation

Analyse statique exécutée avec:

```bash
flutter analyze --no-fatal-infos
```

Résultat:

- pas d'erreur de compilation sur les fichiers touchés
- un `info` non bloquant déjà existant sur un commentaire doc dans
  `bot_power_handler.dart`
