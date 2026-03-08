import '../../core/interfaces/i_haptic_service.dart';
import 'haptic_service_impl.dart';

/// Stub pour les plateformes non-web : retourne l'implémentation native
IHapticService createPlatformHapticService() => HapticServiceImpl();
