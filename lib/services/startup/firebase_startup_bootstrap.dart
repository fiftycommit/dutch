import 'dart:async';

/// Rapporteur d'erreur découplé de `ErrorReportingService` pour rester testable.
typedef StartupErrorReporter = void Function(
  Object error,
  StackTrace stackTrace,
  String context,
);

/// Séquence de démarrage Firebase, bornée et injectable.
///
/// Chaque étape réseau a un timeout explicite : c'est ce qui empêche qu'un
/// réseau dégradé (sonde connectivité positive mais Firebase réellement
/// injoignable) fasse traîner le démarrage — régression du splash ~10 s.
///
/// La logique est isolée ici, sans dépendance directe à Firebase, pour pouvoir
/// vérifier en test que le temps total reste borné même si chaque appel pend.
class FirebaseStartupBootstrap {
  static const Duration defaultFirebaseTimeout = Duration(seconds: 3);
  static const Duration defaultAppCheckTimeout = Duration(seconds: 2);
  static const Duration defaultAuthPersistenceTimeout = Duration(seconds: 2);

  /// Plafond théorique du temps passé dans les étapes Firebase (hors sonde
  /// réseau, qui est bornée en amont par l'appelant). Sert de garde-fou de test.
  static Duration boundedStepsCap({
    Duration firebaseTimeout = defaultFirebaseTimeout,
    Duration appCheckTimeout = defaultAppCheckTimeout,
    Duration authPersistenceTimeout = defaultAuthPersistenceTimeout,
  }) {
    return firebaseTimeout + appCheckTimeout + authPersistenceTimeout;
  }

  /// Retourne `true` si Firebase est prêt.
  ///
  /// - [reachBackend] : sonde réseau déjà bornée par l'appelant.
  /// - [initializeApp] : bloquant (Firebase requis pour restaurer la session).
  ///   Son timeout échoué ⇒ mode dégradé (`false`), pas de blocage plus long.
  /// - [activateAppCheck] / [setAuthPersistence] : best-effort, une erreur ou un
  ///   timeout n'empêche pas le démarrage.
  static Future<bool> run({
    required Future<bool> Function() reachBackend,
    required Future<void> Function() initializeApp,
    required Future<void> Function() activateAppCheck,
    Future<void> Function()? setAuthPersistence,
    Duration firebaseTimeout = defaultFirebaseTimeout,
    Duration appCheckTimeout = defaultAppCheckTimeout,
    Duration authPersistenceTimeout = defaultAuthPersistenceTimeout,
    StartupErrorReporter? onError,
  }) async {
    final canReach = await reachBackend();
    if (!canReach) {
      return false;
    }

    try {
      await initializeApp().timeout(firebaseTimeout);
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace, 'Démarrage Firebase');
      return false;
    }

    try {
      await activateAppCheck().timeout(appCheckTimeout);
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace, 'Démarrage App Check');
    }

    if (setAuthPersistence != null) {
      try {
        await setAuthPersistence().timeout(authPersistenceTimeout);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace, 'Démarrage Auth persistence');
      }
    }

    return true;
  }
}
