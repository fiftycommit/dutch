import 'dart:io';

/// Implémentation headless (dart run):
/// écrit les logs dans le dossier temporaire local sans dépendance Flutter.
final Map<String, File> _logFiles = {};

Future<void> initLogFile(String gameId, String initialContent) async {
  try {
    final file = File('${Directory.systemTemp.path}/$gameId.log');
    await file.writeAsString(initialContent);
    _logFiles[gameId] = file;
  } catch (_) {
    // best-effort logging
  }
}

Future<void> appendToLogFile(String gameId, String content) async {
  try {
    final file = _logFiles[gameId];
    if (file != null) {
      await file.writeAsString(content, mode: FileMode.append);
    }
  } catch (_) {
    // best-effort logging
  }
}

Future<bool> downloadLog(String filename, String content) async {
  try {
    final file = File('${Directory.systemTemp.path}/$filename');
    await file.writeAsString(content);
    return true;
  } catch (_) {
    // best-effort logging
    return false;
  }
}
