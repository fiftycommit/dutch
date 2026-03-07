import 'package:flutter/foundation.dart';
import '../../core/exceptions.dart';

/// Niveaux de sévérité pour le reporting d'erreurs
enum ErrorSeverity { debug, info, warning, error, fatal }

/// Service centralisé de reporting d'erreurs
/// Principe SOLID: SRP — un seul point d'entrée pour toutes les erreurs
///
/// En mode debug : affiche dans la console avec contexte complet.
/// En mode release : stocke en mémoire (prêt pour intégration Sentry/Crashlytics).
class ErrorReportingService {
  static final ErrorReportingService _instance =
      ErrorReportingService._internal();
  factory ErrorReportingService() => _instance;
  ErrorReportingService._internal();

  /// Buffer circulaire des dernières erreurs (pour diagnostic en release)
  static const int _maxBufferSize = 100;
  final List<ErrorReport> _recentErrors = [];

  /// Callback optionnel pour intégration externe (Sentry, Crashlytics, etc.)
  void Function(ErrorReport report)? onError;

  /// Accès aux erreurs récentes (utile pour écran de debug ou envoi différé)
  List<ErrorReport> get recentErrors => List.unmodifiable(_recentErrors);

  /// Signaler une erreur avec contexte
  void report(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
    ErrorSeverity severity = ErrorSeverity.error,
    Map<String, dynamic>? extras,
  }) {
    final report = ErrorReport(
      error: error,
      stackTrace: stackTrace ?? StackTrace.current,
      context: context,
      severity: severity,
      timestamp: DateTime.now(),
      extras: extras,
    );

    // Buffer circulaire
    _recentErrors.add(report);
    if (_recentErrors.length > _maxBufferSize) {
      _recentErrors.removeAt(0);
    }

    // Log en debug
    if (kDebugMode) {
      _logToConsole(report);
    }

    // Callback externe (Sentry, Crashlytics, etc.)
    onError?.call(report);
  }

  /// Raccourci pour les erreurs réseau
  void reportNetwork(
    dynamic error, {
    StackTrace? stackTrace,
    String? endpoint,
  }) {
    report(
      error,
      stackTrace: stackTrace,
      context: 'Réseau${endpoint != null ? ' — $endpoint' : ''}',
      severity: ErrorSeverity.warning,
      extras: endpoint != null ? {'endpoint': endpoint} : null,
    );
  }

  /// Raccourci pour les erreurs de désérialisation
  void reportDeserialization(
    dynamic error, {
    StackTrace? stackTrace,
    String? type,
  }) {
    report(
      error,
      stackTrace: stackTrace,
      context: 'Désérialisation${type != null ? ' de $type' : ''}',
      severity: ErrorSeverity.error,
      extras: type != null ? {'type': type} : null,
    );
  }

  /// Raccourci pour les erreurs de stockage
  void reportStorage(
    dynamic error, {
    StackTrace? stackTrace,
    String? operation,
    String? key,
  }) {
    report(
      error,
      stackTrace: stackTrace,
      context: 'Stockage${operation != null ? ' — $operation' : ''}',
      severity: ErrorSeverity.warning,
      extras: {
        if (operation != null) 'operation': operation,
        if (key != null) 'key': key,
      },
    );
  }

  /// Capturer une erreur Flutter (pour FlutterError.onError)
  void reportFlutterError(FlutterErrorDetails details) {
    report(
      details.exception,
      stackTrace: details.stack,
      context: 'Flutter — ${details.library ?? 'unknown'}',
      severity: ErrorSeverity.error,
      extras: {
        'library': details.library ?? 'unknown',
        if (details.context != null) 'errorContext': details.context.toString(),
      },
    );
  }

  /// Capturer une erreur de zone (pour runZonedGuarded)
  void reportZoneError(Object error, StackTrace stackTrace) {
    report(
      error,
      stackTrace: stackTrace,
      context: 'Zone non capturée',
      severity: ErrorSeverity.fatal,
    );
  }

  /// Vider le buffer
  void clear() => _recentErrors.clear();

  void _logToConsole(ErrorReport report) {
    final severity = report.severity.name.toUpperCase();
    final ctx = report.context != null ? ' [${report.context}]' : '';
    debugPrint('[$severity]$ctx ${report.error}');
    if (report.severity.index >= ErrorSeverity.error.index &&
        report.stackTrace != null) {
      debugPrint('${report.stackTrace}');
    }
  }
}

/// Représentation d'une erreur signalée
class ErrorReport {
  final dynamic error;
  final StackTrace? stackTrace;
  final String? context;
  final ErrorSeverity severity;
  final DateTime timestamp;
  final Map<String, dynamic>? extras;

  const ErrorReport({
    required this.error,
    this.stackTrace,
    this.context,
    required this.severity,
    required this.timestamp,
    this.extras,
  });

  /// True si l'erreur est une AppException typée
  bool get isTyped => error is AppException;

  /// Code d'erreur si disponible
  String? get errorCode =>
      error is AppException ? (error as AppException).code : null;

  @override
  String toString() {
    final severity = this.severity.name.toUpperCase();
    final ctx = context != null ? ' [$context]' : '';
    return '[$severity]$ctx $error (${timestamp.toIso8601String()})';
  }
}
