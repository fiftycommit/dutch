import '../../../models/game_state.dart';
import '../../../models/player.dart';
import 'bot_config.dart';
import 'bot_difficulty.dart';
import 'bot_personality.dart';
import 'bot_memory_manager.dart';
import 'discard_tracker.dart';

/// Stratégie de décision pour appeler Dutch
/// Logique multi‑paramètres (sans seuils de score fixes)
class BotDutchStrategy {
  /// Tracker de défausses partagé (comptage de cartes)
  static final DiscardTracker discardTracker = DiscardTracker();

  /// Snapshot détaillé de lecture de table / conclusion Dutch.
  /// Utilisé uniquement pour le logging et le debug.
  static BotDutchObservationTrace buildObservationTrace(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    final tier = _tierFromDifficulty(difficulty);
    final profile = _profileForDifficulty(difficulty);
    final unknownCount = BotMemoryManager.getUnknownIndices(bot).length;
    final knownScore = bot.getKnownScore();
    final expectedUnknown = BotMemoryManager.getExpectedDeckCardValue(gs);
    final perceivedScore = unknownCount == 0
        ? knownScore
        : knownScore + (expectedUnknown * unknownCount).round();
    final canDutchState = _canDutchStateBased(gs, bot, difficulty);
    final hasOpponentWithGuaranteedZero =
        gs.players.any((p) => p.id != bot.id && p.hand.isEmpty);
    final context = _buildDecisionContext(gs, bot, profile);
    final conclusions =
        _buildExpertDutchConclusions(gs, bot, profile, context, phase);
    final adjustedOpponentEstimate =
        (context.bestOpponentEstimate - profile.opponentEstimatePenalty)
            .clamp(0, 999);
    final margin = adjustedOpponentEstimate - perceivedScore;
    final hybridThreshold = _resolveHybridDutchThreshold(
      profile: profile,
      personality: personality,
      phase: phase,
      context: context,
      conclusions: conclusions,
    );
    final canBreakHybridThreshold =
        margin >= 2 || (conclusions?.safeWindow == true && margin >= 1);

    final blockers = <String>[];
    final opportunities = <String>[];

    if (phase == BotGamePhase.exploration) {
      blockers.add('phase exploration');
    }
    if (!canDutchState) {
      blockers.add('mémoire incomplète/incertaine');
    }
    if (hasOpponentWithGuaranteedZero && perceivedScore > 0) {
      blockers.add('adversaire à 0 garanti');
    }
    if (perceivedScore > adjustedOpponentEstimate) {
      blockers.add('derrière estimation adverse');
    } else {
      opportunities.add('lead estimé >= 0');
    }
    if (perceivedScore > hybridThreshold && !canBreakHybridThreshold) {
      blockers
          .add('au-dessus seuil hybride ($perceivedScore > $hybridThreshold)');
    } else if (perceivedScore <= hybridThreshold) {
      opportunities.add('dans fenêtre seuil hybride');
    }

    if (conclusions != null) {
      if (conclusions.tableExplosive) {
        blockers.add('table explosive');
      } else if (conclusions.safeWindow) {
        opportunities.add('fenêtre safe');
      }
      if (conclusions.opponentMomentumHot) {
        blockers.add('momentum adverse fort');
      }
      if (conclusions.opponentCanFinishSoon) {
        blockers.add('adversaire peut finir vite');
      }
      if (conclusions.forceImmediateClose) {
        opportunities.add('clôture immédiate recommandée');
      }
      if (conclusions.duelActive) {
        opportunities.add('duel actif');
        if (conclusions.duelKnownOpponentScore != null) {
          opportunities
              .add('score adverse connu=${conclusions.duelKnownOpponentScore}');
        }
      }
    }

    final shouldCall = shouldCallDutch(
      gs,
      bot,
      difficulty,
      phase,
      personality: personality,
    );

    final conclusion =
        shouldCall ? 'FENETRE DUTCH OUVERTE' : 'FENETRE DUTCH FERMEE';

    return BotDutchObservationTrace(
      botName: bot.name,
      tierLabel: _tierLabel(tier),
      phaseLabel: phase.name,
      unknownCount: unknownCount,
      knownScore: knownScore,
      perceivedScore: perceivedScore,
      expectedUnknown: expectedUnknown,
      canDutchState: canDutchState,
      shouldCallDutch: shouldCall,
      conclusion: conclusion,
      opponentCount: context.opponentCount,
      bestOpponentEstimate: context.bestOpponentEstimate,
      avgOpponentEstimate: context.avgOpponentEstimate,
      minOpponentCards: context.minOpponentCards,
      avgOpponentCards: context.avgOpponentCards,
      tablePressure: context.tablePressure,
      adjustedOpponentEstimate: adjustedOpponentEstimate,
      margin: margin,
      hybridThreshold: hybridThreshold,
      canBreakHybridThreshold: canBreakHybridThreshold,
      duelKnownOpponentScore: conclusions?.duelKnownOpponentScore,
      duelActive: conclusions?.duelActive ?? false,
      opponentMomentumHot: conclusions?.opponentMomentumHot ?? false,
      opponentCanFinishSoon: conclusions?.opponentCanFinishSoon ?? false,
      tableExplosive: conclusions?.tableExplosive ?? false,
      safeWindow: conclusions?.safeWindow ?? false,
      forceImmediateClose: conclusions?.forceImmediateClose ?? false,
      blockers: blockers,
      opportunities: opportunities,
    );
  }

  static String _tierLabel(_DutchTier tier) {
    switch (tier) {
      case _DutchTier.bronze:
        return 'bronze';
      case _DutchTier.silver:
        return 'argent';
      case _DutchTier.gold:
        return 'or';
      case _DutchTier.platinum:
        return 'platine';
    }
  }

  /// Décide si le bot doit appeler Dutch
  static bool shouldCallDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    final tier = _tierFromDifficulty(difficulty);

    // Règle premium (Or/Platine): main vide OU score 0 certain => Dutch immédiat.
    if (tier == _DutchTier.gold || tier == _DutchTier.platinum) {
      final knownUnknownCount = BotMemoryManager.getUnknownIndices(bot).length;
      final hasGuaranteedZeroScore =
          knownUnknownCount == 0 ? bot.getKnownScore() == 0 : false;
      if (bot.hand.isEmpty || hasGuaranteedZeroScore) return true;
    }

    if (phase == BotGamePhase.exploration) return false;

    switch (tier) {
      case _DutchTier.bronze:
        return _shouldBronzeDutchNaive(gs, bot, phase);
      case _DutchTier.silver:
        if (!_canDutchStateBased(gs, bot, difficulty)) return false;
        return _shouldSilverDutch(gs, bot, difficulty, phase, personality);
      case _DutchTier.gold:
        if (!_canDutchStateBased(gs, bot, difficulty)) return false;
        return _shouldGoldDutch(gs, bot, difficulty, phase, personality);
      case _DutchTier.platinum:
        if (!_canDutchStateBased(gs, bot, difficulty)) return false;
        return _shouldPlatinumDutch(gs, bot, difficulty, personality);
    }
  }

  static bool _shouldBronzeDutchNaive(
    GameState gs,
    Player bot,
    BotGamePhase phase,
  ) {
    // Bronze distrait: il regarde d'abord son propre score perçu,
    // sans analyse des adversaires.
    final enoughTurns = gs.turnCount >= 2 || phase == BotGamePhase.endgame;
    if (!enoughTurns) return false;

    final unknownCount = BotMemoryManager.getUnknownIndices(bot).length;
    final knownScore = bot.getKnownScore();
    final expectedUnknown = BotMemoryManager.getExpectedDeckCardValue(gs);
    final perceivedScore =
        knownScore + (expectedUnknown * unknownCount).round();

    // S'il a encore trop d'inconnues, Bronze hésite hors endgame.
    if (phase != BotGamePhase.endgame && unknownCount >= 3) {
      return false;
    }

    // Seuils simples orientés "si ça a l'air bon pour moi, je Dutch".
    final threshold = phase == BotGamePhase.endgame ? 9 : 6;
    return perceivedScore <= threshold;
  }

  /// Vérifie si le bot PEUT Dutch (conditions nécessaires)
  static bool _canDutchStateBased(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
  ) {
    // RÈGLE FONDAMENTALE : le bot doit connaître TOUTES ses cartes
    final unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    if (unknownIndices.isNotEmpty) {
      final tier = _tierFromDifficulty(difficulty);
      if (tier != _DutchTier.platinum || unknownIndices.length != 1) {
        return false;
      }

      final knownCount = bot.mentalMap.where((c) => c != null).length;
      if (knownCount < bot.hand.length - 1) {
        return false;
      }

      final knownScore = bot.getKnownScore();
      final expectedUnknown = BotMemoryManager.getExpectedDeckCardValue(gs);
      return knownScore <= 1 && expectedUnknown <= 2.5;
    }

    // Vérifier que la mentalMap est cohérente
    final knownCount = bot.mentalMap.where((c) => c != null).length;
    final handSize = bot.hand.length;
    if (knownCount < handSize) {
      return false; // Pas assez de certitude
    }

    return true;
  }

  /// Silver Dutch : prudent, stat-based avec biais négatif
  static bool _shouldSilverDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase,
    BotPersonality? personality,
  ) {
    return _shouldDutchStateBased(gs, bot, difficulty, phase, personality);
  }

  /// Gold Dutch : opportuniste contextuel, analyse de table
  static bool _shouldGoldDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase,
    BotPersonality? personality,
  ) {
    return _shouldDutchStateBased(gs, bot, difficulty, phase, personality);
  }

  /// Platinum Dutch : ultra-opportuniste, pas de phase exploration
  static bool _shouldPlatinumDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotPersonality? personality,
  ) {
    // Platine n'est jamais bridé par la phase — il analyse contextuellement
    return _shouldDutchStateBased(
        gs, bot, difficulty, BotGamePhase.endgame, personality);
  }

  /// Décide si le bot DEVRAIT Dutch (conditions suffisantes)
  ///
  /// RÈGLE DU JEU : Si tu Dutch et que tu n'as PAS le plus petit score,
  /// tu es DERNIER. C'est un risque énorme → le bot doit être CONFIANT
  /// qu'il a le plus petit score avant de Dutch.
  static bool _shouldDutchStateBased(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase,
    BotPersonality? personality,
  ) {
    final unknownCount = BotMemoryManager.getUnknownIndices(bot).length;
    final myKnownScore = bot.getKnownScore();
    final expectedUnknownValue = BotMemoryManager.getExpectedDeckCardValue(gs);
    final myScore = unknownCount == 0
        ? myKnownScore
        : myKnownScore + (expectedUnknownValue * unknownCount).round();
    final profile = _profileForDifficulty(difficulty);

    // Garde-fou critique:
    // si un adversaire a déjà une main vide, son score est 0 garanti.
    // Dutch avec un score > 0 est donc perdant d'office.
    final hasOpponentWithGuaranteedZero =
        gs.players.any((p) => p.id != bot.id && p.hand.isEmpty);
    if (hasOpponentWithGuaranteedZero && myScore > 0) {
      return false;
    }

    // Score 0 certain = Dutch immédiat seulement pour Or/Platine.
    if ((profile.tier == _DutchTier.gold ||
            profile.tier == _DutchTier.platinum) &&
        unknownCount == 0 &&
        myKnownScore == 0) {
      return true;
    }

    // Si je viens de rater un match ou de prendre une pénalité, ne Dutch pas
    if (_recentMatchFail(gs, bot) || _recentPenalty(gs, bot)) {
      return false;
    }

    final context = _buildDecisionContext(gs, bot, profile);
    if (context.opponentCount == 0) return false;

    final expertConclusions = _buildExpertDutchConclusions(
      gs,
      bot,
      profile,
      context,
      phase,
    );

    // Duel contextuel: si le score adverse est connu (espionnage + taille main),
    // on applique directement la règle de tie-break Dutch.
    if (expertConclusions?.duelKnownOpponentScore != null &&
        unknownCount == 0) {
      final duelOpponentScore = expertConclusions!.duelKnownOpponentScore!;
      if (myScore <= duelOpponentScore) {
        return true; // égalité ou avantage => caller gagne
      }
      return false; // derrière avec certitude
    }

    // Platine: verrouille vite les très bas scores en endgame
    if (profile.tier == _DutchTier.platinum &&
        phase == BotGamePhase.endgame &&
        myScore <= 2) {
      return true;
    }
    // Score très bas + table "large": seuls les niveaux experts convertissent
    // agressivement cette fenêtre, les tiers bas restent plus prudents.
    if (unknownCount == 0 && myKnownScore <= 2) {
      final allOpponentsHaveMany = gs.players
          .where((p) => p.id != bot.id)
          .every((p) => p.hand.length >= 3);
      if (allOpponentsHaveMany) {
        if (profile.tier == _DutchTier.platinum) return true;
      }
    }

    if (profile.tier == _DutchTier.platinum && unknownCount == 0) {
      if (myKnownScore <= 3) {
        // À score 3, même Platine n'accélère pas sur table explosive.
        if (expertConclusions?.tableExplosive == true && myKnownScore > 2) {
          // continuer vers la décision contextuelle plus bas
        } else {
          return true;
        }
      }
      if (expertConclusions?.forceImmediateClose == true && myKnownScore <= 2) {
        return true;
      }
      if (phase == BotGamePhase.endgame &&
          myKnownScore <= 4 &&
          context.minOpponentCards <= 3) {
        return true;
      }
    }

    if (profile.tier == _DutchTier.platinum &&
        myKnownScore <= 2 &&
        unknownCount == 0 &&
        context.tablePressure >= 0.6) {
      return true;
    }

    final adjustedOpponentEstimate =
        (context.bestOpponentEstimate - profile.opponentEstimatePenalty)
            .clamp(0, 999);

    // RÈGLE FONDAMENTALE : ne Dutch que si on pense avoir le plus petit score
    // Si même score, celui qui Dutch gagne → on autorise l'égalité
    if (myScore > adjustedOpponentEstimate) {
      return false;
    }

    final margin = adjustedOpponentEstimate - myScore;
    final cardGap = context.avgOpponentCards - bot.hand.length;
    final leadGap = context.avgOpponentEstimate - myScore;
    final urgency = ((4 - context.minOpponentCards).clamp(0, 3)) / 3.0;

    // Mode hybride: seuil de base + contexte qui peut durcir/assouplir.
    final hybridThreshold = _resolveHybridDutchThreshold(
      profile: profile,
      personality: personality,
      phase: phase,
      context: context,
      conclusions: expertConclusions,
    );

    final canBreakHybridThreshold =
        margin >= 2 || (expertConclusions?.safeWindow == true && margin >= 1);
    if (myScore > hybridThreshold && !canBreakHybridThreshold) {
      return false;
    }

    if (expertConclusions != null) {
      if (expertConclusions.duelActive &&
          expertConclusions.duelKnownOpponentScore == null &&
          expertConclusions.opponentCanFinishSoon &&
          myScore > context.minOpponentCards) {
        return false;
      }

      // Table explosive sans edge estimé: éviter le Dutch "panic".
      if (expertConclusions.tableExplosive && margin < 0 && myScore > 0) {
        return false;
      }

      // Duel chaud: si l'adversaire peut finir vite et qu'on n'a pas d'edge,
      // on temporise au lieu de forcer sur un seuil arbitraire.
      if (expertConclusions.duelActive &&
          expertConclusions.opponentCanFinishSoon &&
          expertConclusions.opponentMomentumHot &&
          margin < 0) {
        return false;
      }

      int contextualCap = hybridThreshold;
      if (expertConclusions.tableExplosive) {
        contextualCap = _minInt(contextualCap, 3);
      }
      if (expertConclusions.opponentCanFinishSoon) {
        contextualCap = _minInt(contextualCap, 2);
      }
      if (expertConclusions.opponentMomentumHot &&
          context.minOpponentCards <= 3) {
        contextualCap = _minInt(contextualCap, 2);
      }
      if (myScore > contextualCap && myScore > 2) {
        return false;
      }
    }

    // Platine ultra-opportuniste mais sans suicide:
    // il accélère quand il a un vrai edge estimé.
    if (profile.tier == _DutchTier.platinum) {
      final hasRealEdge = margin >= 1;
      final strongEdge = margin >= 2;
      final emergencyLowScore = myScore <= 2 && margin >= 0;
      final pressureCloseLead = phase == BotGamePhase.endgame &&
          myScore <= 4 &&
          margin >= -1 &&
          context.minOpponentCards <= 2;
      final fastTable = phase == BotGamePhase.endgame ||
          context.minOpponentCards <= 3 ||
          context.tablePressure >= 0.8;
      final stableTable = context.avgOpponentCards >= 3;
      if ((strongEdge && (fastTable || myScore <= 4)) ||
          (hasRealEdge && myScore <= 3 && stableTable) ||
          pressureCloseLead ||
          emergencyLowScore) {
        return true;
      }
    }

    // Les tiers non-platinum deviennent très conservateurs en grande table.
    if (profile.tier != _DutchTier.platinum) {
      if (gs.players.length >= 8 && myScore > 0) {
        return false;
      }
      if (phase != BotGamePhase.endgame && myScore > 1) {
        return false;
      }
    }

    // Confiance estimée dans le lead (−1 = derrière / +1 = clairement devant)
    final confidenceRaw = (margin * 0.7 + leadGap * 0.3) / 10.0;
    final confidence = confidenceRaw.clamp(-1.0, 1.0);

    // Opportunité de Dutch
    double opportunity = margin.toDouble();
    opportunity += cardGap * profile.cardGapWeight;
    opportunity += leadGap * profile.leadWeight;
    opportunity += urgency * profile.urgencyWeight;
    opportunity += context.tablePressure * profile.pressureWeight;
    opportunity += bot.consecutiveBadDraws * profile.badDrawOpportunityWeight;

    if (phase == BotGamePhase.endgame) {
      opportunity += profile.endgameOpportunityBonus;
    }

    final goodTiming = discardTracker.isGoodTimeForDutch(gs, bot);
    if (goodTiming) {
      opportunity += profile.timingOpportunityBonus;
    }

    // Table lente avec scores adverses élevés: fenêtre favorable
    if (context.avgOpponentEstimate >= 12 && context.minOpponentCards >= 3) {
      opportunity += 0.35;
    }

    // Risque perçu du Dutch
    double risk = profile.baseRisk;
    risk += myScore * profile.scoreRiskPerPoint;
    risk += (1 - ((confidence + 1) / 2)) * profile.uncertaintyRiskWeight;

    if (cardGap < 0) {
      risk += (-cardGap) * profile.cardDisadvantageRiskWeight;
    }
    if (phase == BotGamePhase.endgame) {
      risk -= profile.endgameRiskReduction;
    }
    if (context.minOpponentCards <= 2) {
      risk -= profile.urgencyRiskReduction;
    }
    if (goodTiming) {
      risk -= profile.timingRiskReduction;
    }

    if (personality != null) {
      final styleBias = personality.aggressiveness - personality.caution;
      opportunity += styleBias * 1.1;
      opportunity += (personality.riskTolerance - 0.5) * 1.2;
      opportunity += (personality.dutchQuality - 0.5) * 0.8;
      risk += (0.5 - personality.riskTolerance) * 0.8;

      if (personality.rankPenalty > 0.5) {
        risk += 0.6;
      }
    }

    // Les conclusions dérivées de la table influencent directement la décision.
    if (expertConclusions != null) {
      if (expertConclusions.tableExplosive && myScore > 2) {
        risk += profile.tier == _DutchTier.platinum ? 1.0 : 0.8;
      }
      if (expertConclusions.opponentMomentumHot && myScore > 1) {
        risk += 0.65;
      }
      if (expertConclusions.safeWindow) {
        opportunity += 0.45;
      }
      if (expertConclusions.opponentCanFinishSoon && myScore <= 2) {
        opportunity += 0.35;
      }
    }

    final decisionScore = opportunity - risk + profile.decisionBias;
    return decisionScore >= 0;
  }

  static _DutchDecisionContext _buildDecisionContext(
    GameState gs,
    Player bot,
    _DutchDecisionProfile profile,
  ) {
    int bestOpponentEstimate = 999;
    int minOpponentCards = 99;
    int totalOpponentCards = 0;
    double totalOpponentEstimate = 0;
    double stylePressure = 0;
    int opponentCount = 0;

    for (final opponent in gs.players) {
      if (opponent.id == bot.id) continue;
      opponentCount++;

      final cards = opponent.hand.length;
      totalOpponentCards += cards;
      if (cards < minOpponentCards) {
        minOpponentCards = cards;
      }

      final estimated = opponent.hand.isEmpty
          ? 0
          : _estimateOpponentScore(bot, opponent, profile);
      totalOpponentEstimate += estimated;
      if (estimated < bestOpponentEstimate) {
        bestOpponentEstimate = estimated;
      }

      final style = discardTracker.estimateOpponentStyle(opponent.id);
      final fewCardsPressure = ((4 - cards).clamp(0, 3)) / 3.0;
      stylePressure += (style.optimization * 0.7 + style.aggression * 0.3) *
          (0.6 + fewCardsPressure * 0.8) *
          style.confidence;
    }

    if (opponentCount == 0) {
      return const _DutchDecisionContext(
        opponentCount: 0,
        bestOpponentEstimate: 0,
        avgOpponentEstimate: 0,
        minOpponentCards: 0,
        avgOpponentCards: 0,
        tablePressure: 0,
      );
    }

    final avgOpponentEstimate = totalOpponentEstimate / opponentCount;
    final avgOpponentCards = totalOpponentCards / opponentCount;

    // Pression de table 0..~2 (plus c'est haut, plus la table est "chaude")
    double tablePressure = 0;
    if (minOpponentCards <= 1) {
      tablePressure += 1.2;
    } else if (minOpponentCards == 2) {
      tablePressure += 0.7;
    }
    tablePressure += ((8 - avgOpponentEstimate) / 12).clamp(-0.3, 0.6);
    tablePressure += ((stylePressure / opponentCount) * 0.55).clamp(0.0, 0.7);
    tablePressure = tablePressure.clamp(0.0, 2.0);

    return _DutchDecisionContext(
      opponentCount: opponentCount,
      bestOpponentEstimate:
          bestOpponentEstimate == 999 ? 0 : bestOpponentEstimate,
      avgOpponentEstimate: avgOpponentEstimate,
      minOpponentCards: minOpponentCards == 99 ? 0 : minOpponentCards,
      avgOpponentCards: avgOpponentCards,
      tablePressure: tablePressure,
    );
  }

  /// Estime le score d'un adversaire via:
  /// - info publique (défausses),
  /// - info privée (cartes espionnées),
  /// avec un poids de mémoire qui dépend du tier.
  static int _estimateOpponentScore(
    Player observer,
    Player opponent,
    _DutchDecisionProfile profile,
  ) {
    final discardEstimate = discardTracker
        .estimateOpponentHand(opponent.id, opponent.hand.length)
        .estimatedScore;
    final style = discardTracker.estimateOpponentStyle(opponent.id);
    final styledEstimate = _applyStyleToOpponentEstimate(
      discardEstimate,
      opponent.hand.length,
      style,
      profile.tier,
    );

    final spiedCards = observer.getSpiedCards(opponent.id);
    if (spiedCards == null || spiedCards.isEmpty || opponent.hand.isEmpty) {
      return styledEstimate.round();
    }

    final knownSpied = spiedCards.keys
        .where((idx) => idx >= 0 && idx < opponent.hand.length)
        .length;
    if (knownSpied == 0) {
      return styledEstimate.round();
    }

    final spyCoverage = (knownSpied / opponent.hand.length).clamp(0.0, 1.0);
    final tierSpyWeight = _spyWeightForTier(profile.tier);
    final spyWeight =
        (tierSpyWeight * (0.45 + spyCoverage * 0.55)).clamp(0.0, 0.95);
    final spiedEstimate =
        observer.getEstimatedOpponentScore(opponent.id, opponent.hand.length);

    final blended =
        (styledEstimate * (1 - spyWeight)) + (spiedEstimate * spyWeight);
    return blended.round();
  }

  static double _applyStyleToOpponentEstimate(
    double baseEstimate,
    int cards,
    OpponentStyleEstimate style,
    _DutchTier tier,
  ) {
    double adjusted = baseEstimate;
    final fewCardsPressure = ((4 - cards).clamp(0, 3)) / 3.0;

    double styleImpactWeight;
    switch (tier) {
      case _DutchTier.bronze:
        styleImpactWeight = 0.0;
        break;
      case _DutchTier.silver:
        styleImpactWeight = 0.20;
        break;
      case _DutchTier.gold:
        styleImpactWeight = 0.60;
        break;
      case _DutchTier.platinum:
        styleImpactWeight = 1.0;
        break;
    }

    if (styleImpactWeight > 0) {
      final optimizerThreat =
          style.optimization * (0.9 + fewCardsPressure * 1.6);
      final aggressionThreat = style.aggression * (0.5 + fewCardsPressure);
      final unpredictabilityThreat =
          style.unpredictability * (0.25 + fewCardsPressure * 0.45);
      final confidence = style.confidence;

      final threatDelta = (optimizerThreat * 2.6 +
              aggressionThreat * 1.2 +
              unpredictabilityThreat) *
          confidence *
          styleImpactWeight;
      adjusted -= threatDelta;

      if (cards >= 4 && style.optimization <= 0.35) {
        adjusted +=
            (0.35 - style.optimization) * 2.0 * confidence * styleImpactWeight;
      }
    }

    return adjusted.clamp(0.0, 999.0);
  }

  static double _spyWeightForTier(_DutchTier tier) {
    switch (tier) {
      case _DutchTier.bronze:
        return 0.10;
      case _DutchTier.silver:
        return 0.25;
      case _DutchTier.gold:
        return 0.65;
      case _DutchTier.platinum:
        return 0.80;
    }
  }

  static bool _recentMatchFail(GameState gs, Player player) {
    return _recentActionContains(gs, player.name, ['rate son match']);
  }

  static bool _recentPenalty(GameState gs, Player player) {
    return _recentActionContains(gs, player.name, ['pénalité', 'penalite']);
  }

  static _ExpertDutchConclusions? _buildExpertDutchConclusions(
    GameState gs,
    Player bot,
    _DutchDecisionProfile profile,
    _DutchDecisionContext context,
    BotGamePhase phase,
  ) {
    if (profile.tier != _DutchTier.gold &&
        profile.tier != _DutchTier.platinum) {
      return null;
    }

    final momentum = _analyzeOpponentMomentum(gs, bot);
    final duelActive = context.opponentCount == 1;
    final duelKnownOpponentScore =
        duelActive ? _resolveDuelKnownOpponentScore(gs, bot) : null;
    final opponentCanFinishSoon = context.minOpponentCards <= 2;
    final opponentMomentumHot = momentum.opponentJustMatched ||
        momentum.recentMatches >= 2 ||
        momentum.longestStreak >= 2;
    final tableExplosive = opponentCanFinishSoon ||
        (opponentMomentumHot && context.minOpponentCards <= 3);
    final safeWindow = !tableExplosive &&
        !opponentMomentumHot &&
        context.minOpponentCards >= 4 &&
        context.tablePressure < 0.8;
    final forceImmediateClose = opponentCanFinishSoon && opponentMomentumHot;

    return _ExpertDutchConclusions(
      duelActive: duelActive,
      duelKnownOpponentScore: duelKnownOpponentScore,
      opponentMomentumHot: opponentMomentumHot,
      opponentCanFinishSoon: opponentCanFinishSoon,
      tableExplosive: tableExplosive,
      safeWindow: safeWindow,
      forceImmediateClose: forceImmediateClose,
    );
  }

  static int? _resolveDuelKnownOpponentScore(GameState gs, Player bot) {
    final opponent = gs.players.where((p) => p.id != bot.id).firstOrNull;
    if (opponent == null) return null;
    if (opponent.hand.isEmpty) return 0;

    final spied = bot.getSpiedCards(opponent.id);
    if (spied == null || spied.isEmpty) return null;

    int knownScore = 0;
    int knownCount = 0;
    for (final entry in spied.entries) {
      final idx = entry.key;
      if (idx < 0 || idx >= opponent.hand.length) continue;
      knownScore += entry.value.points;
      knownCount++;
    }
    if (knownCount == 0) return null;
    if (knownCount == opponent.hand.length) return knownScore;
    if (opponent.hand.length == 1 && knownCount == 1) return knownScore;
    return null;
  }

  static int _resolveHybridDutchThreshold({
    required _DutchDecisionProfile profile,
    required BotGamePhase phase,
    required _DutchDecisionContext context,
    required _ExpertDutchConclusions? conclusions,
    BotPersonality? personality,
  }) {
    int threshold = profile.hybridBaseThreshold;

    if (phase == BotGamePhase.endgame) {
      threshold += 1;
    }
    if (context.opponentCount == 1) {
      threshold += 1;
    }

    if (personality != null) {
      final personalityThreshold = personality.dutchThreshold.round();
      threshold = ((threshold * 0.65) + (personalityThreshold * 0.35)).round();
    }

    if (context.tablePressure >= 1.0) {
      threshold -= 1;
    }
    if (context.minOpponentCards <= 2) {
      threshold -= 1;
    }
    if (conclusions?.opponentMomentumHot == true) {
      threshold -= 1;
    }

    switch (profile.tier) {
      case _DutchTier.bronze:
        return threshold.clamp(4, 10);
      case _DutchTier.silver:
        return threshold.clamp(3, 8);
      case _DutchTier.gold:
        return threshold.clamp(2, 8);
      case _DutchTier.platinum:
        return threshold.clamp(1, 7);
    }
  }

  static _OpponentMomentum _analyzeOpponentMomentum(
    GameState gs,
    Player bot, {
    int lookback = 18,
  }) {
    final opponentNames = gs.players
        .where((p) => p.id != bot.id)
        .map((p) => p.name.toLowerCase())
        .toList(growable: false);

    int recentMatches = 0;
    int longestStreak = 0;
    int currentStreak = 0;
    String? currentStreakOwner;
    bool opponentJustMatched = false;

    final limit =
        gs.actionHistory.length < lookback ? gs.actionHistory.length : lookback;
    for (int i = 0; i < limit; i++) {
      final entry = gs.actionHistory[i].toLowerCase();
      if (!entry.contains('match !')) {
        currentStreak = 0;
        currentStreakOwner = null;
        continue;
      }

      final actor = _resolveMatchActor(entry, opponentNames);
      if (actor == null) {
        currentStreak = 0;
        currentStreakOwner = null;
        continue;
      }

      recentMatches++;
      if (i <= 1) opponentJustMatched = true;

      if (currentStreakOwner == actor) {
        currentStreak++;
      } else {
        currentStreakOwner = actor;
        currentStreak = 1;
      }

      if (currentStreak > longestStreak) {
        longestStreak = currentStreak;
      }
    }

    return _OpponentMomentum(
      recentMatches: recentMatches,
      longestStreak: longestStreak,
      opponentJustMatched: opponentJustMatched,
    );
  }

  static String? _resolveMatchActor(String line, List<String> opponentNames) {
    for (final name in opponentNames) {
      if (name.isNotEmpty && line.contains(name)) {
        return name;
      }
    }
    return null;
  }

  static int _minInt(int a, int b) => a < b ? a : b;

  static bool _recentActionContains(
      GameState gs, String playerName, List<String> keywords,
      {int limit = 12}) {
    final name = playerName.toLowerCase();
    int count = 0;
    for (final entry in gs.actionHistory) {
      if (count >= limit) break;
      count++;
      final lower = entry.toLowerCase();
      if (!lower.contains(name)) continue;
      for (final keyword in keywords) {
        if (lower.contains(keyword)) return true;
      }
    }
    return false;
  }

  static _DutchDecisionProfile _profileForDifficulty(BotDifficulty difficulty) {
    final tier = _tierFromDifficulty(difficulty);
    switch (tier) {
      case _DutchTier.bronze:
        return const _DutchDecisionProfile(
          tier: _DutchTier.bronze,
          hybridBaseThreshold: 6,
          opponentEstimatePenalty: 3,
          baseRisk: 6.0,
          scoreRiskPerPoint: 0.38,
          uncertaintyRiskWeight: 2.3,
          cardDisadvantageRiskWeight: 1.2,
          urgencyRiskReduction: 0.05,
          endgameRiskReduction: 0.10,
          timingRiskReduction: 0.00,
          cardGapWeight: 0.05,
          leadWeight: 0.03,
          urgencyWeight: 0.10,
          pressureWeight: 0.05,
          endgameOpportunityBonus: 0.00,
          timingOpportunityBonus: 0.00,
          badDrawOpportunityWeight: 0.02,
          decisionBias: -2.20,
        );
      case _DutchTier.silver:
        return const _DutchDecisionProfile(
          tier: _DutchTier.silver,
          hybridBaseThreshold: 5,
          opponentEstimatePenalty: 2,
          baseRisk: 4.4,
          scoreRiskPerPoint: 0.28,
          uncertaintyRiskWeight: 1.75,
          cardDisadvantageRiskWeight: 0.92,
          urgencyRiskReduction: 0.12,
          endgameRiskReduction: 0.18,
          timingRiskReduction: 0.06,
          cardGapWeight: 0.11,
          leadWeight: 0.07,
          urgencyWeight: 0.20,
          pressureWeight: 0.11,
          endgameOpportunityBonus: 0.06,
          timingOpportunityBonus: 0.05,
          badDrawOpportunityWeight: 0.04,
          decisionBias: -1.45,
        );
      case _DutchTier.gold:
        return const _DutchDecisionProfile(
          tier: _DutchTier.gold,
          hybridBaseThreshold: 4,
          opponentEstimatePenalty: 1,
          baseRisk: 3.2,
          scoreRiskPerPoint: 0.22,
          uncertaintyRiskWeight: 1.20,
          cardDisadvantageRiskWeight: 0.70,
          urgencyRiskReduction: 0.20,
          endgameRiskReduction: 0.28,
          timingRiskReduction: 0.12,
          cardGapWeight: 0.18,
          leadWeight: 0.12,
          urgencyWeight: 0.32,
          pressureWeight: 0.20,
          endgameOpportunityBonus: 0.14,
          timingOpportunityBonus: 0.12,
          badDrawOpportunityWeight: 0.06,
          decisionBias: 0.20,
        );
      case _DutchTier.platinum:
        return const _DutchDecisionProfile(
          tier: _DutchTier.platinum,
          hybridBaseThreshold: 3,
          opponentEstimatePenalty: 0,
          baseRisk: 0.55,
          scoreRiskPerPoint: 0.03,
          uncertaintyRiskWeight: 0.30,
          cardDisadvantageRiskWeight: 0.18,
          urgencyRiskReduction: 0.90,
          endgameRiskReduction: 1.20,
          timingRiskReduction: 0.90,
          cardGapWeight: 0.42,
          leadWeight: 0.30,
          urgencyWeight: 1.05,
          pressureWeight: 0.65,
          endgameOpportunityBonus: 1.20,
          timingOpportunityBonus: 1.30,
          badDrawOpportunityWeight: 0.24,
          decisionBias: 3.20,
        );
    }
  }

  static _DutchTier _tierFromDifficulty(BotDifficulty difficulty) {
    switch (difficulty.name) {
      case 'Bronze':
        return _DutchTier.bronze;
      case 'Argent':
        return _DutchTier.silver;
      case 'Or':
      case 'Hard':
      case 'Insane':
        return _DutchTier.gold;
      case 'Platine':
      case 'Nightmare':
      case 'Impossible':
        return _DutchTier.platinum;
      default:
        if (difficulty.matchAccuracy >= 0.99 &&
            difficulty.reactionSpeed >= 0.98) {
          return _DutchTier.platinum;
        }
        if (difficulty.matchAccuracy >= 0.95 &&
            difficulty.reactionSpeed >= 0.9) {
          return _DutchTier.gold;
        }
        if (difficulty.matchAccuracy >= 0.9) {
          return _DutchTier.silver;
        }
        return _DutchTier.bronze;
    }
  }
}

enum _DutchTier { bronze, silver, gold, platinum }

class _DutchDecisionProfile {
  final _DutchTier tier;
  final int hybridBaseThreshold;
  final int opponentEstimatePenalty;
  final double baseRisk;
  final double scoreRiskPerPoint;
  final double uncertaintyRiskWeight;
  final double cardDisadvantageRiskWeight;
  final double urgencyRiskReduction;
  final double endgameRiskReduction;
  final double timingRiskReduction;
  final double cardGapWeight;
  final double leadWeight;
  final double urgencyWeight;
  final double pressureWeight;
  final double endgameOpportunityBonus;
  final double timingOpportunityBonus;
  final double badDrawOpportunityWeight;
  final double decisionBias;

  const _DutchDecisionProfile({
    required this.tier,
    required this.hybridBaseThreshold,
    required this.opponentEstimatePenalty,
    required this.baseRisk,
    required this.scoreRiskPerPoint,
    required this.uncertaintyRiskWeight,
    required this.cardDisadvantageRiskWeight,
    required this.urgencyRiskReduction,
    required this.endgameRiskReduction,
    required this.timingRiskReduction,
    required this.cardGapWeight,
    required this.leadWeight,
    required this.urgencyWeight,
    required this.pressureWeight,
    required this.endgameOpportunityBonus,
    required this.timingOpportunityBonus,
    required this.badDrawOpportunityWeight,
    required this.decisionBias,
  });
}

class _DutchDecisionContext {
  final int opponentCount;
  final int bestOpponentEstimate;
  final double avgOpponentEstimate;
  final int minOpponentCards;
  final double avgOpponentCards;
  final double tablePressure;

  const _DutchDecisionContext({
    required this.opponentCount,
    required this.bestOpponentEstimate,
    required this.avgOpponentEstimate,
    required this.minOpponentCards,
    required this.avgOpponentCards,
    required this.tablePressure,
  });
}

class _ExpertDutchConclusions {
  final bool duelActive;
  final int? duelKnownOpponentScore;
  final bool opponentMomentumHot;
  final bool opponentCanFinishSoon;
  final bool tableExplosive;
  final bool safeWindow;
  final bool forceImmediateClose;

  const _ExpertDutchConclusions({
    required this.duelActive,
    required this.duelKnownOpponentScore,
    required this.opponentMomentumHot,
    required this.opponentCanFinishSoon,
    required this.tableExplosive,
    required this.safeWindow,
    required this.forceImmediateClose,
  });
}

class _OpponentMomentum {
  final int recentMatches;
  final int longestStreak;
  final bool opponentJustMatched;

  const _OpponentMomentum({
    required this.recentMatches,
    required this.longestStreak,
    required this.opponentJustMatched,
  });
}

class BotDutchObservationTrace {
  final String botName;
  final String tierLabel;
  final String phaseLabel;
  final int unknownCount;
  final int knownScore;
  final int perceivedScore;
  final double expectedUnknown;
  final bool canDutchState;
  final bool shouldCallDutch;
  final String conclusion;
  final int opponentCount;
  final int bestOpponentEstimate;
  final double avgOpponentEstimate;
  final int minOpponentCards;
  final double avgOpponentCards;
  final double tablePressure;
  final int adjustedOpponentEstimate;
  final int margin;
  final int hybridThreshold;
  final bool canBreakHybridThreshold;
  final int? duelKnownOpponentScore;
  final bool duelActive;
  final bool opponentMomentumHot;
  final bool opponentCanFinishSoon;
  final bool tableExplosive;
  final bool safeWindow;
  final bool forceImmediateClose;
  final List<String> blockers;
  final List<String> opportunities;

  const BotDutchObservationTrace({
    required this.botName,
    required this.tierLabel,
    required this.phaseLabel,
    required this.unknownCount,
    required this.knownScore,
    required this.perceivedScore,
    required this.expectedUnknown,
    required this.canDutchState,
    required this.shouldCallDutch,
    required this.conclusion,
    required this.opponentCount,
    required this.bestOpponentEstimate,
    required this.avgOpponentEstimate,
    required this.minOpponentCards,
    required this.avgOpponentCards,
    required this.tablePressure,
    required this.adjustedOpponentEstimate,
    required this.margin,
    required this.hybridThreshold,
    required this.canBreakHybridThreshold,
    required this.duelKnownOpponentScore,
    required this.duelActive,
    required this.opponentMomentumHot,
    required this.opponentCanFinishSoon,
    required this.tableExplosive,
    required this.safeWindow,
    required this.forceImmediateClose,
    required this.blockers,
    required this.opportunities,
  });
}
