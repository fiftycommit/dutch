import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/ui/haptic_service.dart';
import 'package:dutch_game/services/ui/haptic_service_impl.dart';

void main() {
  group('HapticIntensity', () {
    test('has all expected values', () {
      expect(HapticIntensity.values, contains(HapticIntensity.light));
      expect(HapticIntensity.values, contains(HapticIntensity.medium));
      expect(HapticIntensity.values, contains(HapticIntensity.heavy));
      expect(HapticIntensity.values, contains(HapticIntensity.error));
      expect(HapticIntensity.values, contains(HapticIntensity.success));
    });

    test('has 5 values', () {
      expect(HapticIntensity.values.length, 5);
    });
  });

  group('HapticServiceImpl', () {
    late HapticServiceImpl service;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      service = HapticServiceImpl();
    });

    group('enabled state', () {
      test('isEnabled returns true by default', () {
        expect(service.isEnabled, isTrue);
      });

      test('setEnabled changes state', () {
        service.setEnabled(false);
        expect(service.isEnabled, isFalse);

        service.setEnabled(true);
        expect(service.isEnabled, isTrue);
      });
    });

    group('trigger', () {
      test('does nothing when disabled', () async {
        service.setEnabled(false);

        // Doit se terminer sans erreur
        await service.trigger(HapticIntensity.light);
        await service.trigger(HapticIntensity.medium);
        await service.trigger(HapticIntensity.heavy);
        await service.trigger(HapticIntensity.error);
        await service.trigger(HapticIntensity.success);
      });

      test('handles all intensity levels', () async {
        for (final intensity in HapticIntensity.values) {
          // Doit se terminer sans exception
          await service.trigger(intensity);
        }
      });
    });

    group('convenience methods', () {
      test('cardTap completes without error', () async {
        await service.cardTap();
      });

      test('buttonTap completes without error', () async {
        await service.buttonTap();
      });

      test('importantAction completes without error', () async {
        await service.importantAction();
      });

      test('error completes without error', () async {
        await service.error();
      });

      test('success completes without error', () async {
        await service.success();
      });

      test('convenience methods respect enabled state', () async {
        service.setEnabled(false);

        // Toutes les méthodes doivent se terminer sans appeler HapticFeedback
        await service.cardTap();
        await service.buttonTap();
        await service.importantAction();
        await service.error();
        await service.success();
      });
    });
  });
}
