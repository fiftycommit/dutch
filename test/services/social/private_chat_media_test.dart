import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:dutch_game/services/social/private_chat_service.dart';

/// UploadTask qui ne se résout JAMAIS : simule un upload média qui pend sur
/// réseau dégradé. Seuls `timeout`, `cancel` et `snapshotEvents` sont utilisés
/// par le service ; le reste passe par noSuchMethod.
class _NeverUploadTask implements UploadTask {
  final Completer<TaskSnapshot> _never = Completer<TaskSnapshot>();
  bool canceled = false;

  @override
  Stream<TaskSnapshot> get snapshotEvents => const Stream.empty();

  @override
  Future<bool> cancel() async {
    canceled = true;
    return true;
  }

  @override
  Future<TaskSnapshot> timeout(Duration timeLimit,
          {FutureOr<TaskSnapshot> Function()? onTimeout}) =>
      _never.future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeRef implements Reference {
  final _NeverUploadTask task;
  _FakeRef(this.task);

  @override
  Reference child(String path) => this;

  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) => task;

  @override
  UploadTask putFile(dynamic file, [SettableMetadata? metadata]) => task;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeStorage implements FirebaseStorage {
  final _NeverUploadTask task;
  _FakeStorage(this.task);

  @override
  Reference ref([String? path]) => _FakeRef(task);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  test('upload média sans réponse ⇒ MediaUploadException dans le plafond, '
      'tâche annulée (pas de pendaison)', () async {
    final task = _NeverUploadTask();
    final service = PrivateChatService(
      storage: _FakeStorage(task),
      mediaUploadTimeout: const Duration(milliseconds: 200),
    );

    final sw = Stopwatch()..start();
    await expectLater(
      () => service.sendImageBytes('chat1', 'user1', const [1, 2, 3]),
      throwsA(isA<MediaUploadException>()),
    );
    sw.stop();

    // Le plafond a bien coupé (bien avant un hang), et la tâche a été annulée
    // pour ne pas continuer en arrière-plan.
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
        reason: 'l\'envoi doit échouer dans le plafond, pas pendre');
    expect(task.canceled, isTrue,
        reason: 'la tâche d\'upload doit être annulée au timeout');
  });
}
