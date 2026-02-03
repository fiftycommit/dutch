import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:convert';
import 'dart:typed_data';

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
  final uint8List = Uint8List.fromList(bytes);
  final jsArray = uint8List.toJS;
  final blob = web.Blob([jsArray].toJS, web.BlobPropertyBag(type: 'text/plain'));

  // Créer une URL pour le blob
  final url = web.URL.createObjectURL(blob);

  // Créer un élément <a> pour déclencher le téléchargement
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';

  // Ajouter au DOM, cliquer, puis retirer
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  // Libérer l'URL
  web.URL.revokeObjectURL(url);
}
