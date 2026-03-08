import '../service_locator.dart';
import '../interfaces/i_haptic_service.dart';
import '../interfaces/i_stats_service.dart';
import '../../services/ui/haptic_service_web_stub.dart'
    if (dart.library.js_interop) '../../services/ui/haptic_service_web.dart';
import '../../services/ui/stats_service_impl.dart';

/// Enregistrement des services UI (haptics, stats, etc.)
/// Ces services peuvent dépendre de Flutter platform channels
/// L'import conditionnel sélectionne HapticServiceWeb sur le web
/// et HapticServiceImpl sur les plateformes natives
void registerUIServices(ServiceLocator locator) {
  // Service de feedback haptique (natif ou web selon la plateforme)
  final hapticService = createPlatformHapticService();
  locator.register<IHapticService>(hapticService);

  // Service de statistiques
  final statsService = StatsServiceImpl();
  locator.register<IStatsService>(statsService);
}
