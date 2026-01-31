# 🧪 Guide de Test des Fonctionnalités ML

## Tests Automatisés (Jest)

Les tests unitaires sont dans `/dutch-server/src/__tests__/`:

```bash
cd dutch-server

# Lancer tous les tests
npm test

# Lancer les tests ML spécifiquement
npm test qlearning
npm test neuralNetwork
npm test playerCloning
npm test botPersonality
```

## Tests Manuels Rapides

### 1. Script de Test Simple

```bash
cd dutch-server

# Compiler le code
npm run build

# Lancer le script de test
node test-ml.js
```

Ce script vérifie :
- ✅ Chargement des 8 personnalités
- ✅ Création d'équipes équilibrées
- ✅ Analyse de patterns de jeu
- ✅ Création de clones
- ✅ Présence des fichiers compilés

### 2. Test des Personnalités via API

```bash
# Démarrer le serveur
npm start

# Dans un autre terminal:

# Lister toutes les personnalités
curl http://localhost:3000/api/bot-learning/personalities

# Récupérer Marco
curl http://localhost:3000/api/bot-learning/personality/the_shark

# Récupérer une personnalité aléatoire
curl http://localhost:3000/api/bot-learning/personality-random

# Créer une équipe de 3 bots
curl http://localhost:3000/api/bot-learning/team/3

# Personnalité par difficulté
curl http://localhost:3000/api/bot-learning/personality/difficulty/hard
```

### 3. Test du Clonage

```bash
# Créer un clone
curl -X POST http://localhost:3000/api/bot-learning/clone-player \
  -H "Content-Type: application/json" \
  -d '{
    "playerId": "player123",
    "playerName": "Alice",
    "games": [
      {
        "actions": [
          {
            "actionType": "draw_from_deck",
            "decisionTime": 1000,
            "gameState": {"myScore": 15},
            "actionDetails": {}
          }
        ],
        "calledDutch": false
      }
    ]
  }'

# Lister les clones
curl http://localhost:3000/api/bot-learning/clones
```

### 4. Test des Stats ML

```bash
# Stats des modèles ML
curl http://localhost:3000/api/bot-learning/ml-stats

# Stats globales
curl http://localhost:3000/api/bot-learning/stats
```

## Vérifications Importantes

### ✅ Checklist de Compilation

```bash
cd dutch-server

# 1. Installer les dépendances
npm install

# 2. Compiler TypeScript
npm run build

# 3. Vérifier qu'il n'y a pas d'erreurs
# Les fichiers suivants doivent exister:
ls dist/services/QLearningService.js
ls dist/services/NeuralNetworkService.js
ls dist/services/PlayerCloningService.js
ls dist/services/BotPersonalityService.js
```

### ✅ Checklist des Répertoires

Les répertoires suivants seront créés automatiquement au premier lancement :

```
dutch-server/data/bot-learning/
├── games/          # Historique des parties
├── profiles/       # Profils des bots
├── qlearning/      # Q-Table
├── neural/         # Réseau de neurones
├── clones/         # Clones de joueurs
└── personalities/  # Personnalités sauvegardées
```

### ✅ Checklist des Fonctionnalités

- [ ] Les 8 personnalités se chargent correctement
- [ ] Les noms sont naturels (Marco, Sophie, Alex, etc.)
- [ ] Création d'équipes équilibrées fonctionne
- [ ] Analyse de patterns de jeu fonctionne
- [ ] Création de clones fonctionne
- [ ] Les routes API répondent
- [ ] Les stats ML sont accessibles
- [ ] Pas d'erreurs dans les logs

## Tests d'Intégration

### Test Complet : Enregistrer une Partie

```bash
# 1. Enregistrer une partie de bot
curl -X POST http://localhost:3000/api/bot-learning/record \
  -H "Content-Type: application/json" \
  -d '{
    "gameId": "test-game-1",
    "botId": "bot-1",
    "botName": "Test Bot",
    "botBehavior": "balanced",
    "botSkillLevel": "silver",
    "startTime": "2026-01-30T15:00:00Z",
    "endTime": "2026-01-30T15:10:00Z",
    "numberOfPlayers": 4,
    "gameMode": "classic",
    "usedSBMM": false,
    "actions": [
      {
        "actionType": "draw_from_deck",
        "turnNumber": 1,
        "timestamp": "2026-01-30T15:00:10Z",
        "gameState": {
          "myScore": 20,
          "cardsInHand": 4,
          "turnPhase": "playing",
          "opponentsAvgScore": 18,
          "deckCardsRemaining": 40
        },
        "actionDetails": {},
        "result": {"newScore": 18}
      }
    ],
    "initialHandSize": 4,
    "finalScore": 15,
    "finalRank": 2,
    "calledDutch": false,
    "wonDutch": false,
    "cardsAtDutch": 0,
    "scoreAtDutch": 0,
    "totalTurns": 1,
    "avgDecisionTime": 1500,
    "powerUsesCount": 0,
    "goodDecisions": 1,
    "badDecisions": 0,
    "opponents": []
  }'

# 2. Vérifier que la partie est enregistrée
curl http://localhost:3000/api/bot-learning/stats

# 3. Vérifier que les modèles ML ont été entraînés
curl http://localhost:3000/api/bot-learning/ml-stats
```

## Dépannage

### Erreur: "Cannot find module"

```bash
# Recompiler
cd dutch-server
npm run build
```

### Erreur: "describe is not defined" dans les tests

C'est normal - les types Jest ne sont pas installés. Les tests fonctionneront quand même avec `npm test`.

### Les personnalités ne se chargent pas

```bash
# Vérifier les logs
pm2 logs dutch-server

# Ou si lancé avec npm start:
# Regarder la console
```

### Les fichiers de données ne sont pas créés

Les répertoires sont créés automatiquement au premier enregistrement de partie. Si ça ne marche pas :

```bash
cd dutch-server
mkdir -p data/bot-learning/{games,profiles,qlearning,neural,clones,personalities}
```

## Commandes Utiles

```bash
# Voir les logs en temps réel
pm2 logs dutch-server --lines 100

# Redémarrer le serveur
pm2 restart dutch-server

# Vérifier le statut
pm2 status

# Nettoyer et recompiler
cd dutch-server
rm -rf dist
npm run build
pm2 restart dutch-server
```

## Résultats Attendus

### Personnalités

```json
{
  "id": "the_shark",
  "name": "Marco",
  "description": "Joueur agressif qui aime prendre le contrôle",
  "traits": {
    "aggressiveness": 0.95,
    "caution": 0.2,
    ...
  }
}
```

### Clone

```json
{
  "playerId": "player123",
  "playerName": "Alice",
  "clonedBotId": "clone_player123_1738251234567",
  "gamesAnalyzed": 1,
  "accuracy": 0.5,
  "pattern": {
    "playStyle": "balanced",
    "aggressivenessScore": 0.5,
    ...
  }
}
```

### Stats ML

```json
{
  "qLearning": {
    "totalStates": 0,
    "totalActions": 0,
    "totalVisits": 0,
    ...
  },
  "neuralNetwork": {
    "architecture": "15 -> 32 -> 16 -> 8",
    "totalParameters": 1080,
    ...
  }
}
```

---

**Note** : Les modèles ML commencent vides et se remplissent au fur et à mesure que des parties sont enregistrées.
