import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SBMM local : source de vérité côté client pour le cursor/skill du joueur.
///
/// Persiste le profil SBMM en SharedPreferences avec signature HMAC-SHA256.
/// Le profil est scopé par slot local (Joueur 1/2/3) : chaque profil de la
/// sélection initiale a son propre cursor et son propre archétype.
/// Toute modification manuelle du payload est détectée au chargement et
/// déclenche un reset avec flag [consumeTamperFlag] pour affichage UI.
class SBMMLocalService {
  static const String _prefsKeyBase = 'sbmm_local_profile_slot';
  static const int _maxRecentResults = 20;
  static const int _currentVersion = 4;

  // Clés historiques purgées silencieusement au premier accès.
  static const String _legacyKeyV1 = 'sbmm_local_profile_v1';
  static const String _legacyKeyV2Base = 'sbmm_local_profile_v2';

  static final Map<int, SBMMLocalProfile> _cachedProfiles = {};
  static bool _tamperDetected = false;
  static bool _legacyPurged = false;

  static String _scopeFor(int slotId) => 'slot_$slotId';
  static String _prefsKey(int slotId) => '${_prefsKeyBase}_$slotId';

  /// À true si la dernière lecture a détecté un payload altéré.
  /// L'appel remet le flag à false (one-shot).
  static bool consumeTamperFlag() {
    final v = _tamperDetected;
    _tamperDetected = false;
    return v;
  }

  static Future<void> _purgeLegacyKeysOnce(SharedPreferences prefs) async {
    if (_legacyPurged) return;
    _legacyPurged = true;

    if (prefs.containsKey(_legacyKeyV1)) {
      await prefs.remove(_legacyKeyV1);
    }
    if (prefs.containsKey(_legacyKeyV2Base)) {
      await prefs.remove(_legacyKeyV2Base);
    }
    // Anciennes clés scopées par UID Firebase : sbmm_local_profile_v2_<uid>.
    final toRemove = prefs
        .getKeys()
        .where((k) => k.startsWith('${_legacyKeyV2Base}_'))
        .toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
  }

  static Future<SBMMLocalProfile> getProfile({required int slotId}) async {
    final cached = _cachedProfiles[slotId];
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    await _purgeLegacyKeysOnce(prefs);

    final raw = prefs.getString(_prefsKey(slotId));
    if (raw != null) {
      final profile = _parseAndVerify(raw, _scopeFor(slotId));
      if (profile != null) {
        _cachedProfiles[slotId] = profile;
        return profile;
      }
      // Signature invalide, version inconnue, ou payload signé pour un autre
      // slot → reset + flag tamper.
      _tamperDetected = true;
      if (kDebugMode) {
        debugPrint('🚨 SBMM: signature invalide slot $slotId, profil réinitialisé');
      }
    }

    final fresh = SBMMLocalProfile.initial();
    _cachedProfiles[slotId] = fresh;
    await _saveProfile(fresh, slotId: slotId);
    return fresh;
  }

  /// Vérifie la signature + la correspondance de scope.
  static SBMMLocalProfile? _parseAndVerify(String raw, String expectedScope) {
    try {
      final wrapped = jsonDecode(raw) as Map<String, dynamic>;
      final data = wrapped['d'] as String;
      final sig = wrapped['s'] as String;
      final version = wrapped['v'] as int?;
      if (version != _currentVersion) return null;

      final scope = wrapped['u'] as String?;
      if (scope != expectedScope) return null;
      if (_sign('$scope|$data') != sig) return null;

      return SBMMLocalProfile.fromJson(
        jsonDecode(data) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveProfile(
    SBMMLocalProfile profile, {
    required int slotId,
  }) async {
    final scope = _scopeFor(slotId);
    _cachedProfiles[slotId] = profile;
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(profile.toJson());
    final wrapped = jsonEncode({
      'v': _currentVersion,
      'u': scope,
      'd': data,
      's': _sign('$scope|$data'),
    });
    await prefs.setString(_prefsKey(slotId), wrapped);
  }

  // ---------------------------------------------------------------------------
  // Signature HMAC-SHA256.
  //
  // Le secret est divisé en fragments volontairement anodins pour rendre
  // l'extraction par `strings` / binaire moins évidente. Ce n'est pas de la
  // vraie crypto serveur — juste de la friction pour décourager les édits
  // manuels triviaux. Un attaquant motivé peut toujours reverse le binaire.
  // ---------------------------------------------------------------------------

  static final List<int> _saltA = [
    0x44, 0x75, 0x74, 0x63, 0x68, 0x37, 0x38, 0x2d
  ];
  static final List<int> _saltB = [
    0x73, 0x62, 0x6d, 0x6d, 0x2d, 0x76, 0x32, 0x2d
  ];
  static final List<int> _saltC = [
    0x61, 0x39, 0x7b, 0x3e, 0x11, 0xcc, 0x4f, 0x02,
    0xe7, 0x1a, 0x88, 0x5d, 0xf6, 0x23, 0xb0, 0x9e
  ];

  static List<int> _secret() => [..._saltA, ..._saltB, ..._saltC];

  static String _sign(String payload) {
    final hmac = Hmac(sha256, _secret());
    return hmac.convert(utf8.encode(payload)).toString();
  }

  /// Sigmoïde centrée à 600 MMR.
  static double mmrToCursor(double mmr) => 1 / (1 + exp(-(mmr - 600) / 200));

  /// Cursor → niveau de bot (3 tiers).
  static String cursorToSkillLevel(double cursor, {Random? rng}) {
    final r = rng ?? Random();
    if (cursor < 0.35) return 'bronze';
    if (cursor < 0.45) {
      return r.nextDouble() < (cursor - 0.35) / 0.1 ? 'silver' : 'bronze';
    }
    if (cursor < 0.65) return 'silver';
    if (cursor < 0.75) {
      return r.nextDouble() < (cursor - 0.65) / 0.1 ? 'gold' : 'silver';
    }
    return 'gold';
  }

  /// Génère le mix de bots pour une partie, en spread autour du cursor joueur.
  /// Les personnalités (BotBehavior) sont choisies en contre-archétype du
  /// joueur : un joueur "dutcher" affronte des bots rapides, un "dominant"
  /// des bots agressifs, etc. L'adaptation reste invisible (pas annoncée).
  static Future<SBMMLocalMix> getBotMix({
    required int botCount,
    required int slotId,
  }) async {
    final profile = await getProfile(slotId: slotId);
    final rng = Random();
    final levels = <String>[];
    final spread = botCount > 1 ? 0.15 : 0.0;

    for (var i = 0; i < botCount; i++) {
      final offset = botCount > 1
          ? -spread + (2 * spread * i) / (botCount - 1)
          : 0.0;
      final eff = (profile.cursor + offset).clamp(0.0, 1.0);
      levels.add(cursorToSkillLevel(eff, rng: rng));
    }

    const order = {'bronze': 0, 'silver': 1, 'gold': 2};
    levels.sort((a, b) => (order[a] ?? 0).compareTo(order[b] ?? 0));

    final archetype = detectArchetype(profile);
    final behaviors = _behaviorsForArchetype(archetype, botCount, rng);

    return SBMMLocalMix(
      botLevels: levels,
      botBehaviors: behaviors,
      cursor: profile.cursor,
      mmr: profile.mmr.round(),
      archetype: archetype,
    );
  }

  /// Détecte l'archétype du joueur à partir de son historique.
  /// Nécessite au moins 3 parties pour sortir du défaut "balanced".
  static PlayerArchetype detectArchetype(SBMMLocalProfile profile) {
    if (profile.gamesPlayed < 3) return PlayerArchetype.balanced;

    final recent = profile.recentResults;
    final window = recent.length > 10
        ? recent.sublist(recent.length - 10)
        : recent;
    if (window.isEmpty) return PlayerArchetype.balanced;

    final wins = window.where((r) => r.rank == 1).length;
    final winRate = wins / window.length;
    final dutchCalls = window.where((r) => r.dutchCalled).length;
    final dutchRate = dutchCalls / window.length;

    if (dutchRate >= 0.4) return PlayerArchetype.dutcher;
    if (winRate >= 0.55) return PlayerArchetype.dominant;
    if (winRate <= 0.25) return PlayerArchetype.learner;
    return PlayerArchetype.balanced;
  }

  /// Matrice counter-archetype : quelles personnalités de bots opposer au
  /// joueur pour maximiser tension et variété sans frustration.
  ///
  /// - dominant  → bots `aggressive` qui pressent en retour (challenge).
  /// - dutcher   → bots `fast` qui punissent les dutchs mal calibrés.
  /// - learner   → bots `balanced` prévisibles (encouragement).
  /// - balanced  → mix varié (1 de chaque style si possible).
  static List<String> _behaviorsForArchetype(
    PlayerArchetype archetype,
    int botCount,
    Random rng,
  ) {
    switch (archetype) {
      case PlayerArchetype.dominant:
        // Presque tout aggressive, 1 balanced pour la variété.
        return List.generate(botCount, (i) {
          if (botCount >= 2 && i == botCount - 1) return 'balanced';
          return 'aggressive';
        });
      case PlayerArchetype.dutcher:
        // Majorité fast (punition timing), 1 aggressive en pression.
        return List.generate(botCount, (i) {
          if (botCount >= 3 && i == 0) return 'aggressive';
          return 'fast';
        });
      case PlayerArchetype.learner:
        // Tout balanced : lisible, pas de panique.
        return List.generate(botCount, (_) => 'balanced');
      case PlayerArchetype.balanced:
        // Mix varié — roue des styles selon le nombre de bots.
        const pool = ['balanced', 'fast', 'aggressive'];
        final shuffled = [...pool]..shuffle(rng);
        return List.generate(botCount, (i) => shuffled[i % shuffled.length]);
    }
  }

  /// Enregistre le résultat d'une partie et ajuste le cursor.
  ///
  /// Le cursor bouge selon 4 mécanismes :
  /// 1. **Poids du lobby** sur le placement : 1v1 pèse ~45% d'un 1v5.
  /// 2. **Facteur lobby** sur la réactivité : gros lobby → facteur ×1.8,
  ///    1v1 → facteur ×0.5. Un smurf en lobby plein monte très vite.
  /// 3. **Anti-smurf** : 2+ victoires consécutives en lobby ≥4 → facteur ×2.5.
  /// 4. **Amortissement directionnel** : freinage léger quand le cursor
  ///    s'éloigne du centre, aucun frein quand il revient vers le milieu.
  static Future<SBMMLocalProfile> recordGame({
    required int slotId,
    required int rank,
    required int totalPlayers,
    bool dutchCalled = false,
    bool dutchWon = false,
  }) async {
    final profile = await getProfile(slotId: slotId);

    final result = SBMMLocalResult(
      rank: rank,
      totalPlayers: totalPlayers,
      timestamp: DateTime.now().toIso8601String(),
      dutchCalled: dutchCalled,
      dutchWon: dutchWon,
    );
    final recent = [...profile.recentResults, result];
    if (recent.length > _maxRecentResults) {
      recent.removeRange(0, recent.length - _maxRecentResults);
    }

    // Fenêtre glissante de 7 parties.
    final window =
        recent.length > 7 ? recent.sublist(recent.length - 7) : recent;

    // Placement pondéré par la taille du lobby.
    final placementScores = window.map((r) {
      if (r.totalPlayers <= 1) return 0.5;
      final rawPlacement =
          (r.totalPlayers - r.rank) / (r.totalPlayers - 1);
      final lobbyWeight =
          sqrt((r.totalPlayers - 1).clamp(1, 9)) / sqrt(5);
      return 0.5 + (rawPlacement - 0.5) * lobbyWeight;
    }).toList();

    final avgPlacement =
        placementScores.reduce((a, b) => a + b) / placementScores.length;
    final delta = avgPlacement - 0.5;

    // ── Facteur de base ──
    final gamesPlayed = profile.gamesPlayed + 1;
    final baseFactor = gamesPlayed <= 5 ? 0.15 : 0.10;

    // ── Facteur lobby : gros lobby = plus réactif ──
    // 2j → ×0.5, 3j → ×0.83, 4j → ×1.15, 5j → ×1.48, 6j → ×1.8
    final lobbyFactor = 0.5 + (totalPlayers - 2) * 0.325;

    // ── Anti-smurf : victoires consécutives en lobby ≥4 ──
    final recentWins = window.reversed
        .take(3)
        .where((r) => r.rank == 1 && r.totalPlayers >= 4)
        .length;
    final smurfBoost = recentWins >= 2 ? 2.5 : 1.0;

    // ── Amortissement directionnel ──
    // S'éloigne du centre → frein léger. Revient vers le centre → aucun frein.
    final distFromCenter = (profile.cursor - 0.5).abs();
    final movingAway = (delta > 0 && profile.cursor >= 0.5) ||
        (delta < 0 && profile.cursor <= 0.5);
    final damping = movingAway
        ? 1.0 - (distFromCenter * 1.2).clamp(0.0, 0.6)
        : 1.0;

    final effectiveFactor = baseFactor * lobbyFactor * smurfBoost * damping;
    final newCursor =
        (profile.cursor + delta * effectiveFactor).clamp(0.0, 1.0);

    final updated = profile.copyWith(
      cursor: newCursor,
      gamesPlayed: gamesPlayed,
      wins: profile.wins + (rank == 1 ? 1 : 0),
      recentResults: recent,
      lastUpdated: DateTime.now().toIso8601String(),
    );

    await _saveProfile(updated, slotId: slotId);

    if (kDebugMode) {
      debugPrint(
        '🎯 SBMM[slot $slotId]: ${profile.cursor.toStringAsFixed(3)} → '
        '${newCursor.toStringAsFixed(3)} '
        '(rank $rank/$totalPlayers, lobby: ×${lobbyFactor.toStringAsFixed(1)}, '
        'smurf: ×${smurfBoost.toStringAsFixed(1)}, '
        'damp: ${damping.toStringAsFixed(2)}, games: $gamesPlayed)',
      );
    }

    return updated;
  }

  /// Réinitialise le profil SBMM du slot donné, ou de tous les slots si null.
  static Future<void> reset({int? slotId}) async {
    _tamperDetected = false;
    final prefs = await SharedPreferences.getInstance();
    if (slotId != null) {
      _cachedProfiles.remove(slotId);
      await prefs.remove(_prefsKey(slotId));
      return;
    }
    _cachedProfiles.clear();
    final toRemove = prefs
        .getKeys()
        .where((k) => k.startsWith('${_prefsKeyBase}_'))
        .toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
  }

  /// Wording doux pour afficher le skill du joueur — 3 tiers alignés sur
  /// les zones de bots :
  ///   < 0.45 : majorité bronze → initié
  ///   < 0.75 : zone silver/mix → régulier
  ///   >= 0.75 : zone gold → confirmé
  static String skillLabelFromCursor(double cursor) {
    if (cursor < 0.45) return 'Joueur initié';
    if (cursor < 0.75) return 'Joueur régulier';
    return 'Joueur confirmé';
  }
}

/// Archétypes détectés à partir de l'historique récent du joueur.
/// Sert à choisir un counter-mix de personnalités de bots.
enum PlayerArchetype {
  /// Peu de parties ou résultats équilibrés : mix varié de bots.
  balanced,

  /// Gagne souvent : on oppose des bots agressifs pour maintenir la tension.
  dominant,

  /// Appelle Dutch fréquemment : on oppose des bots rapides qui punissent
  /// les déclarations mal timées.
  dutcher,

  /// Peu de victoires sur la fenêtre : on oppose des bots prévisibles
  /// (balanced) pour laisser le temps d'apprendre.
  learner,
}

class SBMMLocalProfile {
  final double mmr;
  final double cursor;
  final int gamesPlayed;
  final int wins;
  final List<SBMMLocalResult> recentResults;
  final String lastUpdated;

  const SBMMLocalProfile({
    required this.mmr,
    required this.cursor,
    required this.gamesPlayed,
    required this.wins,
    required this.recentResults,
    required this.lastUpdated,
  });

  factory SBMMLocalProfile.initial() {
    const mmr = 600.0;
    return SBMMLocalProfile(
      mmr: mmr,
      cursor: 0.5,
      gamesPlayed: 0,
      wins: 0,
      recentResults: const [],
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }

  factory SBMMLocalProfile.fromJson(Map<String, dynamic> j) =>
      SBMMLocalProfile(
        mmr: (j['mmr'] as num).toDouble(),
        cursor: (j['cursor'] as num).toDouble(),
        gamesPlayed: j['gamesPlayed'] as int,
        wins: j['wins'] as int,
        recentResults: (j['recentResults'] as List)
            .map((e) => SBMMLocalResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastUpdated: j['lastUpdated'] as String,
      );

  Map<String, dynamic> toJson() => {
        'mmr': mmr,
        'cursor': cursor,
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'recentResults': recentResults.map((r) => r.toJson()).toList(),
        'lastUpdated': lastUpdated,
      };

  SBMMLocalProfile copyWith({
    double? mmr,
    double? cursor,
    int? gamesPlayed,
    int? wins,
    List<SBMMLocalResult>? recentResults,
    String? lastUpdated,
  }) =>
      SBMMLocalProfile(
        mmr: mmr ?? this.mmr,
        cursor: cursor ?? this.cursor,
        gamesPlayed: gamesPlayed ?? this.gamesPlayed,
        wins: wins ?? this.wins,
        recentResults: recentResults ?? this.recentResults,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

class SBMMLocalResult {
  final int rank;
  final int totalPlayers;
  final String timestamp;
  final bool dutchCalled;
  final bool dutchWon;

  const SBMMLocalResult({
    required this.rank,
    required this.totalPlayers,
    required this.timestamp,
    this.dutchCalled = false,
    this.dutchWon = false,
  });

  factory SBMMLocalResult.fromJson(Map<String, dynamic> j) => SBMMLocalResult(
        rank: j['rank'] as int,
        totalPlayers: j['totalPlayers'] as int,
        timestamp: j['timestamp'] as String,
        dutchCalled: j['dutchCalled'] as bool? ?? false,
        dutchWon: j['dutchWon'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'totalPlayers': totalPlayers,
        'timestamp': timestamp,
        'dutchCalled': dutchCalled,
        'dutchWon': dutchWon,
      };
}

class SBMMLocalMix {
  final List<String> botLevels;
  final List<String> botBehaviors;
  final double cursor;
  final int mmr;
  final PlayerArchetype archetype;

  const SBMMLocalMix({
    required this.botLevels,
    required this.botBehaviors,
    required this.cursor,
    required this.mmr,
    required this.archetype,
  });
}
