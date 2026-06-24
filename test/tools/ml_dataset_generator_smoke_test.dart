// Wrapper de run de fumée pour le générateur de dataset ML.
//
// Pourquoi un test et pas `dart run` : le SDK Dart 3.12.2 installé a un bug du
// transformer FFI qui fait crasher `dart run` sur tout script important
// package:flutter (cf. bot_ladder_cli qui crashe à l'identique). La chaîne de
// compilation de `flutter test` n'est pas affectée. Ce wrapper se contente
// d'invoquer le `main()` du générateur deux fois (même seed) pour produire deux
// datasets ; les 3 vérifications (déterminisme byte-identique, actions[] non
// vides, traces de pouvoirs) sont faites ensuite en shell sur les fichiers.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ml_dataset_generator.dart' as gen;

void main() {
  test('génère 2 datasets de fumée (seed=1, 5 parties) pour vérif déterminisme',
      () async {
    await gen.main(['--games=5', '--seed=1', '--out=ml/data/raw/_smoke1']);
    await gen.main(['--games=5', '--seed=1', '--out=ml/data/raw/_smoke2']);

    // Garde-fou minimal : les deux dossiers existent et contiennent des records.
    final d1 = Directory('ml/data/raw/_smoke1');
    final d2 = Directory('ml/data/raw/_smoke2');
    expect(d1.existsSync(), isTrue);
    expect(d2.existsSync(), isTrue);
    expect(d1.listSync().whereType<File>().isNotEmpty, isTrue);
    expect(d2.listSync().whereType<File>().isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
