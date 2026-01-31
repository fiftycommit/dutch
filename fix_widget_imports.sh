#!/bin/bash

# Corriger les imports des widgets dans les screens
find lib/screens -name "*.dart" -print0 | while IFS= read -r -d '' file; do
  sed -i '' "s|'../../widgets/card_widget.dart'|'../../widgets/game/card_widget.dart'|g" "$file"
  sed -i '' "s|'../../widgets/player_hand.dart'|'../../widgets/game/player_hand.dart'|g" "$file"
  sed -i '' "s|'../../widgets/player_avatar.dart'|'../../widgets/game/player_avatar.dart'|g" "$file"
  sed -i '' "s|'../../widgets/responsive_dialog.dart'|'../../widgets/dialogs/responsive_dialog.dart'|g" "$file"
  sed -i '' "s|'../../widgets/game_action_button.dart'|'../../widgets/game/game_action_button.dart'|g" "$file"
  sed -i '' "s|'../../widgets/special_power_dialogs.dart'|'../../widgets/dialogs/special_power_dialogs.dart'|g" "$file"
  sed -i '' "s|'../../widgets/center_table.dart'|'../../widgets/game/center_table.dart'|g" "$file"
  sed -i '' "s|'../../../widgets/competitive_stats_widget.dart'|'../../../widgets/ui/competitive_stats_widget.dart'|g" "$file"
  sed -i '' "s|'../../../widgets/connection_error_dialog.dart'|'../../../widgets/dialogs/connection_error_dialog.dart'|g" "$file"
  sed -i '' "s|'../../../widgets/emote_overlay.dart'|'../../../widgets/dialogs/emote_overlay.dart'|g" "$file"
  sed -i '' "s|'../../../widgets/presence_check_overlay.dart'|'../../../widgets/dialogs/presence_check_overlay.dart'|g" "$file"
  sed -i '' "s|'../../../widgets/multiplayer_special_power_dialogs.dart'|'../../../widgets/dialogs/multiplayer_special_power_dialogs.dart'|g" "$file"
done

echo "✅ Imports corrigés"
