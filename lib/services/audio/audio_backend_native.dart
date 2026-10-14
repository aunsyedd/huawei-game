import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'audio_backend.dart';

AudioBackend createBackend() => NativeAudioBackend();

/// Android / desktop: effects through low-latency pools (SoundPool on
/// Android), music through one looping player whose commands are queued so
/// track switches can never overlap.
class NativeAudioBackend with WidgetsBindingObserver implements AudioBackend {
  NativeAudioBackend() {
    WidgetsBinding.instance.addObserver(this);
  }

  final AudioCache _cache = AudioCache(prefix: 'assets/audio/');
  final Map<String, AudioPool> _pools = {};
  final AudioPlayer _music = AudioPlayer();
  final _mixWithOthers = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  Future<void> _queue = Future.value();
  String? _wantMusic, _musicName;
  double _sfxVolume = 0.8, _musicVolume = 0.5;
  bool _paused = false;

  static const _voices = {'shot_pistol': 5, 'shot_rifle': 5, 'shot_launcher': 3, 'hit': 4, 'splash': 3, 'ui_click': 2};

  @override
  bool get unlocked => true;

  @override
  void unlock() {}

  @override
  Future<void> load(List<String> sfx, List<String> music) async {
    _music.audioCache = _cache;
    await _music.setAudioContext(_mixWithOthers);
    await _music.setReleaseMode(ReleaseMode.loop);
    for (final name in sfx) {
      try {
        _pools[name] = await AudioPool.create(
          source: AssetSource('$name.wav'),
          audioCache: _cache,
          maxPlayers: _voices[name] ?? 2,
          playerMode: PlayerMode.lowLatency,
          audioContext: _mixWithOthers,
        );
      } catch (e) {
        debugPrint('audio: could not load $name: $e');
      }
    }
    await _cache.loadAll([for (final m in music) '$m.wav']);
    _syncMusic();
  }

  @override
  void playSfx(String name, double volume) {
    final pool = _pools[name];
    if (pool == null || _paused) return;
    unawaited(pool.start(volume: (volume * _sfxVolume).clamp(0.0, 1.0)).then<void>((_) {}, onError: (Object _) {}));
  }

  @override
  void playMusic(String name) {
    _wantMusic = name;
    _syncMusic();
  }

  @override
  void stopMusic() {
    _wantMusic = null;
    _syncMusic();
  }

  /// Serialised so rapid screen changes can't start two tracks.
  void _syncMusic() {
    _queue = _queue.then((_) async {
      final want = _paused ? null : _wantMusic;
      if (want == _musicName) return;
      try {
        await _music.stop();
        _musicName = null;
        if (want != null && _musicVolume > 0.001) {
          await _music.setVolume(_musicVolume);
          await _music.setSource(AssetSource('$want.wav'));
          await _music.resume();
          _musicName = want;
        }
      } catch (e) {
        debugPrint('audio: music $e');
      }
    });
  }

  @override
  void setSfxVolume(double v) => _sfxVolume = v;

  @override
  void setMusicVolume(double v) {
    _musicVolume = v;
    if (_musicName != null) unawaited(_music.setVolume(v).then<void>((_) {}, onError: (Object _) {}));
    if (v <= 0.001 || _musicName == null) _syncMusic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state != AppLifecycleState.resumed;
    if (paused == _paused) return;
    _paused = paused;
    if (paused) {
      _musicName = null;
      _queue = _queue.then((_) => _music.pause().then<void>((_) {}, onError: (Object _) {}));
    } else {
      _syncMusic();
    }
  }
}
