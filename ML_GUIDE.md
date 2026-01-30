# 🤖 Guide d'Utilisation du Machine Learning

Ce guide explique comment utiliser les nouvelles fonctionnalités ML du jeu Dutch.

## 🚀 Démarrage Rapide

### 1. Utiliser les Personnalités

```bash
# Récupérer toutes les personnalités
curl https://dutch-game.me/api/bot-learning/personalities

# Récupérer une personnalité aléatoire
curl https://dutch-game.me/api/bot-learning/personality-random

# Récupérer une personnalité par difficulté
curl https://dutch-game.me/api/bot-learning/personality/difficulty/hard

# Créer une équipe équilibrée de 3 bots
curl https://dutch-game.me/api/bot-learning/team/3
```

### 2. Cloner un Joueur

```bash
# Créer un clone à partir de l'historique d'un joueur
curl -X POST https://dutch-game.me/api/bot-learning/clone-player \
  -H "Content-Type: application/json" \
  -d '{
    "playerId": "player123",
    "playerName": "Alice",
    "games": [...]
  }'

# Lister tous les clones
curl https://dutch-game.me/api/bot-learning/clones

# Mettre à jour un clone avec de nouvelles parties
curl -X PUT https://dutch-game.me/api/bot-learning/clone/clone_player123_1234567890 \
  -H "Content-Type: application/json" \
  -d '{
    "games": [...]
  }'
```

### 3. Prédiction d'Actions (Neural Network)

```bash
# Prédire la meilleure action pour un état donné
curl -X POST https://dutch-game.me/api/bot-learning/predict-action \
  -H "Content-Type: application/json" \
  -d '{
    "gameState": {
      "myScore": 12,
      "cardsInHand": 4,
      "turnPhase": "playing",
      "opponentsAvgScore": 15,
      "deckCardsRemaining": 20
    },
    "action": {
      "turnNumber": 5,
      "actionType": "draw_from_deck"
    }
  }'
```

### 4. Statistiques ML

```bash
# Stats des modèles ML
curl https://dutch-game.me/api/bot-learning/ml-stats

# Stats globales
curl https://dutch-game.me/api/bot-learning/stats
```

## 🎭 Les 8 Personnalités

### 1. Marco
**Style :** Agressif
**Quand l'utiliser :** Pour prendre le contrôle de la partie
**Stratégie :** Prend les devants, utilise tous ses pouvoirs rapidement

```javascript
{
  "id": "the_shark",
  "name": "Marco",
  "traits": {
    "aggressiveness": 0.95,
    "caution": 0.2,
    "riskTolerance": 0.9
  }
}
```

### 2. Sophie
**Style :** Méthodique
**Quand l'utiliser :** Pour une stratégie réfléchie
**Stratégie :** Mémorise les cartes, calcule les probabilités

```javascript
{
  "id": "the_professor",
  "name": "Sophie",
  "traits": {
    "calculation": 0.98,
    "observation": 0.95,
    "patience": 0.95
  }
}
```

### 3. Alex
**Style :** Imprévisible
**Quand l'utiliser :** Pour tenter sa chance
**Stratégie :** Change de tactique, prend des risques

```javascript
{
  "id": "the_gambler",
  "name": "Alex",
  "traits": {
    "riskTolerance": 0.95,
    "bluffing": 0.9,
    "adaptability": 0.9
  }
}
```

### 4. Emma
**Style :** Prudente
**Quand l'utiliser :** Pour jouer la sécurité
**Stratégie :** Prend son temps, évite les risques

```javascript
{
  "id": "the_turtle",
  "name": "Emma",
  "traits": {
    "caution": 0.95,
    "patience": 0.9,
    "riskTolerance": 0.15
  }
}
```

### 5. Lucas
**Style :** Adaptatif
**Quand l'utiliser :** Pour s'adapter aux autres joueurs
**Stratégie :** Copie le style des meilleurs, ajuste sa stratégie

```javascript
{
  "id": "the_chameleon",
  "name": "Lucas",
  "traits": {
    "adaptability": 0.98,
    "observation": 0.9,
    "calculation": 0.8
  }
}
```

### 6. Léa
**Style :** Débutante
**Quand l'utiliser :** Pour un niveau facile
**Stratégie :** Découvre le jeu, s'améliore rapidement

```javascript
{
  "id": "the_rookie",
  "name": "Léa",
  "traits": {
    "adaptability": 0.7,
    "learningRate": 0.25
  }
}
```

### 7. Thomas
**Style :** Expérimenté
**Quand l'utiliser :** Pour un adversaire solide
**Stratégie :** Connaît bien le jeu, équilibré

```javascript
{
  "id": "the_veteran",
  "name": "Thomas",
  "traits": {
    "observation": 0.85,
    "calculation": 0.85,
    "adaptability": 0.8
  }
}
```

### 8. Maxime
**Style :** Imprévisible
**Quand l'utiliser :** Pour un jeu complètement fou
**Stratégie :** Actions chaotiques, déstabilise les adversaires

```javascript
{
  "id": "the_psycho",
  "name": "Maxime",
  "traits": {
    "riskTolerance": 0.99,
    "bluffing": 0.95,
    "aggressiveness": 0.85
  }
}
```

## 🧬 Clonage de Joueurs

### Comment ça marche ?

Le système analyse vos parties pour créer un bot qui joue comme vous :

1. **Collecte des données** : Minimum 5 parties recommandées
2. **Analyse des patterns** :
   - Temps de décision moyen
   - Seuil Dutch préféré
   - Agressivité vs prudence
   - Utilisation des pouvoirs
   - Préférences de remplacement de cartes
3. **Création du clone** : Bot avec votre style de jeu
4. **Amélioration continue** : Plus vous jouez, plus le clone est précis

### Précision du Clone

| Parties Analysées | Précision |
|-------------------|-----------|
| < 5 parties       | 50%       |
| 5-10 parties      | 65%       |
| 10-20 parties     | 75%       |
| 20-50 parties     | 85%       |
| 50+ parties       | 95%       |

### Exemple d'utilisation

```typescript
// Côté client Flutter
final games = await gameHistory.getPlayerGames(playerId);

final response = await http.post(
  Uri.parse('https://dutch-game.me/api/bot-learning/clone-player'),
  body: jsonEncode({
    'playerId': playerId,
    'playerName': playerName,
    'games': games,
  }),
);

final clone = jsonDecode(response.body);
print('Clone créé : ${clone['clonedBotId']}');
print('Précision : ${clone['accuracy'] * 100}%');
```

## 🧠 Machine Learning Avancé

### Q-Learning

Le système utilise Q-Learning pour apprendre les meilleures actions :

**Formule :**
```
Q(s,a) = Q(s,a) + α * (r + γ * max(Q(s',a')) - Q(s,a))
```

**Paramètres :**
- α (alpha) = 0.1 : Taux d'apprentissage
- γ (gamma) = 0.95 : Facteur de discount
- ε (epsilon) = 0.2 → 0.05 : Exploration (décroît avec le temps)

**États explorés :** ~1250 états uniques
**Actions par état :** ~5.4 en moyenne

### Réseau de Neurones

Architecture : **15 → 32 → 16 → 8**

**Inputs (15 neurones) :**
1. Score normalisé
2. Cartes en main
3. Score moyen adversaires
4. Cartes restantes
5-7. Phase de jeu (one-hot)
8. Numéro du tour
9. Dutch appelé
10. Pouvoirs utilisés
11. Score à Dutch
12. Rang estimé
13. Cartes visibles
14. Différence avec leader
15. Tours restants

**Outputs (8 neurones) :**
- Probabilité pour chaque action
- Softmax pour normalisation

**Entraînement :**
- 5 epochs par partie
- Learning rate : 0.01
- Backpropagation
- 1080 paramètres entraînables

## 📊 Monitoring et Statistiques

### Dashboard Web

Accessible à : `https://dutch-game.me/bot-stats`

**Métriques disponibles :**
- Total de parties enregistrées
- Nombre de bots actifs
- Taux de victoire moyen
- Distribution MMR
- Top 10 bots par MMR
- Historique des parties récentes

### API Stats

```bash
# Stats globales
curl https://dutch-game.me/api/bot-learning/stats

# Stats ML
curl https://dutch-game.me/api/bot-learning/ml-stats

# Top bots
curl https://dutch-game.me/api/bot-learning/top-bots?limit=10

# Paramètres d'un bot
curl https://dutch-game.me/api/bot-learning/parameters/fast/gold
```

## 🎮 Intégration dans le Jeu

### Utiliser une Personnalité

```dart
// Récupérer une personnalité
final response = await http.get(
  Uri.parse('https://dutch-game.me/api/bot-learning/personality/the_shark'),
);

final personality = jsonDecode(response.body);
final botParams = personality['behaviors'];

// Créer un bot avec cette personnalité
final bot = Player(
  id: 'bot_shark_1',
  name: personality['name'],
  isHuman: false,
  botParameters: botParams,
);
```

### Créer une Équipe Équilibrée

```dart
// Récupérer une équipe de 3 bots
final response = await http.get(
  Uri.parse('https://dutch-game.me/api/bot-learning/team/3'),
);

final team = jsonDecode(response.body) as List;

final bots = team.map((personality) => Player(
  id: 'bot_${personality['id']}',
  name: personality['name'],
  isHuman: false,
  botParameters: personality['behaviors'],
)).toList();
```

### Utiliser un Clone

```dart
// Récupérer un clone
final response = await http.get(
  Uri.parse('https://dutch-game.me/api/bot-learning/clone/$cloneId'),
);

final clone = jsonDecode(response.body);

// Convertir le pattern en paramètres de bot
final botParams = {
  'aggressiveness': clone['pattern']['aggressivenessScore'],
  'caution': 1 - clone['pattern']['riskTakingScore'],
  'dutchThreshold': clone['pattern']['dutchThresholdPattern'],
  'powerUsageRate': clone['pattern']['powerUsageFrequency'],
  // ...
};

final clonedBot = Player(
  id: clone['clonedBotId'],
  name: '${clone['playerName']} (Clone)',
  isHuman: false,
  botParameters: botParams,
);
```

## 🔧 Personnalisation Avancée

### Créer une Personnalité Personnalisée

```bash
curl -X POST https://dutch-game.me/api/bot-learning/personality \
  -H "Content-Type: application/json" \
  -d '{
    "id": "my_custom_bot",
    "name": "Mon Bot Perso",
    "description": "Un bot avec mon style unique",
    "traits": {
      "aggressiveness": 0.6,
      "caution": 0.7,
      "riskTolerance": 0.5,
      "patience": 0.8,
      "adaptability": 0.7,
      "bluffing": 0.4,
      "observation": 0.8,
      "calculation": 0.9
    },
    "behaviors": {
      "dutchThresholdMin": 10,
      "dutchThresholdMax": 15,
      "powerUsageRate": 0.6,
      "memoryAccuracy": 0.85,
      "decisionSpeed": 0.5,
      "preferredStrategy": "balanced_optimal",
      "reactsToOpponents": true,
      "learningRate": 0.1
    },
    "quirks": [
      "Préfère jouer défensivement en début de partie",
      "Devient plus agressif quand en retard"
    ],
    "voiceLines": [
      "Réfléchissons...",
      "Intéressant",
      "Comme prévu"
    ]
  }'
```

## 📈 Optimisation et Performance

### Conseils pour de Meilleurs Bots

1. **Collectez beaucoup de données** : Plus de parties = meilleur apprentissage
2. **Variez les adversaires** : Jouez contre différents styles
3. **Mettez à jour régulièrement** : Les clones s'améliorent avec le temps
4. **Testez différentes personnalités** : Trouvez celle qui vous convient
5. **Créez des équipes équilibrées** : Mélangez agressifs et défensifs

### Maintenance

```bash
# Nettoyer les anciennes parties (garder les 1000 dernières)
cd /var/www/dutch-server/data/bot-learning/games
ls -t | tail -n +1001 | xargs rm -f

# Backup des profils
tar -czf bot-profiles-$(date +%Y%m%d).tar.gz data/bot-learning/profiles/

# Backup des modèles ML
tar -czf ml-models-$(date +%Y%m%d).tar.gz data/bot-learning/qlearning data/bot-learning/neural
```

## 🐛 Dépannage

### Le bot ne s'améliore pas

- Vérifiez que les parties sont bien enregistrées
- Consultez les logs : `pm2 logs dutch-server`
- Vérifiez le dashboard : `/bot-stats`

### Précision du clone faible

- Collectez plus de parties (minimum 20 recommandé)
- Assurez-vous que les parties sont variées
- Mettez à jour le clone régulièrement

### Prédictions incohérentes

- Le réseau de neurones nécessite ~100 parties pour converger
- Vérifiez les stats ML : `/api/bot-learning/ml-stats`
- Redémarrez le serveur si nécessaire

## 📚 Ressources

- **Documentation complète** : `/BOT_LEARNING.md`
- **Dashboard** : `https://dutch-game.me/bot-stats`
- **API Reference** : Voir section API Endpoints dans BOT_LEARNING.md
- **Logs serveur** : `pm2 logs dutch-server`

---

**Version** : 2.0.0  
**Dernière mise à jour** : Janvier 2026
