import 'package:flutter/foundation.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../models/game_settings.dart';
import '../game/bot/bot_dutch_strategy.dart';

// Imports conditionnels pour le web et natif
import 'game_logger_native.dart' if (dart.library.html) 'game_logger_web.dart' as platform;

/// Service de logging pour enregistrer toutes les actions de jeu
/// Fonctionne sur toutes les plateformes (web, mobile, desktop)
class GameLoggerService {
  static GameLoggerService? _instance;
  static GameLoggerService get instance => _instance ??= GameLoggerService._();

  GameLoggerService._();

  final StringBuffer _logBuffer = StringBuffer();
  String? _currentGameId;
  int _turnNumber = 0;
  int _roundNumber = 1;
  bool _isEnabled = true;

  /// Active/désactive le logging
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Démarre une nouvelle partie et crée le fichier de log
  Future<void> startNewGame({
    required List<Player> players,
    required int targetScore,
  }) async {
    if (!_isEnabled) return;

    _logBuffer.clear();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    _currentGameId = 'game_$timestamp';
    _turnNumber = 0;
    _roundNumber = 1;

    _logBuffer.writeln('═══════════════════════════════════════════════════════════════');
    _logBuffer.writeln('  DUTCH GAME LOG - ${DateTime.now()}');
    _logBuffer.writeln('═══════════════════════════════════════════════════════════════');
    _logBuffer.writeln('');
    _logBuffer.writeln('CONFIGURATION:');
    _logBuffer.writeln('  Target Score: $targetScore');
    _logBuffer.writeln('  Players: ${players.length}');
    _logBuffer.writeln('');
    _logBuffer.writeln('JOUEURS:');
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      final type = p.isHuman ? 'HUMAIN' : 'BOT (${p.botBehavior?.name ?? "unknown"})';
      _logBuffer.writeln('  [${i + 1}] ${p.name} - $type');
    }
    _logBuffer.writeln('');
    _logBuffer.writeln('═══════════════════════════════════════════════════════════════');
    _logBuffer.writeln('');

    // Sur les plateformes natives, aussi sauvegarder dans un fichier
    if (!kIsWeb) {
      await platform.initLogFile(_currentGameId!, _logBuffer.toString());
    }
  }

  /// Log le début d'une nouvelle manche
  Future<void> logRoundStart({
    required int roundNumber,
    required List<Player> players,
  }) async {
    if (!_isEnabled) return;

    _roundNumber = roundNumber;
    _turnNumber = 0;

    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('┌─────────────────────────────────────────────────────────────┐');
    buffer.writeln('│                    MANCHE $roundNumber                              │');
    buffer.writeln('└─────────────────────────────────────────────────────────────┘');
    buffer.writeln('');
    buffer.writeln('Mains initiales:');
    for (final p in players) {
      final cards = p.hand.map((c) => _cardToString(c)).join(', ');
      buffer.writeln('  ${p.name}: [$cards] = ${p.calculateScore()} pts');
    }
    buffer.writeln('');

    _logBuffer.write(buffer.toString());
    await _appendToFile(buffer.toString());
  }

  /// Log le début du tour d'un joueur avec ses connaissances
  Future<void> logTurnStart({
    required Player player,
    required int turnNumber,
    List<Player>? allPlayers,
  }) async {
    if (!_isEnabled) return;

    _turnNumber = turnNumber;

    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('┌─── Tour $_turnNumber: ${player.name} ───┐');

    // État de la main (réelle)
    final cards = player.hand.map((c) => _cardToString(c)).join(', ');
    final score = player.calculateScore();
    buffer.writeln('│ Main réelle: [$cards] = $score pts');

    // Pour les bots : ce qu'il SAIT de sa propre main
    if (!player.isHuman) {
      final knownOwn = <String>[];
      for (int i = 0; i < player.hand.length; i++) {
        if (i < player.mentalMap.length && player.mentalMap[i] != null) {
          knownOwn.add(_cardToString(player.mentalMap[i]!));
        } else {
          knownOwn.add('?');
        }
      }
      final knownCount = player.mentalMap.where((c) => c != null).length;
      buffer.writeln('│ Ce que ${player.name} SAIT: [${knownOwn.join(', ')}] ($knownCount/${player.hand.length} connues)');
      
      // Score estimé par le bot
      final estimatedScore = player.getEstimatedScore();
      buffer.writeln('│ Score estimé par ${player.name}: ~$estimatedScore pts');
      
      // Comptage de cartes (pour bots Or/Platine/Hardcore uniquement)
      final skillLevel = player.botSkillLevel;
      final isSmartBot = skillLevel == BotSkillLevel.gold || 
                         skillLevel == BotSkillLevel.platinum ||
                         (player.aiParameters != null && player.aiParameters!['hardcoreMode'] == 1.0);
      if (isSmartBot && allPlayers != null) {
        final tracker = BotDutchStrategy.discardTracker;
        final ratio = tracker.lowToHighRatio;
        buffer.writeln('│ 📊 Comptage cartes:');
        buffer.writeln('│   Ratio bonnes/mauvaises: ${ratio.toStringAsFixed(2)}');
        buffer.writeln('│   Cartes 0-5pts restantes: ${tracker.remainingCount(0) + tracker.remainingCount(1) + tracker.remainingCount(2) + tracker.remainingCount(3) + tracker.remainingCount(4) + tracker.remainingCount(5)}');
        buffer.writeln('│   Cartes 10+pts restantes: ${tracker.remainingCount(10) + tracker.remainingCount(11) + tracker.remainingCount(12) + tracker.remainingCount(13)}');
        
        // Estimations adversaires
        for (final opponent in allPlayers) {
          if (opponent.id != player.id && opponent.hand.isNotEmpty) {
            final estimate = tracker.estimateOpponentHand(opponent.id, opponent.hand.length);
            final lastWasExchange = tracker.lastActionWasExchange(opponent.id);
            final actionInfo = lastWasExchange ? '🔄gardé pioche' : '❌défaussé pioche';
            buffer.writeln('│   → ${opponent.name}: ~${estimate.estimatedScore.toStringAsFixed(0)}pts ($actionInfo, conf:${(estimate.confidence * 100).toInt()}%)');
          }
        }
      }
      
      // Mémoire des adversaires (spyMemory)
      if (player.spyMemory.isNotEmpty && allPlayers != null) {
        buffer.writeln('│ Cartes espionnées:');
        for (final entry in player.spyMemory.entries) {
          final opponentId = entry.key;
          final opponent = allPlayers.where((p) => p.id == opponentId).firstOrNull;
          if (opponent != null && entry.value.isNotEmpty) {
            final spiedCards = entry.value.entries
                .map((e) => '  pos${e.key}:${_cardToString(e.value)}')
                .join(', ');
            buffer.writeln('│   → ${opponent.name}: [$spiedCards]');
          }
        }
      }
    }
    buffer.writeln('└────────────────────────────┘');

    _logBuffer.write(buffer.toString());
    await _appendToFile(buffer.toString());
  }

  /// Log une pioche depuis le deck
  Future<void> logDraw({
    required Player player,
    required PlayingCard card,
    required bool fromDiscard,
  }) async {
    if (!_isEnabled) return;

    final source = fromDiscard ? 'DÉFAUSSE' : 'PIOCHE';
    final text = '  → ${player.name} pioche ${_cardToString(card)} ($source)\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log une défausse
  Future<void> logDiscard({
    required Player player,
    required PlayingCard card,
  }) async {
    if (!_isEnabled) return;

    final text = '  → ${player.name} défausse ${_cardToString(card)}\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log un échange de carte
  Future<void> logExchange({
    required Player player,
    required PlayingCard oldCard,
    required PlayingCard newCard,
    required int handIndex,
  }) async {
    if (!_isEnabled) return;

    final text = '  → ${player.name} ÉCHANGE position $handIndex: '
        '${_cardToString(oldCard)} → ${_cardToString(newCard)} '
        '(gain: ${oldCard.points - newCard.points} pts)\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log un match de cartes
  Future<void> logMatch({
    required Player player,
    required List<PlayingCard> matchedCards,
    required List<int> handIndices,
    required PlayingCard discardCard,
  }) async {
    if (!_isEnabled) return;

    final cardsStr = matchedCards.map((c) => _cardToString(c)).join(', ');
    final indicesStr = handIndices.join(', ');
    final totalPoints = matchedCards.fold<int>(0, (sum, c) => sum + c.points);

    final text = '  → ${player.name} MATCH [$cardsStr] (positions: $indicesStr) '
        'avec ${_cardToString(discardCard)} - économise $totalPoints pts\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log l'utilisation d'un pouvoir
  Future<void> logPowerUse({
    required Player player,
    required int powerValue,
    required String powerName,
    required String description,
  }) async {
    if (!_isEnabled) return;

    final text = '  ⚡ ${player.name} utilise POUVOIR $powerValue ($powerName): $description\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log un pouvoir sauté
  Future<void> logPowerSkip({
    required Player player,
    required int powerValue,
    required String reason,
  }) async {
    if (!_isEnabled) return;

    final text = '  ⚡ ${player.name} SAUTE pouvoir $powerValue - Raison: $reason\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log un échange Valet entre deux joueurs
  Future<void> logValetExchange({
    required Player bot,
    required Player player1,
    required Player player2,
    required int index1,
    required int index2,
    required PlayingCard card1,
    required PlayingCard card2,
  }) async {
    if (!_isEnabled) return;

    final text = '  ⚡ ${bot.name} VALET: échange entre ${player1.name}[$index1] (${_cardToString(card1)}) '
        'et ${player2.name}[$index2] (${_cardToString(card2)})\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log un appel Dutch
  Future<void> logDutch({
    required Player player,
    required int estimatedScore,
    required String reason,
  }) async {
    if (!_isEnabled) return;

    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('  ╔═══════════════════════════════════════════╗');
    buffer.writeln('  ║  🎯 DUTCH appelé par ${player.name.padRight(20)} ║');
    buffer.writeln('  ║  Score estimé: $estimatedScore pts                      ║');
    buffer.writeln('  ║  Raison: ${reason.padRight(32)} ║');
    buffer.writeln('  ╚═══════════════════════════════════════════╝');
    buffer.writeln('');

    _logBuffer.write(buffer.toString());
    await _appendToFile(buffer.toString());
  }

  /// Log les scores de fin de manche
  Future<void> logRoundEnd({
    required List<Player> players,
    required Player dutchCaller,
    required bool dutchSuccess,
  }) async {
    if (!_isEnabled) return;

    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('═══ FIN DE MANCHE $_roundNumber ═══');
    buffer.writeln('Dutch par: ${dutchCaller.name} - ${dutchSuccess ? "RÉUSSI ✓" : "RATÉ ✗"}');
    buffer.writeln('');
    buffer.writeln('Scores:');
    for (final p in players) {
      final cards = p.hand.map((c) => _cardToString(c)).join(', ');
      buffer.writeln('  ${p.name}: [$cards] = ${p.calculateScore()} pts');
    }
    buffer.writeln('');

    _logBuffer.write(buffer.toString());
    await _appendToFile(buffer.toString());
  }

  /// Log la fin de la partie
  Future<void> logGameEnd({
    required List<Player> players,
    required Map<String, int> totalScores,
    required Player winner,
  }) async {
    if (!_isEnabled) return;

    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('╔═══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║                      FIN DE PARTIE                            ║');
    buffer.writeln('╚═══════════════════════════════════════════════════════════════╝');
    buffer.writeln('');
    buffer.writeln('CLASSEMENT FINAL:');

    // Trier par score
    final sorted = totalScores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    int rank = 1;
    for (final entry in sorted) {
      final medal = rank == 1 ? '🥇' : (rank == 2 ? '🥈' : (rank == 3 ? '🥉' : '  '));
      buffer.writeln('  $medal $rank. ${entry.key}: ${entry.value} pts');
      rank++;
    }

    buffer.writeln('');
    buffer.writeln('🏆 GAGNANT: ${winner.name}');
    buffer.writeln('');
    buffer.writeln('═══════════════════════════════════════════════════════════════');

    _logBuffer.write(buffer.toString());
    await _appendToFile(buffer.toString());
  }

  /// Log une action personnalisée
  Future<void> logCustomAction({
    required Player player,
    required String action,
    String? details,
  }) async {
    if (!_isEnabled) return;

    final detailsStr = details != null ? ' - $details' : '';
    final text = '  → ${player.name}: $action$detailsStr\n';
    _logBuffer.write(text);
    await _appendToFile(text);
  }

  /// Log de debug pour les décisions bot
  Future<void> logBotDecision({
    required Player bot,
    required String decision,
    required Map<String, dynamic> context,
  }) async {
    if (!_isEnabled) return;

    final buffer = StringBuffer();
    buffer.writeln('  [BOT DEBUG] ${bot.name} - $decision');
    for (final entry in context.entries) {
      buffer.writeln('    ${entry.key}: ${entry.value}');
    }

    _logBuffer.write(buffer.toString());
    await _appendToFile(buffer.toString());
  }

  /// Ajoute du texte au fichier de log (plateformes natives uniquement)
  Future<void> _appendToFile(String text) async {
    if (kIsWeb || _currentGameId == null) return;
    await platform.appendToLogFile(_currentGameId!, text);
  }

  /// Convertit une carte en string lisible
  String _cardToString(PlayingCard card) {
    return '${card.value}${card.suit}(${card.points})';
  }

  /// Retourne le contenu complet du log
  String getLogContent() {
    return _logBuffer.toString();
  }

  /// Télécharge le log (fonctionne sur web et natif)
  Future<void> downloadLog() async {
    if (_logBuffer.isEmpty) return;

    final filename = _currentGameId != null
        ? '$_currentGameId.log'
        : 'dutch_game_${DateTime.now().millisecondsSinceEpoch}.log';

    await platform.downloadLog(filename, _logBuffer.toString());
  }

  /// Retourne true si un log est disponible
  bool get hasLog => _logBuffer.isNotEmpty;

  /// Retourne l'ID de la partie en cours
  String? get currentGameId => _currentGameId;

  /// Réinitialise le log
  void reset() {
    _logBuffer.clear();
    _currentGameId = null;
    _turnNumber = 0;
    _roundNumber = 1;
  }
}
