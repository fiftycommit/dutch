import 'dart:io';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Implémentation native (iOS, Android, macOS, Windows, Linux)
/// Utilise le système de fichiers local + copie presse-papiers

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

/// Télécharge/partage le fichier de log + copie dans le presse-papiers
Future<bool> downloadLog(String filename, String content) async {
  try {
    // Toujours copier dans le presse-papiers
    await Clipboard.setData(ClipboardData(text: content));

    final directory = await _getLogDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsString(content);

    // Mobile: share sheet natif
    if (Platform.isIOS || Platform.isAndroid) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Log de partie Dutch',
          subject: 'Log de partie Dutch',
        ),
      );
      return true;
    }

    // macOS: fenêtre "Enregistrer sous..."
    if (Platform.isMacOS) {
      final saveLocation = await fs.getSaveLocation(
        suggestedName: filename,
        confirmButtonText: 'Enregistrer',
      );

      if (saveLocation == null) return false;

      final targetPath = saveLocation.path.toLowerCase().endsWith('.log')
          ? saveLocation.path
          : '${saveLocation.path}.log';
      await File(targetPath).writeAsString(content);
      return true;
    }

    // Autres desktop: fichier déjà sauvé localement
    return true;
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ downloadLog error: $e');
    rethrow;
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
