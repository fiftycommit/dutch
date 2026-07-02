import 'package:flutter/foundation.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';

/// Interface abstraite pour contrôler le jeu (solo et multiplayer)
/// Pattern Strategy : Encapsule les différences de comportement entre modes
/// Principe SOLID: DIP - L'UI dépend de cette abstraction, pas des implémentations concrètes
/// Principe SOLID: ISP - Interface minimale pour les actions de jeu
abstract class IGameController implements Listenable {
  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS - État du jeu
  // ═══════════════════════════════════════════════════════════════════════════

  /// État actuel du jeu (null si pas de partie en cours)
  GameState? get gameState;

  /// Indique si une partie est en cours
  bool get hasActiveGame;

  /// Indique si une action est en cours de traitement
  bool get isProcessing;

  /// Indique si le jeu est en pause
  bool get isPaused;

  /// Indices des cartes qui doivent vibrer (erreur de match)
  Set<int> get shakingCardIndices;

  /// Temps de réaction actuel en millisecondes
  int get currentReactionTimeMs;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS - Joueur local
  // ═══════════════════════════════════════════════════════════════════════════

  /// Retourne le joueur local (humain en solo, joueur connecté en multi)
  Player? get localPlayer;

  /// Vérifie si c'est le tour du joueur local
  bool get isLocalPlayerTurn;

  /// Vérifie si le joueur local peut interagir (son tour + phase correcte)
  bool get canLocalPlayerAct;

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS DE JEU - Phase de pioche
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pioche une carte du deck
  void drawCard();

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS DE JEU - Phase de remplacement/défausse
  // ═══════════════════════════════════════════════════════════════════════════

  /// Remplace une carte de la main par la carte piochée
  void replaceCard(int cardIndex);

  /// Défausse la carte piochée sans remplacer
  void discardDrawnCard();

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS DE JEU - Phase de réaction
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tente de matcher une carte pendant la phase de réaction
  void attemptMatch(int cardIndex);

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS DE JEU - Dutch
  // ═══════════════════════════════════════════════════════════════════════════

  /// Appelle Dutch pour terminer la manche
  void callDutch();

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS DE JEU - Pouvoirs spéciaux
  // ═══════════════════════════════════════════════════════════════════════════

  /// Passe le pouvoir spécial sans l'utiliser
  void skipSpecialPower();

  /// Gère le tap sur une carte (logique déléguée au controller selon la phase)
  void handleCardTap(int cardIndex);
}

/// Extension avec des méthodes utilitaires calculées
extension IGameControllerExtensions on IGameController {
  /// Vérifie si le joueur local peut piocher
  bool get canDraw =>
      gameState != null &&
      isLocalPlayerTurn &&
      gameState!.phase == GamePhase.playing &&
      gameState!.drawnCard == null;

  /// Vérifie si le joueur local peut prendre de la défausse
  bool get canTakeFromDiscard => canDraw && gameState!.discardPile.isNotEmpty;

  /// Vérifie si le joueur local peut remplacer ou défausser
  bool get canReplaceOrDiscard =>
      gameState != null && isLocalPlayerTurn && gameState!.drawnCard != null;

  /// Vérifie si le joueur local peut appeler Dutch
  bool get canCallDutch => canDraw;

  /// Vérifie si le joueur local peut matcher (phase de réaction)
  bool get canMatch =>
      gameState != null && gameState!.phase == GamePhase.reaction;

  /// Vérifie si un pouvoir spécial est en attente
  bool get isWaitingForSpecialPower =>
      gameState != null &&
      gameState!.phase == GamePhase.specialPower &&
      isLocalPlayerTurn;
}
