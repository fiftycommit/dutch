# TODO - Finaliser le Refactoring de GameProvider

## 🎯 Objectif
Terminer le refactoring de `game_provider.dart` pour éliminer complètement le couplage fort.

## ⚡ Actions Rapides (Recommandé)

### Option 1: Script Python Automatique
```bash
cd /Users/maxmbey/projets/dutch
python3 refactor_game_provider.py
```

Ce script va automatiquement:
- ✅ Remplacer tous les appels `_playerLearningService` et `_botLearningService`
- ✅ Remplacer tous les appels `BotAI` par `_botAIService`
- ✅ Remplacer tous les appels `StatsService` par `_statsService`

### Option 2: Remplacements Manuels
Si le script ne fonctionne pas, suivre `MIGRATION_GUIDE.md` pour les remplacements manuels.

## 📝 Checklist Détaillée

### 1. Finaliser game_provider.dart
- [ ] Supprimer les lignes qui référencent `_currentGameId` (maintenant dans `_trackingProvider`)
- [ ] Supprimer les lignes qui référencent `_humanActionCounter` (maintenant dans `_trackingProvider`)
- [ ] Remplacer tous les appels tracking par `_trackingProvider`
- [ ] Remplacer tous les appels `BotAI` par `_botAIService`
- [ ] Remplacer tous les appels `StatsService` par `_statsService`
- [ ] Vérifier que le fichier compile: `flutter analyze lib/providers/game_provider.dart`

### 2. Mettre à jour main.dart
- [ ] Ajouter l'import: `import 'core/service_locator.dart';`
- [ ] Appeler `ServiceLocator.setupDefaultServices();` dans `main()`
- [ ] Modifier le `ChangeNotifierProvider` de `GameProvider` pour injecter les dépendances:
```dart
ChangeNotifierProvider(
  create: (_) => GameProvider(
    hapticService: ServiceLocator().get<IHapticService>(),
    statsService: ServiceLocator().get<IStatsService>(),
    botAIService: ServiceLocator().get<IBotAIService>(),
    trackingProvider: ServiceLocator().get<GameTrackingProvider>(),
  ),
)
```

### 3. Compilation et Tests
- [ ] Exécuter: `flutter pub get`
- [ ] Exécuter: `flutter analyze`
- [ ] Corriger les erreurs de compilation éventuelles
- [ ] Lancer l'app: `flutter run`
- [ ] Tester les fonctionnalités principales:
  - [ ] Créer une nouvelle partie
  - [ ] Jouer des cartes
  - [ ] Utiliser des pouvoirs spéciaux
  - [ ] Terminer une partie
  - [ ] Vérifier les statistiques
  - [ ] Tester le mode tournoi

### 4. Nettoyage (Optionnel)
- [ ] Une fois que tout fonctionne, marquer les anciens services comme `@deprecated`
- [ ] Planifier la suppression des anciens services dans une future version

## 🔍 Vérification des Erreurs Courantes

### Si le code ne compile pas:
1. Vérifier que tous les imports sont corrects
2. Vérifier que `ServiceLocator.setupDefaultServices()` est appelé
3. Vérifier que toutes les méthodes de `GameTrackingProvider` sont disponibles
4. Lire attentivement les messages d'erreur du compilateur

### Si l'app crash au démarrage:
1. Vérifier que le ServiceLocator est initialisé avant la création de GameProvider
2. Vérifier que tous les services sont enregistrés dans `setupDefaultServices()`
3. Vérifier les logs pour identifier le service manquant

### Si les fonctionnalités ne marchent pas:
1. Vérifier que les méthodes de tracking sont bien appelées
2. Vérifier que les services sont correctement injectés
3. Ajouter des logs pour débugger

## 📚 Documentation de Référence

- **REFACTORING_NOTES.md**: Analyse détaillée des dépendances
- **MIGRATION_GUIDE.md**: Guide pas à pas avec exemples de code
- **REFACTORING_SUMMARY.md**: Vue d'ensemble du refactoring
- **refactor_game_provider.py**: Script d'automatisation

## 💡 Conseils

1. **Faire des commits fréquents**: Commiter après chaque étape réussie
2. **Tester régulièrement**: Ne pas attendre la fin pour tester
3. **Garder une sauvegarde**: Avoir une copie du code avant refactoring
4. **Lire les erreurs**: Les messages du compilateur Dart sont très explicites

## 🎉 Une fois terminé

Le code sera:
- ✅ Découplé et maintenable
- ✅ Testable avec des mocks
- ✅ Conforme aux principes SOLID et GRASP
- ✅ Prêt pour l'évolution future

## ⏱️ Estimation du Temps Restant

- **Avec le script Python**: 15-30 minutes (script + tests)
- **Manuellement**: 1-2 heures (remplacements + tests)

## 🆘 En Cas de Problème

Si tu rencontres des difficultés:
1. Lire attentivement `MIGRATION_GUIDE.md`
2. Vérifier les exemples de code dans le guide
3. Comparer avec le code de `GameTrackingProvider`
4. Revenir à une version précédente et recommencer étape par étape

Bon courage! 💪
