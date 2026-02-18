import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:convert';
import 'dart:typed_data';

/// Implémentation web
/// Utilise le téléchargement de fichier du navigateur

/// Initialise un nouveau fichier de log (no-op sur web)
Future<void> initLogFile(String gameId, String initialContent) async {}

/// Ajoute du contenu au fichier de log (no-op sur web)
Future<void> appendToLogFile(String gameId, String content) async {}

/// Télécharge le fichier de log via le navigateur + copie dans le presse-papiers
Future<bool> downloadLog(String filename, String content) async {
  // Toujours copier dans le presse-papiers
  await _copyToClipboard(content);

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

  // Mobile/PWA: partage natif (uniquement sur mobile, pas desktop)
  if (_isMobile()) {
    if (await _tryShareFile(file, filename)) return true;
  }

  // Desktop + fallback: téléchargement via <a download>
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

    try {
      await navigator.share(shareData).toDart;
    } catch (_) {}
    return true;
  } catch (_) {
    return false;
  }
}

bool _isMobile() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') || ua.contains('ipad') || ua.contains('android');
}

Future<void> _copyToClipboard(String content) async {
  try {
    await web.window.navigator.clipboard.writeText(content).toDart;
  } catch (_) {}
}

void _triggerAnchorDownload(String filename, web.Blob blob) {
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  Future<void>.delayed(const Duration(seconds: 30), () {
    try {
      web.URL.revokeObjectURL(url);
    } catch (_) {}
  });
}
