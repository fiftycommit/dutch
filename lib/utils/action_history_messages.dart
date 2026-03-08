import '../models/playing_card.dart';

/// Utilitaire commun pour générer les textes d'action (solo + multi).
/// Centralise tous les messages affichés dans l'historique de la partie.
class ActionHistoryMessages {
  ActionHistoryMessages._();

  // ─── Pioche ──────────────────────────────────────────────────────────

  static String draw(String playerName) => "$playerName a pioché.";

  // ─── Défausse de la carte piochée ────────────────────────────────────

  static String discardDrawn(String playerName, PlayingCard card,
      {required bool isLocal, bool hasPower = false}) {
    final cardName = card.displayName;
    if (hasPower) {
      final verb = isLocal ? 'avez défaussé' : 'a défaussé';
      return "$playerName $verb la carte $cardName";
    }
    final verb = isLocal ? "n'avez pas gardé" : "n'a pas gardé";
    return "$playerName $verb la carte $cardName (pas intéressé)";
  }

  // ─── Remplacement (échange avec la pioche) ──────────────────────────

  static String replaceCard(String playerName, PlayingCard oldCard,
      {required bool isLocal}) {
    final isDame = oldCard.displayName == 'Dame';
    final cardName = oldCard.displayName.trimLeft();
    if (isLocal) {
      return "Vous avez remplacé votre $cardName par la carte piochée";
    } else {
      final possessif = isDame ? 'sa' : 'son';
      return "$playerName a remplacé $possessif $cardName par la carte piochée";
    }
  }

  // ─── Match ───────────────────────────────────────────────────────────

  static String matchSuccess(String playerName, PlayingCard card,
      {required bool isLocal}) {
    final article = card.displayName == 'Dame' ? 'une' : 'un';
    if (isLocal) {
      return "MATCH ! - Vous avez posé $article ${card.displayName} !";
    }
    return "MATCH ! - $playerName a posé $article ${card.displayName} !";
  }

  static String matchFailed(
      String playerName, PlayingCard card, PlayingCard topDiscard) {
    return "$playerName a raté son match (${card.displayName} ≠ ${topDiscard.displayName}) ! Pénalité !";
  }

  // ─── Pénalité ────────────────────────────────────────────────────────

  static String penalty(String playerName) =>
      "$playerName a pris une carte de pénalité.";

  // ─── Prendre de la défausse ──────────────────────────────────────────

  static String takeFromDiscard(String playerName, PlayingCard card) =>
      "$playerName a pris ${card.displayName} de la défausse.";

  // ─── Pouvoirs spéciaux ───────────────────────────────────────────────

  static String powerLookOwn(String playerName, int cardIndex) =>
      "👁️ $playerName a regardé sa carte #${cardIndex + 1}";

  static String powerSpy(String playerName, String targetName, int cardIndex) =>
      "👁 $playerName a espionné $targetName (carte #${cardIndex + 1})";

  static String powerSwap(String playerName, String targetName) =>
      "🔄 $playerName a échangé avec $targetName";

  static String powerSwapDetailed(
          String p1Name, int idx1, String p2Name, int idx2) =>
      "Échange : $p1Name carte #${idx1 + 1} ↔ $p2Name carte #${idx2 + 1}.";

  static String powerJoker(String playerName, String targetName) =>
      "JOKER ! $playerName a mélangé $targetName !";

  static String powerSkipped() => "⏭️ Pouvoir spécial a été ignoré.";

  static String powerUsed(String playerName) =>
      "$playerName a utilisé son pouvoir.";

  // ─── Dutch ───────────────────────────────────────────────────────────

  static String dutch(String playerName) => "📢 $playerName a crié DUTCH !";

  // ─── Deck vide ───────────────────────────────────────────────────────

  static String deckRefilled(int cardCount) =>
      "🔄 Pioche vide ! Défausse mélangée ($cardCount cartes)";

  static String noCardsLeft() => "Plus de cartes disponibles - Fin de partie";
}
