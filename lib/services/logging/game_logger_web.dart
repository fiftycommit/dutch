// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

/// Implémentation web
/// Utilise le téléchargement de fichier du navigateur

/// Initialise un nouveau fichier de log (no-op sur web)
Future<void> initLogFile(String gameId, String initialContent) async {
  // Sur web, on stocke tout en mémoire dans GameLoggerService
  // Pas besoin d'initialiser un fichier
}

/// Ajoute du contenu au fichier de log (no-op sur web)
Future<void> appendToLogFile(String gameId, String content) async {
  // Sur web, on stocke tout en mémoire dans GameLoggerService
}

/// Télécharge le fichier de log via le navigateur
Future<void> downloadLog(String filename, String content) async {
  // Créer un blob avec le contenu
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/plain');

  // Créer une URL pour le blob
  final url = html.Url.createObjectUrlFromBlob(blob);

  // Créer un élément <a> pour déclencher le téléchargement
  final anchor = html.AnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';

  // Ajouter au DOM, cliquer, puis retirer
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  // Libérer l'URL
  html.Url.revokeObjectUrl(url);
}
