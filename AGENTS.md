# AGENTS.md — Dutch'78 Card Game

## Project Overview

Full-stack card game with a **Flutter/Dart** frontend (mobile, web, desktop) and a **Node.js/TypeScript** backend (Socket.IO multiplayer server). The project lives at the repo root with the server in `dutch-server/`.

---

## Build / Lint / Test Commands

### Flutter Frontend (run from repo root)

```bash
# Install dependencies
flutter pub get

# Static analysis (used in CI)
flutter analyze --no-fatal-infos

# Run ALL tests
flutter test

# Run a SINGLE test file
flutter test test/critical/score_calculation_test.dart

# Run tests matching a name pattern
flutter test --name "Score Calculation"

# Run a test directory
flutter test test/critical/

# Run integration tests (requires device/emulator)
flutter test integration_test/

# Build web release
flutter build web --release

# Run app
flutter run
```

### Node.js Backend (run from `dutch-server/`)

```bash
# Install dependencies
npm install

# Build (TypeScript → JavaScript)
npm run build

# Run ALL tests (builds first, uses Node.js built-in test runner)
npm test

# Run a SINGLE test file
npm run build && node --test dist/__tests__/gameLogic.test.js

# Dev server with hot reload
npm run dev

# Start production server
npm start
```

### CI Pipeline

- **On push/PR to main/develop:** `flutter analyze --no-fatal-infos` (no test run in CI)
- **Deploy:** Builds Flutter web, SCP to DigitalOcean, PM2 restart

---

## Code Style Guidelines

### Dart / Flutter

**Linter:** `package:flutter_lints/flutter.yaml` (see `analysis_options.yaml`).
`use_build_context_synchronously` is suppressed project-wide.

**Formatting:**
- 2-space indentation (Dart standard)
- Default Dart formatter line length (80 chars)
- Single quotes for strings
- Trailing commas in argument lists and widget trees (Flutter convention)

**Import order** (grouped with blank lines between groups):
1. `dart:` SDK imports (`dart:async`, `dart:math`)
2. `package:flutter/` framework imports
3. Third-party `package:` imports (`package:provider/...`)
4. Project `package:dutch_game/` imports
5. Relative imports within the same module (`'../models/player.dart'`)

In **test files**, always use `package:dutch_game/...` absolute imports for project code. Use relative imports only for test-local files (mocks, helpers).

**Barrel files:** `index.dart` exists in `models/`, `services/`, `widgets/` — re-export public API from a directory.

**Naming:**
- Files: `snake_case.dart` (`game_logic.dart`, `bot_ai.dart`)
- Classes: `PascalCase` (`GameLogic`, `ServiceLocator`)
- Abstract interfaces: `I` prefix (`IHapticService`, `IBotAIService`, `IStatsService`)
- Enums: `PascalCase` name, `camelCase` values (`GamePhase.playing`, `BotBehavior.fast`)
- Variables / methods: `camelCase` (`knownCardCount`, `calculateScore()`)
- Private members: underscore prefix (`_random`, `_calculatePoints()`)
- Constants: `camelCase`

**Types:**
- Use named constructors and factory constructors for models (e.g., `PlayingCard.create(suit, value)`)
- Prefer `required` named parameters for clarity
- Use `final` for immutable local variables and fields

**Error handling:**
- Throw `Exception('message')` with descriptive French messages for service errors
- Use `try/catch` in providers and services that call external APIs
- Return `null` or empty collections rather than throwing in lookup methods

**Architecture patterns:**
- **State management:** `Provider` (ChangeNotifierProvider) — not Riverpod or Bloc
- **Routing:** `go_router` (see `lib/router/app_router.dart`)
- **DI:** Custom `ServiceLocator` singleton (not get_it). Register services in `lib/core/di/register_*_services.dart`
- **Interfaces:** All services accessed through abstract interfaces in `lib/core/interfaces/i_*.dart` (SOLID DIP)
- **Comments:** Written in French. Doc comments (`///`) reference SOLID/GRASP principles where relevant

### TypeScript (Server)

**Config:** `strict: true`, ES2020 target, CommonJS modules (see `dutch-server/tsconfig.json`).

**Formatting:**
- 2-space indentation
- Single quotes for imports
- Semicolons required

**Naming:**
- Service/model files: `PascalCase.ts` (`RoomManager.ts`, `GameLogic.ts`)
- Handler/route files: `camelCase.ts` (`connectionHandler.ts`, `botLearningRoutes.ts`)
- Test files: `camelCase.test.ts` (`gameLogic.test.ts`, `roomManager.multiplayer.test.ts`)
- Interfaces/types: `PascalCase` (`PlayingCard`, `Room`, `Player`)
- Functions: `camelCase` (`createCard()`, `calculatePoints()`)

**Imports:**
- Named imports: `import { Server } from 'socket.io';`
- Default imports: `import express from 'express';`
- Relative imports: `import { RoomManager } from './services/RoomManager';`

**Tests:** Use Node.js built-in test runner (`import { describe, it } from 'node:test'`) with `assert` (`import assert from 'node:assert'`). No Jest or Mocha.

---

## Testing Conventions

### Flutter Tests (`test/`)

Directory structure mirrors `lib/`:
- `test/critical/` — Core game rule tests (scoring, phases, powers, deck, matching)
- `test/models/`, `test/services/`, `test/providers/`, `test/widgets/`, `test/screens/`
- `test/integration/` — End-to-end solo game flow
- `test/multiplayer/` — Multiplayer protocol tests
- `test/regression/` — Regression tests for specific bugs

**Test infrastructure:**
- `test/flutter_test_config.dart` — Global config that mocks SVG asset loading (auto-loaded)
- `test/test_bootstrap.dart` — `setupAssetMocks()` / `tearDownAssetMocks()` helpers
- `test/mocks/mock_services.dart` — Hand-written mocks implementing interfaces (not code-gen)
- `test/helpers/test_helpers.dart` — Factory functions: `createHumanPlayer()`, `createBotPlayer()`, `createTestGameState()`, `createCard()`

**Test pattern:** Always register mock services via `ServiceLocator` in `setUp`, and call `ServiceLocator().reset()` in `tearDown`.

### Server Tests (`dutch-server/src/__tests__/`)

17 test files using Node.js built-in `node:test`. Three are excluded from compilation: `neuralNetwork`, `playerCloning`, `qlearning`.

---

## Key Directories

```
lib/
├── core/              # DI registration, interfaces, service locator
├── models/            # Data models (PlayingCard, Player, GameState, etc.)
├── providers/         # Provider state management + manager subdirs
├── router/            # go_router configuration
├── screens/           # UI screens (game, menu, multiplayer, auth, friends)
├── services/          # Business logic (game/, bot/, multiplayer/, auth/, etc.)
├── widgets/           # Reusable widgets (game, dialogs, UI components)
└── utils/             # Utilities (constants, screen helpers)

dutch-server/
├── src/
│   ├── models/        # TypeScript data models
│   ├── services/      # Business logic services
│   ├── handlers/      # Socket.IO event handlers
│   ├── routes/        # REST API routes
│   ├── middleware/     # Express/Socket middleware
│   └── __tests__/     # Server tests
```

---

## Important Notes

- **Language:** UI strings and code comments are in **French**. Keep new comments in French for consistency.
- **SDK requirements:** Dart SDK `>=3.5.0 <4.0.0`, Flutter stable 3.x, Node.js with ES2020 support
- **No .prettierrc / .eslintrc** — Dart uses `flutter_lints`; TypeScript relies on `tsc --strict`
- **Firebase:** The project uses Firebase Auth, Firestore, Storage, and FCM. Config is in `firebase.json`. Do not commit `.env` files or credentials.
- **Platform code:** Conditional imports for web vs. native use `_stub.dart` pattern (see `lib/screens/web_*_stub.dart`).
