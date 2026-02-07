import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Implémentation native (iOS, Android, macOS, Windows, Linux)
/// Utilise le système de fichiers local

Map<String, File> _logFiles = {};

/// Initialise un nouveau fichier de log
Future<void> initLogFile(String gameId, String initialContent) async {
  try {
    final directory = await _getLogDirectory();
    final file = File('${directory.path}/$gameId.log');
    await file.writeAsString(initialContent);
    _logFiles[gameId] = file;
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ initLogFile error: $e');
  }
}

/// Ajoute du contenu au fichier de log
Future<void> appendToLogFile(String gameId, String content) async {
  try {
    final file = _logFiles[gameId];
    if (file != null) {
      await file.writeAsString(content, mode: FileMode.append);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ appendToLogFile error: $e');
  }
}

/// Télécharge/ouvre le fichier de log
Future<void> downloadLog(String filename, String content) async {
  try {
    final directory = await _getLogDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsString(content);
    // Sur native, le fichier est déjà sauvegardé
    // On pourrait ouvrir le dossier ici si nécessaire
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ downloadLog error: $e');
  }
}

/// Retourne le dossier de logs
Future<Directory> _getLogDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final logDir = Directory('${appDir.path}/dutch_logs');

  if (!await logDir.exists()) {
    await logDir.create(recursive: true);
  }

  return logDir;
}
