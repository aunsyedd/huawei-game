import 'audio_backend_native.dart' if (dart.library.js_interop) 'audio_backend_web.dart' as impl;

/// Platform audio engine. Web uses the Web Audio API (sample-accurate, gapless
/// loops, ~10 ms latency); Android uses SoundPool via audioplayers' low-latency
/// mode for effects and a single serialised player for music.
abstract class AudioBackend {
  /// Loads `assets/audio/<name>.wav` for each name.
  Future<void> load(List<String> sfx, List<String> music);

  void playSfx(String name, double volume);

  /// Starts a looping track (cross-fading from the current one). Same track: no-op.
  void playMusic(String name);
  void stopMusic();

  void setSfxVolume(double v);
  void setMusicVolume(double v);

  /// Must be called from a user gesture on web (browser autoplay policy).
  void unlock();
  bool get unlocked;
}

AudioBackend createAudioBackend() => impl.createBackend();
