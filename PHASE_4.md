# 🏆 Phase 4 : Compétition et Évolution

## Vue d'ensemble

La Phase 4 ajoute un écosystème compétitif complet avec :
- **Tournois automatiques** entre bots
- **Évolution génétique** pour optimiser les algorithmes
- **Adaptation de difficulté** selon le niveau du joueur
- **Leaderboard mondial** pour le classement

## 🎯 Objectif Principal

**Les bots doivent s'adapter à ton niveau de jeu :**
- Bronze/Silver : Bots légèrement plus faibles pour rester compétitifs
- Gold/Platinum : Bots plus forts qui te battent systématiquement

## 🧬 Services Implémentés

### 1. TournamentService

Gère les tournois automatiques entre bots.

**Fonctionnalités :**
- Création de tournois (daily, weekly, special)
- Génération de brackets équilibrés (Swiss system)
- Simulation de matchs basée sur MMR
- Calcul automatique des prix

**Exemple d'utilisation :**
```typescript
const tournament = await tournamentService.createTournament(
  'Tournoi Quotidien',
  'daily',
  participants // 4, 8, 16, ou 32 bots
);

await tournamentService.runTournament(tournament.tournamentId);
```

**API :**
```bash
# Créer un tournoi
POST /api/bot-learning/tournament/create
{
  "name": "Tournoi du Vendredi",
  "type": "weekly",
  "participants": [...]
}

# Lancer un tournoi
POST /api/bot-learning/tournament/:id/run

# Récupérer un tournoi
GET /api/bot-learning/tournament/:id

# Lister tous les tournois
GET /api/bot-learning/tournaments?status=completed
```

### 2. GeneticAlgorithmService

Évolution génétique pour optimiser les paramètres des bots.

**Algorithme :**
1. **Sélection** : Tournoi entre 4 bots, garder les 2 meilleurs
2. **Croisement** : Mélange aléatoire des gènes des parents
3. **Mutation** : 15% de chance de mutation par gène
4. **Élitisme** : Garder les 4 meilleurs bots

**Gènes optimisés :**
- Aggressiveness
- Caution
- Risk Tolerance
- Patience
- Dutch Threshold
- Power Usage Rate
- Memory Accuracy
- Adaptability

**Exemple :**
```typescript
// Initialiser la population (20 bots)
const gen1 = await geneticService.initializePopulation();

// Jouer des parties pour calculer la fitness
// ...

// Évoluer vers la génération suivante
const gen2 = await geneticService.evolveGeneration();
```

**API :**
```bash
# Initialiser la population
POST /api/bot-learning/genetic/initialize

# Évoluer vers la prochaine génération
POST /api/bot-learning/genetic/evolve

# Récupérer la population actuelle
GET /api/bot-learning/genetic/population

# Récupérer le meilleur bot
GET /api/bot-learning/genetic/best
```

### 3. AdaptiveDifficultyService

Ajuste automatiquement la difficulté des bots selon le niveau du joueur.

**Analyse du joueur :**
- Taux de victoire
- Score moyen
- Temps de décision
- Nombre de parties

**Niveaux de compétence :**
- **Beginner** : Winrate < 20%, Score > 15
- **Intermediate** : Winrate < 40%, Score > 12
- **Advanced** : Winrate < 60%, Score < 12
- **Expert** : Winrate > 60%, Score excellent

**Ajustement selon le niveau cible :**

| Niveau Cible | Débutant | Intermédiaire | Avancé | Expert |
|--------------|----------|---------------|--------|--------|
| **Bronze**   | -30% MMR | -15% MMR      | -5% MMR | -5% MMR |
| **Silver**   | -20% MMR | -5% MMR       | 0% MMR  | 0% MMR |
| **Gold**     | +10% MMR | +10% MMR      | +20% MMR | +30% MMR |
| **Platinum** | +40% MMR | +40% MMR      | +50% MMR | +60% MMR |

**Exemple :**
```typescript
// Analyser un joueur
const stats = await adaptiveService.analyzePlayer(playerId, games);
// Résultat : { skillLevel: 'advanced', estimatedMMR: 1850 }

// Ajuster la difficulté d'un bot
const adjustment = await adaptiveService.adjustBotDifficulty(
  1500, // MMR de base du bot
  playerId,
  'gold' // Niveau cible
);
// Résultat : { adjustedMMR: 1800, reason: 'Challenge élevé' }
```

**API :**
```bash
# Analyser un joueur
POST /api/bot-learning/adaptive/analyze
{
  "playerId": "player123",
  "games": [...]
}

# Ajuster la difficulté
POST /api/bot-learning/adaptive/adjust
{
  "botBaseMMR": 1500,
  "playerId": "player123",
  "targetSkillLevel": "gold"
}

# Recommander un niveau
GET /api/bot-learning/adaptive/recommend/:playerId
```

### 4. LeaderboardService

Classement mondial des bots.

**Fonctionnalités :**
- Top 100 bots par MMR
- Filtres par niveau et personnalité
- Statistiques globales
- Rising stars (meilleurs taux de victoire)
- Stats par génération (bots génétiques)

**Exemple :**
```typescript
// Mettre à jour le leaderboard
await leaderboard.updateLeaderboard({
  botId: 'bot123',
  botName: 'Marco Clone',
  mmr: 1850,
  wins: 45,
  losses: 15,
  totalGames: 60,
  avgScore: 11.5,
  skillLevel: 'gold',
  personality: 'the_shark',
  lastPlayed: '2026-01-30T16:00:00Z'
});

// Récupérer le top 10
const top10 = leaderboard.getTopBots(10);
```

**API :**
```bash
# Récupérer le leaderboard
GET /api/bot-learning/leaderboard?limit=100

# Stats du leaderboard
GET /api/bot-learning/leaderboard/stats
```

## 📊 Intégration Complète

Tous les services sont intégrés dans `BotLearningService` :

```typescript
const botLearning = new BotLearningService();

// Accès aux services Phase 4
const tournament = botLearning.getTournamentService();
const genetic = botLearning.getGeneticService();
const adaptive = botLearning.getAdaptiveService();
const leaderboard = botLearning.getLeaderboardService();
```

## 🎮 Scénarios d'Utilisation

### Scénario 1 : Tournoi Hebdomadaire Automatique

```typescript
// Chaque vendredi à 20h
const topBots = await botLearning.getTopBots(16);
const tournament = await tournament.createTournament(
  'Tournoi du Vendredi',
  'weekly',
  topBots
);

await tournament.runTournament(tournament.tournamentId);
// Le gagnant reçoit +200 MMR
```

### Scénario 2 : Évolution Génétique Continue

```typescript
// Toutes les 100 parties
if (totalGames % 100 === 0) {
  const newGen = await genetic.evolveGeneration();
  console.log(`Génération ${newGen.generationNumber} créée`);
  console.log(`Meilleur bot : ${newGen.bestBot.botId}`);
}
```

### Scénario 3 : Adaptation au Joueur

```typescript
// Avant chaque partie
const playerGames = await getPlayerHistory(playerId);
const playerStats = await adaptive.analyzePlayer(playerId, playerGames);

// Recommander le niveau
const recommended = adaptive.recommendDifficulty(playerId);

// Ajuster les bots adverses
const adjustedMMR = await adaptive.adjustBotDifficulty(
  botMMR,
  playerId,
  recommended
);
```

## 🚀 Déploiement

Les nouveaux répertoires sont créés automatiquement :
```
data/bot-learning/
├── tournaments/    # Tournois
├── genetic/        # Générations
├── adaptive/       # Stats joueurs
└── leaderboard/    # Classement
```

## 📈 Métriques de Succès

**Objectifs :**
- ✅ Bots Bronze/Silver : 40-60% winrate contre joueurs
- ✅ Bots Gold : 60-70% winrate
- ✅ Bots Platinum : 80%+ winrate
- ✅ Évolution génétique : +10% fitness par génération
- ✅ Tournois : 1 par jour minimum

## 🔄 Cycle de Vie Complet

```
1. Joueur joue des parties
   ↓
2. AdaptiveService analyse le niveau
   ↓
3. Bots ajustés selon le niveau
   ↓
4. Parties enregistrées
   ↓
5. Leaderboard mis à jour
   ↓
6. Tournois automatiques
   ↓
7. Évolution génétique
   ↓
8. Nouveaux bots plus forts
   ↓
Retour à 1
```

## 🎯 Prochaines Améliorations Possibles

- Replay des meilleures parties
- Graphiques d'évolution MMR
- Badges et achievements
- Saisons compétitives
- API publique pour les stats
- Streaming de tournois en direct

---

**Phase 4 est maintenant complète et prête pour la production !** 🎉
