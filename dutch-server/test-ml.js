/**
 * Script de test manuel pour vérifier les services ML
 * Usage: node test-ml.js
 */

const { BotPersonalityService } = require('./dist/services/BotPersonalityService');
const { PlayerCloningService } = require('./dist/services/PlayerCloningService');

console.log('🧪 Test des services ML...\n');

// Test 1: Personnalités
console.log('1️⃣ Test BotPersonalityService');
try {
  const personalityService = new BotPersonalityService();
  const personalities = personalityService.getAllPersonalities();
  
  console.log(`✅ ${personalities.length} personnalités chargées`);
  personalities.forEach(p => {
    console.log(`   - ${p.name} (${p.id})`);
  });
  
  const marco = personalityService.getPersonality('the_shark');
  console.log(`✅ Marco récupéré: agressivité = ${marco.traits.aggressiveness}`);
  
  const team = personalityService.createBalancedTeam(3);
  console.log(`✅ Équipe créée: ${team.map(p => p.name).join(', ')}`);
  
  console.log('✅ BotPersonalityService fonctionne\n');
} catch (error) {
  console.error('❌ Erreur BotPersonalityService:', error.message);
}

// Test 2: Clonage
console.log('2️⃣ Test PlayerCloningService');
try {
  const cloningService = new PlayerCloningService();
  
  const mockGames = [
    {
      actions: [
        {
          actionType: 'draw_from_deck',
          decisionTime: 1000,
          gameState: { myScore: 15 },
          actionDetails: {},
        },
        {
          actionType: 'draw_from_discard',
          decisionTime: 1200,
          gameState: { myScore: 12 },
          actionDetails: {},
        },
      ],
      calledDutch: true,
      scoreAtDutch: 12,
    },
  ];
  
  cloningService.analyzePlayerGames('test_player', mockGames)
    .then(pattern => {
      console.log(`✅ Pattern analysé: style = ${pattern.playStyle}`);
      console.log(`   - Temps décision moyen: ${pattern.avgDecisionTime}ms`);
      console.log(`   - Seuil Dutch: ${pattern.dutchThresholdPattern}`);
      console.log(`   - Agressivité: ${pattern.aggressivenessScore.toFixed(2)}`);
      
      return cloningService.createClone('test_player', 'Test Player', mockGames);
    })
    .then(clone => {
      console.log(`✅ Clone créé: ${clone.clonedBotId}`);
      console.log(`   - Précision: ${(clone.accuracy * 100).toFixed(0)}%`);
      console.log(`   - Parties analysées: ${clone.gamesAnalyzed}`);
      console.log('✅ PlayerCloningService fonctionne\n');
    })
    .catch(error => {
      console.error('❌ Erreur PlayerCloningService:', error.message);
    });
  
} catch (error) {
  console.error('❌ Erreur PlayerCloningService:', error.message);
}

// Test 3: Vérification des fichiers
console.log('3️⃣ Vérification des fichiers');
const fs = require('fs');
const path = require('path');

const requiredFiles = [
  'dist/services/QLearningService.js',
  'dist/services/NeuralNetworkService.js',
  'dist/services/PlayerCloningService.js',
  'dist/services/BotPersonalityService.js',
  'dist/services/BotLearningService.js',
];

requiredFiles.forEach(file => {
  const fullPath = path.join(__dirname, file);
  if (fs.existsSync(fullPath)) {
    console.log(`✅ ${file}`);
  } else {
    console.log(`❌ ${file} - MANQUANT`);
  }
});

console.log('\n✅ Tests terminés !');
console.log('\n📝 Pour tester complètement:');
console.log('   1. Compiler: npm run build');
console.log('   2. Lancer ce script: node test-ml.js');
console.log('   3. Tester les routes API avec curl ou Postman');
