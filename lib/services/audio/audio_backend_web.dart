import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

import 'audio_backend.dart';

AudioBackend createBackend() => WebAudioBackend();

/// Web Audio: every sound is decoded once into memory and played from an
/// AudioBuffer, so effects start within a few ms and music loops are gapless.
class WebAudioBackend implements AudioBackend {
  web.AudioContext? _ctx;
  late web.GainNode _sfxBus, _musicBus;
  final Map<String, web.AudioBuffer> _buffers = {};

  web.AudioBufferSourceNode? _musicSrc;
  web.GainNode? _musicGain;
  String? _musicName;
  String? _wantMusic;
  int _active = 0;
  double _sfxVolume = 0.8, _musicVolume = 0.5;

  static const _fade = 0.35;
  static const _maxVoices = 24;

  web.AudioContext get _context {
    final existing = _ctx;
    if (existing != null) return existing;
    final c = web.AudioContext(web.AudioContextOptions(latencyHint: 'interactive'.toJS));
    _sfxBus = c.createGain()..connect(c.destination);
    _musicBus = c.createGain()..connect(c.destination);
    _sfxBus.gain.value = _sfxVolume;
    _musicBus.gain.value = _musicVolume;
    return _ctx = c;
  }

  @override
  bool get unlocked => _ctx?.state == 'running';

  @override
  Future<void> load(List<String> sfx, List<String> music) async {
    final ctx = _context;
    for (final name in [...sfx, ...music]) {
      try {
        final data = await rootBundle.load('assets/audio/$name.wav');
        final bytes = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        _buffers[name] = await ctx.decodeAudioData(bytes.buffer.toJS).toDart;
      } catch (e) {
        debugPrint('audio: could not load $name: $e');
      }
    }
    _startWantedMusic();
  }

  @override
  void unlock() {
    final ctx = _context;
    if (ctx.state == 'running') return;
    unawaited(ctx.resume().toDart.then((_) => _startWantedMusic(), onError: (Object _) {}));
  }

  @override
  void playSfx(String name, double volume) {
    final ctx = _ctx;
    final buf = _buffers[name];
    if (ctx == null || buf == null || ctx.state != 'running' || _active >= _maxVoices) return;
    final src = ctx.createBufferSource()..buffer = buf;
    final gain = ctx.createGain();
    gain.gain.value = volume;
    src.connect(gain);
    gain.connect(_sfxBus);
    _active++;
    src.onended = ((web.Event _) {
      _active--;
      gain.disconnect();
    }).toJS;
    src.start();
  }

  @override
  void playMusic(String name) {
    _wantMusic = name;
    _startWantedMusic();
  }

  void _startWantedMusic() {
    final ctx = _ctx;
    final name = _wantMusic;
    if (ctx == null || name == null || ctx.state != 'running' || name == _musicName) return;
    final buf = _buffers[name];
    if (buf == null) return;
    _fadeOutCurrent();
    final now = ctx.currentTime;
    final gain = ctx.createGain();
    gain.gain
      ..setValueAtTime(0, now)
      ..linearRampToValueAtTime(1, now + _fade);
    final src = ctx.createBufferSource()
      ..buffer = buf
      ..loop = true;
    src.connect(gain);
    gain.connect(_musicBus);
    src.start();
    _musicSrc = src;
    _musicGain = gain;
    _musicName = name;
  }

  void _fadeOutCurrent() {
    final ctx = _ctx, src = _musicSrc, gain = _musicGain;
    if (ctx == null || src == null || gain == null) return;
    final now = ctx.currentTime;
    gain.gain
      ..cancelScheduledValues(now)
      ..setValueAtTime(gain.gain.value, now)
      ..linearRampToValueAtTime(0, now + _fade);
    src.stop(now + _fade + 0.05);
    _musicSrc = null;
    _musicGain = null;
    _musicName = null;
  }

  @override
  void stopMusic() {
    _wantMusic = null;
    _fadeOutCurrent();
  }

  @override
  void setSfxVolume(double v) {
    _sfxVolume = v;
    if (_ctx != null) _sfxBus.gain.value = v;
  }

  @override
  void setMusicVolume(double v) {
    _musicVolume = v;
    if (_ctx != null) _musicBus.gain.value = v;
  }
}
