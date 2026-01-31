import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum SoundType {
  cardFlip,
  cardDraw,
  cardDiscard,
  cardPlace,
  buttonTap,
  dutch,
  powerActivate,
  win,
  lose,
  error,
}

class SoundService {
  static bool _isEnabled = true;
  static final Map<String, AudioPlayer> _players = {};
  static final Set<String> _initializedAssets = {};

  static const String _uiClickAsset = 'sounds/ui_click.wav';
  static const String _cardDrawAsset = 'sounds/card_draw.wav';
  static const String _winAsset = 'sounds/win.wav';

  static const Map<SoundType, String> _soundAssets = {
    SoundType.cardFlip: _uiClickAsset,
    SoundType.cardDraw: _cardDrawAsset,
    SoundType.cardDiscard: _uiClickAsset,
    SoundType.cardPlace: _uiClickAsset,
    SoundType.buttonTap: _uiClickAsset,
    SoundType.dutch: _uiClickAsset,
    SoundType.powerActivate: _uiClickAsset,
    SoundType.win: _winAsset,
    SoundType.lose: _uiClickAsset,
    SoundType.error: _uiClickAsset,
  };

  static const Map<SoundType, double> _soundVolumes = {
    SoundType.cardDraw: 0.6,
    SoundType.win: 0.9,
    SoundType.buttonTap: 0.4,
  };

  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  static bool get isEnabled => _isEnabled;

  static Future<void> play(SoundType sound) async {
    if (!_isEnabled) return;

    try {
      final asset = _soundAssets[sound] ?? _uiClickAsset;
      final volume = _soundVolumes[sound] ?? 0.5;
      final player = await _playerFor(asset);
      await player.play(AssetSource(asset), volume: volume);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SoundService error: $e');
      }
    }
  }

  static Future<AudioPlayer> _playerFor(String asset) async {
    final player = _players.putIfAbsent(asset, () => AudioPlayer());
    if (!_initializedAssets.contains(asset)) {
      await player.setReleaseMode(ReleaseMode.stop);
      _initializedAssets.add(asset);
    }
    return player;
  }

  static Future<void> cardFlip() => play(SoundType.cardFlip);
  static Future<void> cardDraw() => play(SoundType.cardDraw);
  static Future<void> cardDiscard() => play(SoundType.cardDiscard);
  static Future<void> cardPlace() => play(SoundType.cardPlace);
  static Future<void> buttonTap() => play(SoundType.buttonTap);
  static Future<void> dutch() => play(SoundType.dutch);
  static Future<void> powerActivate() => play(SoundType.powerActivate);
  static Future<void> win() => play(SoundType.win);
  static Future<void> lose() => play(SoundType.lose);
  static Future<void> error() => play(SoundType.error);
}
