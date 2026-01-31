import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/ui/haptic_service.dart';

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

  group('HapticService', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Reset to enabled state
      HapticService.setEnabled(true);
    });

    group('enabled state', () {
      test('isEnabled returns true by default', () {
        HapticService.setEnabled(true);
        expect(HapticService.isEnabled, isTrue);
      });

      test('setEnabled changes state', () {
        HapticService.setEnabled(false);
        expect(HapticService.isEnabled, isFalse);

        HapticService.setEnabled(true);
        expect(HapticService.isEnabled, isTrue);
      });
    });

    group('trigger', () {
      test('does nothing when disabled', () async {
        HapticService.setEnabled(false);

        // Should complete without error
        await HapticService.trigger(HapticIntensity.light);
        await HapticService.trigger(HapticIntensity.medium);
        await HapticService.trigger(HapticIntensity.heavy);
        await HapticService.trigger(HapticIntensity.error);
        await HapticService.trigger(HapticIntensity.success);
      });

      test('handles all intensity levels', () async {
        for (final intensity in HapticIntensity.values) {
          // Should complete without throwing
          await HapticService.trigger(intensity);
        }
      });
    });

    group('convenience methods', () {
      test('cardTap completes without error', () async {
        await HapticService.cardTap();
      });

      test('buttonTap completes without error', () async {
        await HapticService.buttonTap();
      });

      test('importantAction completes without error', () async {
        await HapticService.importantAction();
      });

      test('error completes without error', () async {
        await HapticService.error();
      });

      test('success completes without error', () async {
        await HapticService.success();
      });

      test('convenience methods respect enabled state', () async {
        HapticService.setEnabled(false);

        // All should complete without calling HapticFeedback
        await HapticService.cardTap();
        await HapticService.buttonTap();
        await HapticService.importantAction();
        await HapticService.error();
        await HapticService.success();
      });
    });
  });
}
