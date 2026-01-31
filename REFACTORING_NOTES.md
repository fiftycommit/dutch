# Analyse des dépendances de game_provider.dart

## Dépendances directes identifiées

### Services instanciés directement (couplage fort)
1. **BotLearningService** - ligne 27
2. **PlayerLearningService** - ligne 28
3. **HapticService** - lignes 208, 260, 309, 311 (méthodes statiques)
4. **StatsService** - lignes 90, 1033 (méthodes statiques)

### Services utilisés via imports
1. **GameLogic** - utilisé pour toute la logique métier
2. **BotAI** - lignes 796, 877, 894 (méthodes statiques)

### Dépendances UI
1. **BuildContext** - ligne 20, 127 (stocké pour les bots)

## Problèmes identifiés

### 1. Instanciation directe des services
```dart
final BotLearningService _botLearningService = BotLearningService();
final PlayerLearningService _playerLearningService = PlayerLearningService();
```
❌ Couplage fort - impossible de tester ou remplacer
❌ Viole le principe d'inversion de dépendances (DIP)

### 2. Méthodes statiques
```dart
HapticService.cardTap();
HapticService.error();
StatsService.saveGameResult(...);
StatsService.getStats(...);
BotAI.playBotTurn(...);
BotAI.tryReactionMatch(...);
```
❌ Impossible à mocker pour les tests
❌ Couplage fort avec l'implémentation

### 3. Responsabilités multiples
Le GameProvider gère:
- État du jeu
- Logique de jeu
- Tracking ML
- Feedback haptique
- Statistiques
- IA des bots
- Timers de réaction
- Tournois

❌ Viole le principe de responsabilité unique (SRP)

### 4. BuildContext stocké
```dart
BuildContext? _currentContext;
```
❌ Anti-pattern Flutter - peut causer des memory leaks
❌ Couplage avec la couche UI

## Solutions proposées

### Phase 1: Extraction du tracking (FAIT partiellement)
✅ GameTrackingProvider existe déjà
🔄 Besoin de l'utiliser dans GameProvider

### Phase 2: Interfaces pour services UI
Créer:
- `IHapticService` - abstraction pour le feedback haptique
- `IStatsService` - abstraction pour les statistiques
- `IBotAIService` - abstraction pour l'IA des bots

### Phase 3: Injection de dépendances
Refactorer le constructeur de GameProvider:
```dart
GameProvider({
  required IHapticService hapticService,
  required IStatsService statsService,
  required IBotAIService botAIService,
  required GameTrackingProvider trackingProvider,
})
```

### Phase 4: Extraction de la logique bot
Créer un `BotOrchestrationService` pour:
- Gérer les tours des bots
- Coordonner les actions des bots
- Gérer les pouvoirs spéciaux des bots

### Phase 5: Extraction de la logique tournoi
Créer un `TournamentManager` pour:
- Gérer les manches
- Calculer les classements
- Gérer les éliminations

## Ordre de refactoring

1. ✅ Analyser les dépendances
2. Créer les interfaces manquantes (IHapticService, IStatsService, IBotAIService)
3. Intégrer GameTrackingProvider dans GameProvider
4. Modifier le constructeur pour injection de dépendances
5. Refactorer méthode par méthode pour utiliser les abstractions
6. Extraire la logique bot
7. Extraire la logique tournoi
8. Tests et validation
