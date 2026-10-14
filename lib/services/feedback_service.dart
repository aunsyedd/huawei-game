import 'package:flutter/services.dart';

/// Sound + haptics. Sound is a stub until OGG files are added to assets/audio
/// (e.g. Kenney CC0 packs); haptics work now.
class FeedbackService {
  FeedbackService({this.hapticsEnabled = true, this.soundVolume = 0.8});

  bool hapticsEnabled;
  double soundVolume;
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

  // Sound hooks: wire to an audio player once assets/audio exists.
  void shot(String weaponId) {}
  void splash() {}
  void pickup() {}
}
