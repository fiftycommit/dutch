# 🤖 Système d'Apprentissage Automatique des Bots

## Vue d'ensemble

Le jeu Dutch intègre un système d'apprentissage automatique qui permet aux bots d'évoluer et de s'améliorer au fil des parties, similaire à un joueur humain. Les données de toutes les parties sont collectées, analysées et utilisées pour ajuster les paramètres des bots.

## Architecture

### 1. Collecte des données (Client Flutter)

**Fichiers :**
- `lib/models/bot_learning_data.dart` : Modèles de données
- `lib/services/bot_learning_service.dart` : Service de logging
- `lib/providers/game_provider.dart` : Intégration

**Données collectées pour chaque partie :**
- Chaque action du bot (pioche, défausse, remplacement, pouvoir spécial)
- État du jeu à chaque moment
- Temps de décision
- Résultat final (score, rang, victoire/défaite)
- Contexte (adversaires, mode de jeu, SBMM)

### 2. Stockage et analyse (Serveur Node.js)

**Fichiers :**
- `dutch-server/src/models/BotLearning.ts` : Types TypeScript
- `dutch-server/src/services/BotLearningService.ts` : Logique métier
- `dutch-server/src/routes/botLearningRoutes.ts` : API REST

**Stockage :**
```
/data/bot-learning/
  games/          # Historique complet des parties
  profiles/       # Profils des bots avec stats et MMR
```

### 3. Système MMR (Matchmaking Rating)

Chaque bot possède un MMR qui évolue selon ses performances :

**MMR Initial :**
- Bronze : 800
- Silver : 1200
- Gold : 1600

**Calcul après chaque partie :**
```
K = 32 (facteur Elo)
performance = (totalPlayers - rank + 1) / totalPlayers
change = K * (performance - 0.5)
newMMR = currentMMR + change
```

### 4. Paramètres appris

Les bots ajustent automatiquement leurs paramètres :

```javascript
{
  aggressiveness: 0.0-1.0,      // Tendance à prendre des risques
  caution: 0.0-1.0,             // Prudence dans les décisions
  dutchThreshold: 10-25,        // Score seuil pour appeler Dutch
  powerUsageRate: 0.0-1.0,      // Fréquence d'utilisation des pouvoirs
  memoryAccuracy: 0.0-1.0,      // Précision de mémorisation
  riskTolerance: 0.0-1.0        // Tolérance au risque
}
```

**Ajustement automatique :**
- Victoire → Renforcement des paramètres actuels
- Défaite → Ajustement vers plus de prudence
- Dutch réussi → Réduction du seuil Dutch
- Dutch raté → Augmentation du seuil Dutch

### 5. Évolution en mode SBMM

En mode SBMM (Skill-Based Matchmaking), les bots évoluent comme les humains :
- MMR qui augmente/diminue selon les performances
- Adaptation progressive des stratégies
- Les meilleurs bots deviennent plus forts au fil du temps

## API Endpoints

### POST `/api/bot-learning/record`
Enregistre une partie complète d'un bot.

**Body :**
```json
{
  "gameId": "string",
  "botId": "string",
  "botName": "string",
  "botBehavior": "fast|aggressive|balanced",
  "botSkillLevel": "bronze|silver|gold",
  "finalScore": number,
  "finalRank": number,
  "actions": [...],
  ...
}
```

### GET `/api/bot-learning/top-bots?limit=10&behavior=fast&skillLevel=gold`
Récupère les meilleurs bots par MMR.

**Response :**
```json
[
  {
    "botId": "fast_gold",
    "mmr": 1850,
    "winRate": 0.65,
    "totalGames": 150,
    ...
  }
]
```

### GET `/api/bot-learning/parameters/:behavior/:skillLevel`
Récupère les paramètres appris d'un bot spécifique.

**Response :**
```json
{
  "aggressiveness": 0.7,
  "caution": 0.4,
  "dutchThreshold": 16,
  ...
}
```

### GET `/api/bot-learning/stats`
Statistiques globales du système d'apprentissage.

## Dashboard Web

Accessible à : `https://dutch-game.me/bot-stats`

**Fonctionnalités :**
- 📊 Stats globales (total parties, bots actifs, taux de victoire moyen)
- 🏆 Leaderboard des bots par MMR
- 📈 Historique des parties récentes
- 🔄 Auto-refresh toutes les 30 secondes

## Utilisation

### Côté Client (Flutter)

Le système s'active automatiquement en mode solo :

```dart
// Dans GameProvider
void createNewGame({
  required List<Player> players,
  bool useSBMM = false,
}) {
  // ...
  
  // Initialisation automatique de l'enregistrement
  for (var player in players) {
    if (!player.isHuman) {
      _botLearningService.startGameRecording(
        gameId: _currentGameId!,
        bot: player,
        gameState: _gameState!,
        usedSBMM: useSBMM,
      );
    }
  }
}

// Fin de partie
void endGame() {
  // Finalisation automatique
  _finalizeBotRecordings();
}
```

### Côté Serveur

Le serveur reçoit et traite automatiquement les données :

```typescript
// Enregistrement d'une partie
await botLearningService.saveGameRecord(record);

// Mise à jour automatique du profil
// - Calcul du nouveau MMR
// - Ajustement des paramètres
// - Sauvegarde dans /data/bot-learning/
```

## Métriques de Performance

### Par Bot
- **Win Rate** : Taux de victoire
- **Avg Score** : Score moyen
- **Avg Rank** : Rang moyen
- **MMR** : Classement Elo
- **Dutch Success Rate** : Taux de réussite des Dutch

### Globales
- Total de parties enregistrées
- Nombre de bots actifs
- Évolution du MMR moyen
- Distribution des niveaux

## Évolutions Futures

### Phase 2 : Machine Learning Avancé
- Réseau de neurones pour prédire les meilleures actions
- Apprentissage par renforcement (Q-Learning)
- Analyse des patterns de jeu des humains

### Phase 3 : Bots Personnalisés
- Création de bots basés sur le style de jeu d'un joueur spécifique
- "Clone" d'un joueur humain
- Bots avec personnalités distinctes

### Phase 4 : Compétition de Bots
- Tournois automatiques entre bots
- Sélection naturelle des meilleurs algorithmes
- Leaderboard public des bots les plus performants

## Sécurité et Vie Privée

- ✅ Seules les données des bots sont collectées
- ✅ Aucune donnée personnelle des joueurs humains
- ✅ Stockage local sur le serveur
- ✅ Pas de tracking ou analytics tiers

## Tests

### Test manuel
1. Lancer une partie solo avec des bots
2. Terminer la partie
3. Vérifier les logs : `🤖 Démarrage enregistrement pour bot...`
4. Consulter le dashboard : `https://dutch-game.me/bot-stats`
5. Vérifier les fichiers : `/data/bot-learning/games/` et `/data/bot-learning/profiles/`

### Test API
```bash
# Stats globales
curl https://dutch-game.me/api/bot-learning/stats

# Top bots
curl https://dutch-game.me/api/bot-learning/top-bots?limit=5

# Paramètres d'un bot
curl https://dutch-game.me/api/bot-learning/parameters/fast/gold
```

## Maintenance

### Nettoyage des anciennes données
```bash
# Garder seulement les 1000 dernières parties
cd /var/www/dutch-server/data/bot-learning/games
ls -t | tail -n +1001 | xargs rm -f
```

### Backup des profils
```bash
# Sauvegarder les profils des bots
tar -czf bot-profiles-$(date +%Y%m%d).tar.gz data/bot-learning/profiles/
```

## Support

Pour toute question ou problème :
- Consulter les logs serveur : `pm2 logs dutch-server`
- Vérifier le dashboard : `/bot-stats`
- Consulter les fichiers de données : `/data/bot-learning/`

---

**Version** : 1.0.0  
**Dernière mise à jour** : Janvier 2026  
**Statut** : ✅ Production Ready
