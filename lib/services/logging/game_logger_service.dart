import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../models/game_state.dart';
import '../game/bot/bot_config.dart';
import '../game/bot/bot_dutch_strategy.dart';
import '../game/bot/bot_personality.dart';

// Fallback headless pour `dart run` (sans Flutter UI / dart:ui),
// puis spécialisations web et Flutter.
import 'game_logger_headless.dart'
    if (dart.library.html) 'game_logger_web.dart'
    if (dart.library.ui) 'game_logger_native.dart' as platform;

const bool _isWeb = bool.fromEnvironment('dart.library.js_util');

/// Service de logging pour enregistrer toutes les actions de jeu
/// Fonctionne sur toutes les plateformes (web, mobile, desktop)
class GameLoggerService {
  static GameLoggerService? _instance;
  static GameLoggerService get instance => _instance ??= GameLoggerService._();

  GameLoggerService._();

  final StringBuffer _logBuffer = StringBuffer();
  final StringBuffer _tournamentArchive = StringBuffer();
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

    // Archiver le log de la manche précédente (pour "tout le tournoi")
    if (_logBuffer.isNotEmpty) {
      _tournamentArchive.write(_logBuffer.toString());
    }
    _logBuffer.clear();

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    _currentGameId = 'game_$timestamp';
    _turnNumber = 0;
    _roundNumber = 1;

    _logBuffer.writeln(
        '═══════════════════════════════════════════════════════════════');
    _logBuffer.writeln('  DUTCH GAME LOG - ${DateTime.now()}');
    _logBuffer.writeln(
        '═══════════════════════════════════════════════════════════════');
    _logBuffer.writeln('');
    _logBuffer.writeln('CONFIGURATION:');
    _logBuffer.writeln('  Target Score: $targetScore');
    _logBuffer.writeln('  Players: ${players.length}');
    _logBuffer.writeln('');
    _logBuffer.writeln('JOUEURS:');
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      final type =
          p.isHuman ? 'HUMAIN' : 'BOT (${p.botBehavior?.name ?? "unknown"})';
      _logBuffer.writeln('  [${i + 1}] ${p.name} - $type');
      if (!p.isHuman) {
        final skill = p.botSkillLevel?.name ?? '?';
        final hasAI = p.aiParameters != null && p.aiParameters!.isNotEmpty;
        final src = hasAI ? 'SERVEUR' : 'LOCAL';
        if (hasAI) {
          final ai = p.aiParameters!;
          final mmr = ai['serverMMR']?.toInt() ?? '?';
          final vsHuman = ai['serverWinRateVsHuman'] != null
              ? '${(ai['serverWinRateVsHuman']! * 100).toStringAsFixed(0)}%'
              : '?';
          _logBuffer.writeln(
              '        Skill: $skill | Params: $src | MMR: $mmr | Vs humain: $vsHuman');
          final mem = ai['memoryAccuracy']?.toStringAsFixed(2) ?? '?';
          final dutch = ai['dutchThreshold']?.toStringAsFixed(1) ?? '?';
          final agg = ai['aggressiveness']?.toStringAsFixed(2) ?? '?';
          _logBuffer.writeln(
              '        memoryAccuracy=$mem dutchThreshold=$dutch aggressiveness=$agg');
        } else {
          _logBuffer.writeln('        Skill: $skill | Params: $src');
        }
      }
    }
    _logBuffer.writeln('');
    _logBuffer.writeln(
        '═══════════════════════════════════════════════════════════════');
    _logBuffer.writeln('');

    // Sur les plateformes natives, aussi sauvegarder dans un fichier
    if (!_isWeb) {
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
    buffer.writeln(
        '┌─────────────────────────────────────────────────────────────┐');
    buffer.writeln(
        '│                    MANCHE $roundNumber                              │');
    buffer.writeln(
        '└─────────────────────────────────────────────────────────────┘');
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
    GameState? gameState,
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
      buffer.writeln(
          '│ Ce que ${player.name} SAIT: [${knownOwn.join(', ')}] ($knownCount/${player.hand.length} connues)');

      // Score connu et confiance du bot
      final knownScore = player.getKnownScore();
      final confidence = player.getMemoryConfidence();
      final unknownCount = player.unknownCardCount;
      if (unknownCount == 0) {
        buffer.writeln('│ Score CERTAIN: $knownScore pts (confiance: 100%)');
      } else {
        buffer.writeln(
            '│ Score connu: $knownScore pts + $unknownCount carte(s) inconnue(s) (confiance: ${(confidence * 100).toInt()}%)');
      }

      // Comptage de cartes (pour bots Or/Platine/Hardcore uniquement)
      final skillLevel = player.botSkillLevel;
      final isSmartBot = skillLevel == BotSkillLevel.gold ||
          skillLevel == BotSkillLevel.platinum ||
          (player.aiParameters != null &&
              player.aiParameters!['hardcoreMode'] == 1.0);
      if (isSmartBot && allPlayers != null) {
        final tracker = BotDutchStrategy.discardTracker;
        final ratio = tracker.lowToHighRatio;
        buffer.writeln('│ 📊 Comptage cartes:');
        buffer
            .writeln('│   Ratio bonnes/mauvaises: ${ratio.toStringAsFixed(2)}');
        buffer.writeln(
            '│   Cartes 0-5pts restantes: ${tracker.remainingCount(0) + tracker.remainingCount(1) + tracker.remainingCount(2) + tracker.remainingCount(3) + tracker.remainingCount(4) + tracker.remainingCount(5)}');
        buffer.writeln(
            '│   Cartes 10+pts restantes: ${tracker.remainingCount(10) + tracker.remainingCount(11) + tracker.remainingCount(12) + tracker.remainingCount(13)}');

        // Estimations adversaires
        for (final opponent in allPlayers) {
          if (opponent.id == player.id) continue;
          if (opponent.hand.isEmpty) {
            buffer.writeln(
                '│   → ${opponent.name}: ~0pts (main vide, conf:100%)');
            continue;
          }

          final difficulty = BotConfig.getDifficulty(player, null);
          final estimate = gameState != null
              ? BotDutchStrategy.estimateOpponentForObserver(
                  gameState,
                  player,
                  opponent,
                  difficulty,
                )
              : null;
          final estimatedScore = estimate?.estimatedScore ??
              tracker
                  .estimateOpponentHand(opponent.id, opponent.hand.length)
                  .estimatedScore
                  .round();
          final estimateConfidence = estimate?.confidence ??
              tracker
                  .estimateOpponentHand(opponent.id, opponent.hand.length)
                  .confidence;
          final lastWasExchange = tracker.lastActionWasExchange(opponent.id);
          final actionInfo =
              lastWasExchange ? '🔄gardé pioche' : '❌défaussé pioche';
          buffer.writeln(
              '│   → ${opponent.name}: ~${estimatedScore}pts ($actionInfo, conf:${(estimateConfidence * 100).toInt()}%)');
        }
      }

      if (isSmartBot && gameState != null) {
        final difficulty = BotConfig.getDifficulty(player, null);
        final phase = BotConfig.getBotPhase(player, gameState);
        final personality = BotPersonality.fromBot(player);
        final trace = BotDutchStrategy.buildObservationTrace(
          gameState,
          player,
          difficulty,
          phase,
          personality: personality,
        );

        buffer.writeln('│ 🧠 Conclusion observation:');
        buffer.writeln(
            '│   Verdict: ${trace.conclusion} (${trace.shouldCallDutch ? "call" : "wait"})');
        buffer.writeln(
            '│   Lecture table: minCartes=${trace.minOpponentCards}, pression=${trace.tablePressure.toStringAsFixed(2)}, marge=${trace.margin}');
        buffer.writeln(
            '│   Fiabilité lecture: avg=${(trace.avgEstimateConfidence * 100).toInt()}% min=${(trace.minEstimateConfidence * 100).toInt()}%');
        buffer.writeln(
            '│   Auto-éval: scorePerçu=${trace.perceivedScore} (known=${trace.knownScore}, unknown=${trace.unknownCount}, E[unk]=${trace.expectedUnknown.toStringAsFixed(1)})');
        buffer.writeln(
            '│   Seuil hybride: ${trace.hybridThreshold} (${trace.canBreakHybridThreshold ? "cassable" : "strict"})');
        buffer.writeln(
            '│   Contexte: duel=${trace.duelActive ? "oui" : "non"}, momentum=${trace.opponentMomentumHot ? "chaud" : "calme"}, explosive=${trace.tableExplosive ? "oui" : "non"}');
        if (trace.duelKnownOpponentScore != null) {
          buffer.writeln(
              '│   Duel connu: score adverse=${trace.duelKnownOpponentScore}');
        }
        if (trace.opportunities.isNotEmpty) {
          buffer.writeln('│   Feux verts: ${trace.opportunities.join(' | ')}');
        }
        if (trace.blockers.isNotEmpty) {
          buffer.writeln('│   Veto: ${trace.blockers.join(' | ')}');
        }
      }

      // Mémoire des adversaires (spyMemory)
      if (player.spyMemory.isNotEmpty && allPlayers != null) {
        buffer.writeln('│ Cartes espionnées:');
        for (final entry in player.spyMemory.entries) {
          final opponentId = entry.key;
          final opponent =
              allPlayers.where((p) => p.id == opponentId).firstOrNull;
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

    final text =
        '  → ${player.name} MATCH [$cardsStr] (positions: $indicesStr) '
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

    final text =
        '  ⚡ ${player.name} utilise POUVOIR $powerValue ($powerName): $description\n';
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

    final text =
        '  ⚡ ${player.name} SAUTE pouvoir $powerValue - Raison: $reason\n';
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

    final text =
        '  ⚡ ${bot.name} VALET: échange entre ${player1.name}[$index1] (${_cardToString(card1)}) '
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
    buffer.writeln(
        '  ║  Score estimé: $estimatedScore pts                      ║');
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
    buffer.writeln(
        'Dutch par: ${dutchCaller.name} - ${dutchSuccess ? "RÉUSSI ✓" : "RATÉ ✗"}');
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
    buffer.writeln(
        '╔═══════════════════════════════════════════════════════════════╗');
    buffer.writeln(
        '║                      FIN DE PARTIE                            ║');
    buffer.writeln(
        '╚═══════════════════════════════════════════════════════════════╝');
    buffer.writeln('');
    buffer.writeln('CLASSEMENT FINAL:');

    // Trier par score
    final sorted = totalScores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    int rank = 1;
    for (final entry in sorted) {
      final medal =
          rank == 1 ? '🥇' : (rank == 2 ? '🥈' : (rank == 3 ? '🥉' : '  '));
      buffer.writeln('  $medal $rank. ${entry.key}: ${entry.value} pts');
      rank++;
    }

    buffer.writeln('');
    buffer.writeln('🏆 GAGNANT: ${winner.name}');
    buffer.writeln('');
    buffer.writeln(
        '═══════════════════════════════════════════════════════════════');

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
    if (_isWeb || _currentGameId == null) return;
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

  /// Retourne le log complet du tournoi (toutes les manches archivées + manche courante)
  String getFullLog() {
    return _tournamentArchive.toString() + _logBuffer.toString();
  }

  /// Retourne le log de la manche courante uniquement
  String getLogForCurrentRound() {
    return _logBuffer.toString();
  }

  /// Télécharge le log (fonctionne sur web et natif)
  Future<bool> downloadLog() async {
    if (_logBuffer.isEmpty) return false;

    final filename = _currentGameId != null
        ? '$_currentGameId.log'
        : 'dutch_game_${DateTime.now().millisecondsSinceEpoch}.log';

    return platform.downloadLog(filename, _logBuffer.toString());
  }

  /// Télécharge un contenu de log arbitraire
  Future<bool> downloadLogContent(String content) async {
    if (content.isEmpty) return false;
    final filename = _currentGameId != null
        ? '$_currentGameId.log'
        : 'dutch_game_${DateTime.now().millisecondsSinceEpoch}.log';
    return platform.downloadLog(filename, content);
  }

  /// Retourne true si un log est disponible
  bool get hasLog => _logBuffer.isNotEmpty || _tournamentArchive.isNotEmpty;

  /// Retourne true si des manches précédentes sont archivées (tournoi multi-manches)
  bool get hasTournamentArchive => _tournamentArchive.isNotEmpty;

  /// Retourne l'ID de la partie en cours
  String? get currentGameId => _currentGameId;

  /// Réinitialise le log (appelé en début de nouveau tournoi/partie)
  void reset() {
    _logBuffer.clear();
    _tournamentArchive.clear();
    _currentGameId = null;
    _turnNumber = 0;
    _roundNumber = 1;
  }
}
