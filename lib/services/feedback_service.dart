import 'package:flutter/services.dart';

import 'audio_service.dart';

/// Sound effects + haptics for in-match events.
class FeedbackService {
  FeedbackService({this.hapticsEnabled = true, AudioService? audio}) : audio = audio ?? SilentAudioService();

  bool hapticsEnabled;
  final AudioService audio;
  double _lastHaptic = -1;

  void _haptic(double now, Future<void> Function() fn) {
    if (!hapticsEnabled || now - _lastHaptic < 0.08) return;
    _lastHaptic = now;
    fn();
  }

  void playerHit(double now) => _haptic(now, HapticFeedback.lightImpact);
  void tagOut(double now) => _haptic(now, HapticFeedback.mediumImpact);
  void playerTaggedOut(double now) => _haptic(now, HapticFeedback.heavyImpact);
  void treePlanted(double now) => _haptic(now, HapticFeedback.selectionClick);

  /// Plays a sound effect from assets/audio (see tool/gen_audio.py).
  void play(String name, {double volume = 1}) => audio.sfx(name, volume: volume);
}
