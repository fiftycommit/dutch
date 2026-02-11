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
Future<bool> downloadLog(String filename, String content) async {
  // Créer un blob avec le contenu
  final bytes = utf8.encode(content);
  final uint8List = Uint8List.fromList(bytes);
  final jsArray = uint8List.toJS;
  final blob = web.Blob(
    [jsArray].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final file = web.File(
    [blob].toJS,
    filename,
    web.FilePropertyBag(type: 'text/plain;charset=utf-8'),
  );

  // 1) Priorité mobile/PWA: partage natif (évite la navigation vers un aperçu)
  if (await _tryShareFile(file, filename)) return true;

  // 2) Fallback iOS: partager le texte si le partage de fichier n'est pas disponible
  if (_isLikelyIos() && await _tryShareText(filename, content)) return true;

  // 3) Fallback iOS ultime: copier dans le presse-papiers
  if (_isLikelyIos() && await _copyToClipboard(content)) return true;

  // 4) Fallback desktop/Android: téléchargement via <a download>
  _triggerAnchorDownload(filename, blob);
  return true;
}

Future<bool> _tryShareFile(web.File file, String filename) async {
  try {
    final shareData = web.ShareData(
      files: [file].toJS,
      title: filename,
      text: 'Log de partie Dutch',
    );
    final navigator = web.window.navigator;
    if (!navigator.canShare(shareData)) return false;

    // Si l'utilisateur annule, on considère l'action gérée (pas de fallback agressif).
    try {
      await navigator.share(shareData).toDart;
    } catch (_) {}
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _tryShareText(String filename, String content) async {
  try {
    final shareData = web.ShareData(
      title: filename,
      text: content,
    );
    final navigator = web.window.navigator;
    if (!navigator.canShare(shareData)) return false;

    try {
      await navigator.share(shareData).toDart;
    } catch (_) {}
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _copyToClipboard(String content) async {
  try {
    await web.window.navigator.clipboard.writeText(content).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

bool _isLikelyIos() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
}

void _triggerAnchorDownload(String filename, web.Blob blob) {
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.target = '_blank';
  anchor.rel = 'noopener';
  anchor.style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  // Safari peut démarrer la navigation/téléchargement plus tard.
  Future<void>.delayed(const Duration(seconds: 30), () {
    try {
      web.URL.revokeObjectURL(url);
    } catch (_) {}
  });
}
