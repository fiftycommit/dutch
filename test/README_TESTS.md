# Tests des Nouvelles Fonctionnalités Multijoueur

Ce dossier contient les tests pour les nouvelles fonctionnalités ajoutées au mode multijoueur.

## 📁 Structure des Tests

### Tests Unitaires - Services

#### `test/services/emote_service_test.dart`
Tests du service de gestion des émotes :
- ✅ Émission d'événements d'émotes
- ✅ Création d'événements avec timestamp
- ✅ Support de plusieurs listeners
- ✅ Gestion d'envoi rapide d'émotes

#### `test/services/competitive_service_test.dart`
Tests du service de mode compétitif :
- ✅ Stats par défaut pour nouveau joueur
- ✅ Sauvegarde et récupération des stats
- ✅ Calcul correct des tiers selon MMR
- ✅ Calcul du changement de MMR (victoire/défaite)
- ✅ Mise à jour des stats après partie
- ✅ Suivi des séries de victoires
- ✅ Calcul du win rate
- ✅ Limitation du MMR (0-3000)
- ✅ Réinitialisation des stats
- ✅ Couleurs et icônes des tiers

### Tests de Widgets

#### `test/widgets/emote_overlay_test.dart`
Tests du widget d'overlay d'émotes :
- ✅ Affichage de la grille d'émotes
- ✅ Fermeture via bouton close
- ✅ Fermeture via tap sur fond
- ✅ Envoi d'émote au tap
- ✅ Affichage des 12 émotes
- ✅ Animation et affichage du FloatingEmote

#### `test/widgets/competitive_stats_widget_test.dart`
Tests des widgets de stats compétitives :
- ✅ Affichage compact
- ✅ Affichage complet avec toutes les stats
- ✅ Icônes correctes par tier
- ✅ Calcul et affichage du win rate
- ✅ Message de victoire (1ère place)
- ✅ Message de résultat (autres places)
- ✅ Changement MMR positif (vert)
- ✅ Changement MMR négatif (rouge)

### Tests d'Intégration

#### `test/integration/multiplayer_reconnection_test.dart`
Tests d'intégration pour la reconnexion silencieuse :
- ⚠️ Structure de test (nécessite mocking du service)
- ⚠️ Timeout après 3 secondes
- ⚠️ Reconnexion et rejoin de room

**Note**: Ces tests sont des placeholders et nécessitent un mock du `MultiplayerService` pour être pleinement fonctionnels.

## 🚀 Exécution des Tests

### Tous les tests
```bash
flutter test
```

### Tests spécifiques
```bash
# Tests des services
flutter test test/services/

# Tests des widgets
flutter test test/widgets/

# Test spécifique
flutter test test/services/emote_service_test.dart
```

### Avec couverture
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## 📊 Couverture Attendue

Les tests couvrent :
- **EmoteService**: ~95% (toutes les méthodes principales)
- **CompetitiveService**: ~90% (calculs MMR, stats, tiers)
- **EmoteOverlay**: ~80% (interactions utilisateur)
- **CompetitiveStatsWidget**: ~85% (affichage et formatage)

## ⚠️ Notes Importantes

### Erreurs de Lint Normales
Les erreurs de type "Target of URI doesn't exist" dans l'IDE sont normales avant la compilation. Elles disparaissent lors de l'exécution des tests avec `flutter test`.

### Tests d'Intégration
Les tests d'intégration dans `multiplayer_reconnection_test.dart` sont des structures de base. Pour les rendre fonctionnels, il faudrait :

1. **Créer des mocks** pour `MultiplayerService`
2. **Utiliser `mockito`** ou un package similaire :
```yaml
dev_dependencies:
  mockito: ^5.4.0
  build_runner: ^2.4.0
```

3. **Générer les mocks** :
```bash
flutter pub run build_runner build
```

### Dépendances Requises
Assurez-vous que `pubspec.yaml` contient :
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  shared_preferences: ^2.0.0  # Pour CompetitiveService
```

## 🔧 Amélioration des Tests

### Prochaines Étapes
1. Ajouter des mocks pour `MultiplayerService`
2. Implémenter les tests d'intégration complets
3. Ajouter des tests de performance pour les animations
4. Tester les edge cases (émotes spam, MMR extrêmes)
5. Ajouter des tests de régression

### Tests Manquants Suggérés
- Tests de l'animation `AnimatedCardTransition`
- Tests du comportement du provider avec émotes
- Tests de la synchronisation réseau des émotes
- Tests de la persistance des stats compétitives
- Tests de la migration de données (anciennes versions)

## 📝 Exemple d'Exécution

```bash
$ flutter test test/services/emote_service_test.dart

00:01 +5: All tests passed!
```

```bash
$ flutter test test/services/competitive_service_test.dart

00:02 +18: All tests passed!
```

## 🐛 Debugging

Si un test échoue :

1. **Vérifier les logs** : `flutter test --verbose`
2. **Isoler le test** : Utiliser `test('description', () {}, skip: false)`
3. **Ajouter des prints** : `debugPrint()` dans le code testé
4. **Vérifier SharedPreferences** : Réinitialiser avec `SharedPreferences.setMockInitialValues({})`

## ✅ Checklist de Test

Avant de merger :
- [ ] Tous les tests unitaires passent
- [ ] Tous les tests de widgets passent
- [ ] Couverture > 80% pour les nouveaux fichiers
- [ ] Pas de warnings dans les tests
- [ ] Documentation à jour
