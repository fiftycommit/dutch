import '../service_locator.dart';
import '../interfaces/i_learning_service.dart';
import '../interfaces/i_tracking_service.dart';
import '../interfaces/i_validation_service.dart';
import '../interfaces/i_bot_ai_service.dart';
import '../../services/learning/bot_learning_service.dart';
import '../../services/learning/player_learning_service.dart';
import '../../services/learning/game_tracking_service.dart';
import '../../services/game/game_state_validator.dart';
import '../../services/game/bot/bot_ai_service_impl.dart';
import '../../providers/game_tracking_provider.dart';

/// Enregistrement des services de jeu (logique métier pure)
/// Ces services ne dépendent pas de Flutter UI
void registerGameServices(ServiceLocator locator) {
  // Services d'apprentissage
  final botLearningService = BotLearningService();
  final playerLearningService = PlayerLearningService();

  locator.register<ILearningService>(botLearningService);
  locator.register<IPlayerLearningService>(playerLearningService);

  // Service de tracking (dépend de ILearningService)
  final trackingService = GameTrackingService(botLearningService);
  locator.register<ITrackingService>(trackingService);

  // Service de validation
  final validationService = GameStateValidator();
  locator.register<IValidationService>(validationService);

  // Service d'IA des bots
  final botAIService = BotAIServiceImpl();
  locator.register<IBotAIService>(botAIService);

  // Provider de tracking (dépend des services d'apprentissage)
  final trackingProvider = GameTrackingProvider(
    botLearningService: botLearningService,
    playerLearningService: playerLearningService,
  );
  locator.register<GameTrackingProvider>(trackingProvider);
}
