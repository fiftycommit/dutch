import '../models/playing_card.dart';

/// Utilitaire commun pour générer les textes d'action (solo + multi).
/// Centralise tous les messages affichés dans l'historique de la partie.
class ActionHistoryMessages {
  ActionHistoryMessages._();

  // ─── Pioche ──────────────────────────────────────────────────────────

  static String draw(String playerName) => "$playerName pioche.";

  // ─── Défausse de la carte piochée ────────────────────────────────────

  static String discardDrawn(String playerName, PlayingCard card,
      {required bool isLocal, bool hasPower = false}) {
    final cardName = card.displayName == 'e Dame' ? ' Dame' : card.displayName;
    if (hasPower) {
      final verb = isLocal ? 'défaussez' : 'défausse';
      return "$playerName $verb la carte$cardName";
    }
    final verb = isLocal ? "ne gardez pas" : "ne garde pas";
    return "$playerName $verb la carte$cardName (pas intéressé)";
  }

  // ─── Remplacement (échange avec la pioche) ──────────────────────────

  static String replaceCard(String playerName, PlayingCard oldCard,
      {required bool isLocal}) {
    final isDame = oldCard.displayName == 'e Dame';
    final cardName = isDame ? 'Dame' : oldCard.displayName.trimLeft();
    if (isLocal) {
      return "Vous remplacez votre $cardName par la carte piochée";
    } else {
      final possessif = isDame ? 'sa' : 'son';
      return "$playerName remplace $possessif $cardName par la carte piochée";
    }
  }

  // ─── Match ───────────────────────────────────────────────────────────

  static String matchSuccess(String playerName, PlayingCard card,
      {required bool isLocal}) {
    if (isLocal) {
      return "MATCH ! - Vous avez posé un${card.displayName} !";
    }
    return "MATCH ! - $playerName pose un${card.displayName} !";
  }

  static String matchFailed(
      String playerName, PlayingCard card, PlayingCard topDiscard) {
    return "$playerName rate son match (${card.displayName} ≠ ${topDiscard.displayName}) ! Pénalité !";
  }

  // ─── Pénalité ────────────────────────────────────────────────────────

  static String penalty(String playerName) =>
      "$playerName prend une carte de pénalité.";

  // ─── Prendre de la défausse ──────────────────────────────────────────

  static String takeFromDiscard(String playerName, PlayingCard card) =>
      "$playerName prend ${card.displayName} de la défausse.";

  // ─── Pouvoirs spéciaux ───────────────────────────────────────────────

  static String powerLookOwn(String playerName, int cardIndex) =>
      "👁️ $playerName regarde sa carte #${cardIndex + 1}";

  static String powerSpy(String playerName, String targetName, int cardIndex) =>
      "👁 $playerName espionne $targetName (carte #${cardIndex + 1})";

  static String powerSwap(String playerName, String targetName) =>
      "🔄 $playerName échange avec $targetName";

  static String powerSwapDetailed(
          String p1Name, int idx1, String p2Name, int idx2) =>
      "Échange : $p1Name carte #${idx1 + 1} ↔ $p2Name carte #${idx2 + 1}.";

  static String powerJoker(String playerName, String targetName) =>
      "JOKER ! $playerName mélange $targetName !";

  static String powerSkipped() => "⏭️ Pouvoir spécial ignoré.";

  static String powerUsed(String playerName) =>
      "$playerName a utilisé son pouvoir.";

  // ─── Dutch ───────────────────────────────────────────────────────────

  static String dutch(String playerName) => "📢 $playerName crie DUTCH !";

  // ─── Deck vide ───────────────────────────────────────────────────────

  static String deckRefilled(int cardCount) =>
      "🔄 Pioche vide ! Défausse mélangée ($cardCount cartes)";

  static String noCardsLeft() => "Plus de cartes disponibles - Fin de partie";
}
