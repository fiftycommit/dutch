// Hiérarchie d'exceptions pour Dutch'78.
// Permet un traitement d'erreurs structuré et typé dans tout le projet.

/// Exception de base de l'application — toutes les exceptions custom en héritent.
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const AppException(
    this.message, {
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => code != null ? '[$code] $message' : message;

  /// Message affichable à l'utilisateur (sans détail technique)
  String get userMessage => message;
}

/// Erreur réseau (timeout, pas de connexion, serveur injoignable)
class NetworkException extends AppException {
  const NetworkException(
    super.message, {
    super.code,
    super.originalError,
    super.stackTrace,
  });

  factory NetworkException.timeout({String? endpoint}) => NetworkException(
        'Le serveur ne répond pas${endpoint != null ? ' ($endpoint)' : ''}',
        code: 'NETWORK_TIMEOUT',
      );

  factory NetworkException.noConnection() => const NetworkException(
        'Pas de connexion internet',
        code: 'NO_CONNECTION',
      );

  factory NetworkException.serverError({int? statusCode, String? endpoint}) =>
      NetworkException(
        'Erreur serveur${statusCode != null ? ' ($statusCode)' : ''}',
        code: 'SERVER_ERROR',
      );
}

/// Erreur d'authentification (token expiré, identifiants invalides, etc.)
class AuthException extends AppException {
  const AuthException(
    super.message, {
    super.code,
    super.originalError,
    super.stackTrace,
  });

  factory AuthException.notLoggedIn() => const AuthException(
        'Non connecté',
        code: 'NOT_LOGGED_IN',
      );

  factory AuthException.tokenExpired() => const AuthException(
        'Session expirée, reconnecte-toi',
        code: 'TOKEN_EXPIRED',
      );
}

/// Erreur liée à l'état du jeu (état invalide, action impossible, etc.)
class GameStateException extends AppException {
  const GameStateException(
    super.message, {
    super.code,
    super.originalError,
    super.stackTrace,
  });

  factory GameStateException.invalidState(String detail) => GameStateException(
        'État de jeu invalide : $detail',
        code: 'INVALID_GAME_STATE',
      );

  factory GameStateException.deserializationFailed({
    dynamic originalError,
    StackTrace? stackTrace,
  }) =>
      GameStateException(
        'Impossible de lire l\'état du jeu reçu du serveur',
        code: 'DESERIALIZATION_FAILED',
        originalError: originalError,
        stackTrace: stackTrace,
      );
}

/// Erreur de stockage local (SharedPreferences, fichiers, etc.)
class StorageException extends AppException {
  const StorageException(
    super.message, {
    super.code,
    super.originalError,
    super.stackTrace,
  });

  factory StorageException.readFailed({
    String? key,
    dynamic originalError,
    StackTrace? stackTrace,
  }) =>
      StorageException(
        'Erreur de lecture des données${key != null ? ' ($key)' : ''}',
        code: 'STORAGE_READ_FAILED',
        originalError: originalError,
        stackTrace: stackTrace,
      );

  factory StorageException.writeFailed({
    String? key,
    dynamic originalError,
    StackTrace? stackTrace,
  }) =>
      StorageException(
        'Erreur de sauvegarde des données${key != null ? ' ($key)' : ''}',
        code: 'STORAGE_WRITE_FAILED',
        originalError: originalError,
        stackTrace: stackTrace,
      );
}
