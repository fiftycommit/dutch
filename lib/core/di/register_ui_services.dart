import '../service_locator.dart';
import '../interfaces/i_haptic_service.dart';
import '../interfaces/i_stats_service.dart';
import '../../services/ui/haptic_service_impl.dart';
import '../../services/ui/stats_service_impl.dart';

/// Enregistrement des services UI (haptics, stats, etc.)
/// Ces services peuvent dépendre de Flutter platform channels
void registerUIServices(ServiceLocator locator) {
  // Service de feedback haptique
  final hapticService = HapticServiceImpl();
  locator.register<IHapticService>(hapticService);

  // Service de statistiques
  final statsService = StatsServiceImpl();
  locator.register<IStatsService>(statsService);
}
