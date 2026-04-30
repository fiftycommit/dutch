# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Dutch'78 — jeu de cartes mémoire/stratégie. Frontend **Flutter/Dart** (mobile, web, desktop) à la racine ; backend **Node.js/TypeScript** (Socket.IO multijoueur) dans `dutch-server/`.

## Commands

### Flutter (depuis la racine)

```bash
flutter pub get
flutter analyze --no-fatal-infos          # analyse statique (utilisée en CI)
flutter test                               # tous les tests
flutter test test/critical/score_calculation_test.dart   # un seul fichier
flutter test --name "Score Calculation"   # par nom
flutter test integration_test/             # nécessite device/emulator
flutter build web --release
flutter run                                # ou: flutter run -d chrome
```

Web avec FCM VAPID key (cf. README) :
```bash
flutter run -d chrome --dart-define-from-file=env/web.local.json
```

### Server (depuis `dutch-server/`)

```bash
npm install
npm run build                              # TS → JS
npm test                                   # build + node:test runner
npm run dev                                # hot reload
node --test dist/__tests__/gameLogic.test.js   # un seul test (après build)
```

CI : sur push/PR vers `main`/`develop`, lance `flutter analyze --no-fatal-infos` (pas de tests). Le déploiement build le web, SCP vers DigitalOcean, restart PM2.

## Architecture

### State, DI, routing
- **State management :** `Provider` (ChangeNotifierProvider) — pas Riverpod ni Bloc.
- **Routing :** `go_router` configuré dans `lib/router/app_router.dart`.
- **DI :** `ServiceLocator` singleton custom (pas `get_it`) dans `lib/core/service_locator.dart`. Les services sont enregistrés via `lib/core/di/register_*_services.dart`. Tous les services sont exposés derrière des interfaces abstraites `I*` dans `lib/core/interfaces/` (SOLID DIP).
- Dans les tests : enregistrer les mocks via `ServiceLocator` dans `setUp`, appeler `ServiceLocator().reset()` dans `tearDown`.

### Layout `lib/`
- `core/` — DI, interfaces (`i_*.dart`), exceptions, service_locator
- `models/` — `PlayingCard`, `Player`, `GameState`, `GameSettings`…
- `providers/` — providers + sous-dossiers de managers
- `screens/` — `game/`, `menu/`, `multiplayer/`, `auth/`, `friends/`, `shared/`
- `services/` — `game/` (logic, bot_ai, shuffle_strategy, rp_calculator), `learning/`, `matchmaking/`, `multiplayer/`, `auth/`, `ui/` (sound, haptic, stats…), `notifications/`, `platform/`, `web/`
- `widgets/` — `game/`, `dialogs/`, `multiplayer/`, `ui/`
- `utils/` — `ui_constants.dart` (tokens design), `screen_utils.dart`

Barrel files `index.dart` exposent l'API publique de `models/`, `services/`, `widgets/`.

### Web vs natif
Imports conditionnels via le pattern `_stub.dart` (cf. `lib/screens/web_*_stub.dart`).

### Server (`dutch-server/src/`)
`models/`, `services/` (`RoomManager`, `GameLogic`…), `handlers/` (Socket.IO), `routes/` (REST), `middleware/`, `__tests__/`. Tests : `node:test` + `node:assert` natifs (pas Jest). Trois fichiers exclus de la compilation : `neuralNetwork`, `playerCloning`, `qlearning`.

## Conventions

### Dart
- Linter : `flutter_lints` (`analysis_options.yaml`). `use_build_context_synchronously` désactivé projet-wide.
- Indent 2 espaces, single quotes, trailing commas dans widget trees.
- Imports ordonnés : `dart:` → `package:flutter/` → autres `package:` → `package:dutch_game/` → relatifs. Dans les tests : toujours `package:dutch_game/...` pour le code projet.
- Naming : fichiers `snake_case.dart`, classes `PascalCase`, interfaces préfixées `I` (`IHapticService`), enums `PascalCase.camelCase` (`GamePhase.playing`), privés `_prefix`.
- Models : constructeurs nommés / factories (`PlayingCard.create(suit, value)`), `required` sur les params nommés, `final` par défaut.
- Erreurs : `throw Exception('message en français')` dans les services ; `try/catch` dans providers/services qui appellent des APIs externes ; retourner `null`/collection vide dans les lookups plutôt que throw.

### TypeScript (server)
- `strict: true`, ES2020, CommonJS.
- Files : `PascalCase.ts` pour models/services, `camelCase.ts` pour handlers/routes, `*.test.ts` pour tests.
- Indent 2 espaces, single quotes, semicolons.

### Langue
**Strings UI et commentaires en français.** Garder cette convention pour tout nouveau code. Les doc comments `///` référencent SOLID/GRASP quand pertinent.

## Tests Flutter

`test/` reflète `lib/`. Sous-dossiers notables :
- `test/critical/` — règles de base (scoring, phases, pouvoirs, deck, matching)
- `test/integration/`, `test/multiplayer/`, `test/regression/`

Infrastructure :
- `test/flutter_test_config.dart` — auto-loaded, mock SVG asset loading
- `test/test_bootstrap.dart` — `setupAssetMocks()` / `tearDownAssetMocks()`
- `test/mocks/mock_services.dart` — mocks écrits à la main (pas codegen)
- `test/helpers/test_helpers.dart` — factories : `createHumanPlayer()`, `createBotPlayer()`, `createTestGameState()`, `createCard()`

## Design (Dutch'78)

### Audience & ton
Mix casual (familles, amis) et compétitif (tournois). Personnalité : **élégant, tendu, immersif** — la concentration d'une partie de cartes physique. Anti-références : casino flashy, gamification agressive, plastique numérique.

### Direction visuelle
- Thème principal **dark green** (`#0d2818` → `#1a472a`).
- Tons chauds/profonds, touches ambrées pour les états actifs.
- Typographie sobre, lisible, non-décorative.
- Les **SVGs des cartes** sont les héros visuels — les mettre en valeur sans surcharger.
- Animations 150–300ms, purposeful (rappel du geste physique).
- WCAG AA minimum, touch target ≥ 44px, contraste ≥ 4.5:1.

### Règles de design (non-négociables)
1. **Authenticité** — rappeler le jeu physique, préférer chaleur/texture au digital générique.
2. **Tension équilibrée** — états d'urgence (timer rouge, Dutch imminent) clairs mais non agressifs.
3. **Élégance dans la simplicité** — l'espace vide est un outil, pas un manque.
4. **Accessibilité sans compromis**.
5. **Cohérence systémique** — utiliser les tokens de `lib/utils/ui_constants.dart` (`AppColors`, `AppSpacing`, `AppTextStyles`, `AppDurations`). **Ne jamais hardcoder de valeurs visuelles.**

### Fichiers design clés
- `lib/utils/ui_constants.dart` — tokens
- `lib/main.dart` — définitions des 3 thèmes (light / dark / green)
- `lib/models/game_settings.dart` — enum thèmes
- `lib/widgets/game/`, `lib/widgets/ui/` — composants

## Notes
- SDK : Dart `>=3.5.0 <4.0.0`, Flutter stable 3.x, Node.js ES2020+.
- Firebase : Auth, Firestore, Storage, FCM. Config dans `firebase.json`.
- Pas de `.prettierrc` / `.eslintrc` — Dart utilise `flutter_lints`, TS s'appuie sur `tsc --strict`.
