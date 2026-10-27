import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../data/game_config.dart';
import '../services/feedback_service.dart';
import 'components/actor.dart';
import 'components/loot.dart';
import 'components/tree.dart';
import 'render/camera3d.dart';
import 'render/fx.dart';
import 'render/perspective_renderer.dart';
import 'systems/match_manager.dart';

/// Flame game: owns the [MatchSimulation], feeds it input from the Flutter
/// overlays, and draws everything with a hand-rolled camera.
class HazeRoyaleGame extends Game with MatchListener {
  HazeRoyaleGame({
    required this.config,
    required this.lang,
    required this.feedback,
    this.aimSensitivity = 1,
    this.playerSkin = 0,
    this.graphics = 3,
    this.cameraFollow = true,
    double cameraTilt = Camera3D.defaultTilt,
    String playerName = 'You',
    GameMode mode = GameMode.royale,
    int? seed,
  }) : sim = MatchSimulation(config, seed: seed, playerName: playerName, mode: mode),
       quality = graphics.clamp(0, 3),
       camTilt = cameraTilt.clamp(Camera3D.minTilt, Camera3D.maxTilt),
       camTiltSetting = cameraTilt.clamp(Camera3D.minTilt, Camera3D.maxTilt),
       _tiltGoal = cameraTilt.clamp(Camera3D.minTilt, Camera3D.maxTilt) {
    sim.listener = this;
    camX = sim.map.width / 2;
    camY = sim.map.height / 2;
    final rng = math.Random(7);
    for (var i = 0; i < 40; i++) {
      particles.add(HazeParticle(rng));
    }
    _stepTimers = List.filled(sim.actors.length, 0);
    lastShot = List.filled(sim.actors.length, -9);
  }

  final GameConfig config;
  final String lang;
  final FeedbackService feedback;
  final MatchSimulation sim;
  double aimSensitivity;

  /// Graphics preset picked in settings: 3 = ultra ... 0 = minimal.
  final int graphics;

  /// Whether the camera swings behind the player as they move.
  bool cameraFollow;

  GameMode get mode => sim.mode;

  /// Index into progression.json skins (the player's chosen colour).
  final int playerSkin;

  // ---- Input written by the Flutter overlays ----
  final Vector2 moveInput = Vector2.zero();
  final Vector2 aimInput = Vector2.zero();
  bool fireHeld = false;

  /// Building: hold to mine, and whether the HUD shows the targeting box.
  bool mineHeld = false;
  bool buildMode = false;
  bool showBlockTarget = true;

  // ---- Notifications to the HUD ----
  final ValueNotifier<int> hudTick = ValueNotifier(0);
  final ValueNotifier<MatchPhase> phase = ValueNotifier(MatchPhase.dropping);
  void Function(PlayerResult result)? onPlayerFinishedCallback;
  double fps = 60;
  double hurtTimer = 0;

  // ---- Camera ----
  double viewW = 0, viewH = 0, zoom = 1, camX = 0, camY = 0;

  /// Heading (0 = looking north) and tilt from straight down. Both ease
  /// towards their goals so turning the camera never snaps.
  double camYaw = 0, camTilt = Camera3D.defaultTilt;
  double _yawGoal = 0, _tiltGoal = Camera3D.defaultTilt;

  /// The tilt chosen in settings; manual tilting starts from it.
  double camTiltSetting = Camera3D.defaultTilt;

  /// While positive, the player's own camera drag wins over follow.
  double _manualCam = 0;

  /// 0..1 over a day; 0.5 is noon.
  double timeOfDay = 0.40;

  double _shake = 0, _shakeTime = 0;
  final _rng = math.Random();
  double _hudAccum = 0;

  /// Wall-clock time, for animations that run even before the match starts.
  double clock = 0;

  final Map<int, Picture> _chunks = {};
  static const double _chunkSize = 500;

  /// Chunks baked into textures (LRU), so the detailed ground costs one image
  /// draw per chunk per frame instead of replaying thousands of shapes.
  final Map<int, Image> _chunkImages = {};
  final List<int> _chunkLru = [];
  static const int _maxChunkImages = 36; // the whole island
  static const double _chunkPad = 4;
  final Paint _chunkPaint = Paint()..filterQuality = FilterQuality.medium;
  int _bakedThisFrame = 0;
  final List<HazeParticle> particles = [];
  final FxSystem fx = FxSystem();
  late final List<double> _stepTimers;

  bool _wasShrinking = false;

  /// 3 = ultra (voxel texture detail, cast shadows, sea glitter), 2 = high,
  /// 1 = reduced, 0 = minimal. Drops automatically when the device cannot keep
  /// up (never goes back up within a match, to avoid flicker).
  int quality;
  double _slowTime = 0;

  /// Last time each actor fired (muzzle flash).
  late final List<double> lastShot;
  late final PerspectiveRenderer renderer = PerspectiveRenderer(this);

  @override
  Color backgroundColor() => const Color(0xFF237BAE);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    viewW = size.x;
    viewH = size.y;
    zoom = math.min(viewW / 1100, viewH / 620).clamp(0.45, 2.0);
    renderer.onResize();
  }

  void startMatch(double x, double y) {
    sim.start(x, y);
    final p = sim.player.pos;
    camX = p.x;
    camY = p.y;
    phase.value = MatchPhase.running;
  }

  // ------------------------------------------------------------------ blocks

  /// Puts the selected block down in front of the player.
  bool placeBlock() {
    final ok = sim.placeBlock(sim.player);
    if (!ok) feedback.play('ui_click', volume: 0.25);
    return ok;
  }

  void selectBlock(int type) {
    sim.player.selected = type;
    feedback.play('ui_click', volume: 0.4);
  }

  /// Cycles through the blocks the player is carrying (keyboard).
  void cycleBlock(int delta) {
    final bar = sim.hotbar(sim.player);
    if (bar.isEmpty) return;
    final i = bar.indexOf(sim.player.selected);
    selectBlock(bar[(i + delta + bar.length) % bar.length]);
  }

  bool craft(int recipeIndex) {
    final ok = sim.craft(sim.player, recipeIndex);
    feedback.play(ok ? 'pickup' : 'ui_click', volume: ok ? 0.8 : 0.25);
    return ok;
  }

  // ------------------------------------------------------------------ update

  @override
  void update(double dt) {
    if (dt <= 0) return;
    fps = fps * 0.95 + (1 / dt) * 0.05;
    _adaptQuality(dt);
    dt = math.min(dt, 0.05);
    clock += dt;

    final p = sim.player;
    if (p.alive && p.brain == null && sim.phase == MatchPhase.running) {
      // Sticks are read relative to where the camera looks, so turning the
      // camera never inverts the controls.
      final cs = math.cos(camYaw), sn = math.sin(camYaw);
      p.moveInput.setValues(moveInput.x * cs - moveInput.y * sn, moveInput.x * sn + moveInput.y * cs);
      if (aimInput.length2 > 0.0025) {
        p.aimAngle = math.atan2(aimInput.x * sn + aimInput.y * cs, aimInput.x * cs - aimInput.y * sn);
      } else if (moveInput.length2 > 0.01) {
        p.aimAngle = math.atan2(p.moveInput.y, p.moveInput.x);
      }
      p.wantFire = fireHeld && !buildMode;
      p.wantMine = mineHeld;
    }
    sim.update(dt);
    if (sim.phase == MatchPhase.ended) sim.effects.update(dt);
    if (phase.value != sim.phase) phase.value = sim.phase;

    final f = sim.focus.pos;
    if (sim.phase != MatchPhase.dropping) {
      final k = math.min(1.0, dt * 8);
      camX += (f.x - camX) * k;
      camY += (f.y - camY) * k;
    }
    _updateCamera(dt);
    _updateSky(dt);
    if (_shakeTime > 0) _shakeTime -= dt;
    if (hurtTimer > 0) hurtTimer -= dt;

    final shrinking = sim.zone.shrinking;
    if (shrinking && !_wasShrinking && sim.phase == MatchPhase.running) feedback.play('haze_warning', volume: 0.8);
    _wasShrinking = shrinking;

    if (quality >= 2) _footsteps(dt);
    if (sim.phase == MatchPhase.dropping) _prebakeNextChunk();
    fx.update(dt);
    _updateParticles(dt);

    _hudAccum += dt;
    if (_hudAccum > 1 / 12) {
      _hudAccum = 0;
      hudTick.value++;
    }
  }

  bool _nearCamera(double x, double y) => (x - camX).abs() < 1100 && (y - camY).abs() < 900;

  // ------------------------------------------------------------------ camera

  /// Drag on the look pad: [dx] turns, [dy] tilts, both in screen pixels.
  void orbitCamera(double dx, double dy) {
    _manualCam = 5;
    _yawGoal += dx * 0.006;
    _tiltGoal = (_tiltGoal + dy * 0.004).clamp(Camera3D.minTilt, Camera3D.maxTilt);
  }

  /// Snaps the camera back behind the player (double tap on the look pad).
  void recentreCamera() {
    _manualCam = 0;
    final v = sim.focus.vel;
    _yawGoal = v.length2 > 100 ? math.atan2(v.x, -v.y) : 0;
    _tiltGoal = camTiltSetting;
  }

  static double _wrap(double a) {
    while (a > math.pi) {
      a -= math.pi * 2;
    }
    while (a < -math.pi) {
      a += math.pi * 2;
    }
    return a;
  }

  void _updateCamera(double dt) {
    if (_manualCam > 0) {
      _manualCam -= dt;
    } else if (cameraFollow) {
      final v = sim.focus.vel;
      if (v.length2 > 2500) _yawGoal = math.atan2(v.x, -v.y);
    } else {
      _yawGoal = 0;
    }
    camYaw = _wrap(camYaw + _wrap(_yawGoal - camYaw) * math.min(1.0, dt * (_manualCam > 0 ? 9 : 2.2)));
    camTilt += (_tiltGoal - camTilt) * math.min(1.0, dt * 6);
  }

  /// Royale slides from afternoon towards a smoky dusk; Blok Craft runs a
  /// full day in about seven minutes.
  void _updateSky(double dt) {
    if (sim.mode == GameMode.craft) {
      timeOfDay = (timeOfDay + dt / 420) % 1.0;
    } else if (sim.phase == MatchPhase.running) {
      timeOfDay = 0.40 + math.min(0.20, sim.time / 1100);
    }
  }

  void _adaptQuality(double dt) {
    if (sim.phase != MatchPhase.running || dt > 0.25 || quality <= 0) return;
    if (fps < 48) {
      _slowTime += dt;
    } else {
      _slowTime = math.max(0, _slowTime - dt * 0.5);
    }
    if (_slowTime > 3) {
      quality--;
      _slowTime = 0;
    }
  }

  /// Bakes ground textures while the landing map is up, so the match never
  /// stutters when walking into a new area.
  void _prebakeNextChunk() {
    if (viewW == 0) return;
    final cols = (sim.map.width / _chunkSize).ceil();
    final rows = (sim.map.height / _chunkSize).ceil();
    for (var cy = 0; cy < rows; cy++) {
      for (var cx = 0; cx < cols; cx++) {
        final key = cy * 1000 + cx;
        if (_chunkImages.containsKey(key)) continue;
        _bakedThisFrame = 0;
        _chunkImage(key, cx, cy);
        return;
      }
    }
  }

  void _footsteps(double dt) {
    if (sim.phase != MatchPhase.running) return;
    for (var i = 0; i < sim.actors.length; i++) {
      final a = sim.actors[i];
      if (!a.alive || a.vel.length2 < 100 || !_nearCamera(a.pos.x, a.pos.y)) continue;
      _stepTimers[i] -= dt;
      if (_stepTimers[i] <= 0) {
        _stepTimers[i] = 0.24;
        fx.dust(a.pos.x, a.pos.y);
      }
    }
  }

  void _updateParticles(double dt) {
    final hw = viewW / zoom, hh = viewH / zoom;
    for (final p in particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.life -= dt;
      if (p.life <= 0 || (p.x - camX).abs() > hw || (p.y - camY).abs() > hh) {
        p.x = camX + (_rng.nextDouble() * 2 - 1) * hw;
        p.y = camY + (_rng.nextDouble() * 2 - 1) * hh;
        p.life = 3 + _rng.nextDouble() * 5;
        p.maxLife = p.life;
      }
    }
  }

  // ------------------------------------------------------------- listeners

  void _addShake(double mag, double time) {
    _shake = math.max(_shake, mag);
    _shakeTime = math.max(_shakeTime, time);
  }

  int _colorOf(Actor? a) => a?.weapon?.stats.color.toARGB32() ?? 0xFF4FC3F7;

  /// Plays a sound whose volume falls off with distance from the camera.
  void _play3d(String name, double x, double y, {double gain = 1, double range = 900}) {
    final f = sim.focus.pos;
    final dx = x - f.x, dy = y - f.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d >= range) return;
    feedback.play(name, volume: gain * (1 - d / range));
  }

  static String _shotSound(Actor a) => switch (a.weapon?.stats.id) {
    'soaker_rifle' => 'shot_rifle',
    'bubble_launcher' => 'shot_launcher',
    _ => 'shot_pistol',
  };

  @override
  void onDamaged(Actor a, double amount, Actor? source) {
    if (_nearCamera(a.pos.x, a.pos.y)) {
      final c = _colorOf(source);
      fx.splat(
        a.pos.x + (_rng.nextDouble() - 0.5) * 30,
        a.pos.y + (_rng.nextDouble() - 0.5) * 30,
        18 + amount * 1.2,
        c,
      );
      fx.burst(a.pos.x, a.pos.y, 18, c, 6, 110);
    }
    if (identical(a, sim.player)) {
      _addShake(5 + amount * 0.3, 0.18);
      hurtTimer = 0.35;
      feedback.playerHit(sim.time);
      feedback.play('hurt');
    } else if (identical(source, sim.player)) {
      feedback.play('hit', volume: 0.8);
    } else {
      _play3d('hit', a.pos.x, a.pos.y, gain: 0.4);
    }
  }

  @override
  void onShot(Actor a) {
    lastShot[a.id] = sim.time;
    if (_nearCamera(a.pos.x, a.pos.y)) {
      final w = a.weapon;
      final len = Actor.radius + 18 + (w?.stats.rank ?? 1) * 5;
      fx.muzzle(a.pos.x + math.cos(a.aimAngle) * len, a.pos.y + math.sin(a.aimAngle) * len, a.aimAngle, _colorOf(a));
    }
    if (identical(a, sim.player)) {
      feedback.play(_shotSound(a), volume: 0.75);
    } else {
      _play3d(_shotSound(a), a.pos.x, a.pos.y, gain: 0.5);
    }
  }

  @override
  void onSplash(double x, double y) {
    if (_nearCamera(x, y)) {
      fx.splat(x, y, 90, config.weapons['bubble_launcher']?.color.toARGB32() ?? 0xFFFF7043);
      fx.burst(x, y, 10, 0xFFFFFFFF, 10, 180);
    }
    _play3d('splash', x, y, gain: 0.9, range: 1000);
    final p = sim.player.pos;
    final dx = p.x - x, dy = p.y - y;
    if (dx * dx + dy * dy < 400 * 400) _addShake(4, 0.15);
  }

  @override
  void onTagOut(Actor victim, Actor? by, String cause) {
    if (_nearCamera(victim.pos.x, victim.pos.y)) {
      final c = cause == 'haze' ? 0xFF8D6E63 : _colorOf(by);
      fx.splat(victim.pos.x, victim.pos.y, 110, c);
      fx.burst(victim.pos.x, victim.pos.y, 20, c, 18, 200);
    }
    if (identical(victim, sim.player) || identical(by, sim.player)) {
      feedback.play('tag_out');
    } else {
      _play3d('tag_out', victim.pos.x, victim.pos.y, gain: 0.5);
    }
    if (identical(by, sim.player)) feedback.tagOut(sim.time);
    if (identical(victim, sim.player)) {
      feedback.playerTaggedOut(sim.time);
      _addShake(12, 0.4);
    }
  }

  @override
  void onPickup(Actor a, LootItem item) {
    if (identical(a, sim.player)) {
      fx.sparkle(a.pos.x, a.pos.y, 0xFFFFF59D);
      feedback.play('pickup', volume: 0.7);
    }
  }

  @override
  void onTreePlanted(Actor a, Tree t) {
    if (_nearCamera(t.x, t.y)) fx.leaves(t.x, t.y);
    if (identical(a, sim.player)) {
      feedback.treePlanted(sim.time);
      feedback.play('plant', volume: 0.9);
    } else {
      _play3d('plant', t.x, t.y, gain: 0.5);
    }
  }

  int _blockColor(int type) => config.blocks.types[type].top.toARGB32();

  @override
  void onBlockMined(Actor a, int bx, int by, int type) {
    final b = sim.blocks;
    final x = b.wx(bx), y = b.wy(by);
    if (_nearCamera(x, y)) fx.blockBurst(x, y, _blockColor(type), count: quality >= 2 ? 10 : 5);
    if (identical(a, sim.player)) {
      feedback.play('mine', volume: 0.75);
    } else {
      _play3d('mine', x, y, gain: 0.45);
    }
  }

  @override
  void onBlockPlaced(Actor a, int bx, int by, int type) {
    final b = sim.blocks;
    final x = b.wx(bx), y = b.wy(by);
    if (_nearCamera(x, y) && quality >= 2) fx.blockBurst(x, y, _blockColor(type), count: 4, size: 3);
    if (identical(a, sim.player)) {
      feedback.play('place', volume: 0.7);
    } else {
      _play3d('place', x, y, gain: 0.4);
    }
  }

  @override
  void onBlockBroken(double x, double y, int type) {
    if (_nearCamera(x, y)) fx.blockBurst(x, y, _blockColor(type), count: quality >= 2 ? 12 : 6, size: 6);
    _play3d('mine', x, y, gain: 0.5);
  }

  @override
  void onCrafted(Actor a, BlockRecipe recipe) {
    if (identical(a, sim.player)) feedback.play('craft', volume: 0.85);
  }

  @override
  void onReload(Actor a) {
    if (identical(a, sim.player)) feedback.play('reload', volume: 0.8);
  }

  @override
  void onPlayerFinished(PlayerResult r) => onPlayerFinishedCallback?.call(r);

  // ------------------------------------------------------------------ render

  static final _paint = Paint();
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  Paint _fill(Color c) => _paint..color = c;
  Paint _line(Color c, double w) => _stroke
    ..color = c
    ..strokeWidth = w;

  @override
  void render(Canvas canvas) {
    if (viewW == 0) return;
    var sx = camX, sy = camY;
    if (_shakeTime > 0) {
      sx += (_rng.nextDouble() - 0.5) * _shake * 2 / zoom;
      sy += (_rng.nextDouble() - 0.5) * _shake * 2 / zoom;
    } else {
      _shake = 0;
    }
    renderer.render(canvas, sx, sy);
    renderer.drawScreenEffects(canvas);
  }

  void drawChunks(Canvas canvas, Rect visible) {
    _bakedThisFrame = 0;
    final cols = (sim.map.width / _chunkSize).ceil();
    final rows = (sim.map.height / _chunkSize).ceil();
    final x0 = math.max(0, (visible.left / _chunkSize).floor());
    final y0 = math.max(0, (visible.top / _chunkSize).floor());
    final x1 = math.min(cols - 1, (visible.right / _chunkSize).floor());
    final y1 = math.min(rows - 1, (visible.bottom / _chunkSize).floor());
    for (var cy = y0; cy <= y1; cy++) {
      for (var cx = x0; cx <= x1; cx++) {
        final key = cy * 1000 + cx;
        final img = _chunkImage(key, cx, cy);
        if (img != null) {
          final scale = img.width / (_chunkSize + _chunkPad * 2);
          final pad = _chunkPad * scale;
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(pad, pad, img.width - pad * 2, img.height - pad * 2),
            Rect.fromLTWH(cx * _chunkSize, cy * _chunkSize, _chunkSize, _chunkSize),
            _chunkPaint,
          );
        } else {
          canvas.drawPicture(_chunks[key] ??= _recordChunk(cx, cy));
        }
      }
    }
  }

  /// Texture for a chunk, baking at most one new chunk per frame (the others
  /// fall back to the vector picture until their turn).
  Image? _chunkImage(int key, int cx, int cy) {
    final cached = _chunkImages[key];
    if (cached != null) {
      _chunkLru
        ..remove(key)
        ..add(key);
      return cached;
    }
    if (_bakedThisFrame >= 1 || viewW == 0) return null;
    _bakedThisFrame++;
    final pic = _chunks.remove(key) ?? _recordChunk(cx, cy);
    // About one texel per screen pixel near the camera.
    final texScale = (zoom * 1.3).clamp(0.5, 0.85);
    final size = ((_chunkSize + _chunkPad * 2) * texScale).ceil();
    final rec = PictureRecorder();
    final c = Canvas(rec)
      ..scale(texScale)
      ..translate(-cx * _chunkSize + _chunkPad, -cy * _chunkSize + _chunkPad);
    c.drawPicture(pic);
    final img = rec.endRecording().toImageSync(size, size);
    pic.dispose();
    _chunkImages[key] = img;
    _chunkLru.add(key);
    while (_chunkLru.length > _maxChunkImages) {
      _chunkImages.remove(_chunkLru.removeAt(0))?.dispose();
    }
    return img;
  }

  static const _areaColors = {
    'forest': Color(0xFF3B7A37),
    'plantation': Color(0xFF79AD47),
    'kampung': Color(0xFF97C862),
    'town': Color(0xFFBCC2C5),
    'beach': Color(0xFFEBD8A2),
  };

  /// Static ground art for one 500x500 chunk, recorded once and replayed.
  Picture _recordChunk(int cx, int cy) {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    final clip = Rect.fromLTWH(cx * _chunkSize, cy * _chunkSize, _chunkSize, _chunkSize);
    // Include a small margin so baked textures overlap without seams.
    c.clipRect(clip.inflate(_chunkPad));
    final p = Paint();
    final s = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final map = sim.map;
    final cull = clip.inflate(80);
    final rng = math.Random(cx * 7919 + cy * 104729 + map.config.seed);

    for (final a in map.config.areas) {
      if (!a.rect.overlaps(clip)) continue;
      final base = _areaColors[a.type] ?? const Color(0xFF9CCB65);
      // Gentle light-to-dark gradient across each area for depth.
      p.color = const Color(0xFFFFFFFF);
      p.shader = Gradient.linear(a.rect.topLeft, a.rect.bottomRight, [
        Color.lerp(base, const Color(0xFFFFFFFF), 0.06)!,
        Color.lerp(base, const Color(0xFF000000), 0.08)!,
      ]);
      c.drawRect(a.rect, p);
      p.shader = null;
      final area = a.rect.intersect(clip.inflate(10));
      c.save();
      c.clipRect(a.rect);
      _groundDetail(c, a.type, area, rng, p, s);
      c.restore();
    }

    // Sand rim and wet edge where the island meets the sea.
    final land = Rect.fromLTWH(0, 0, map.width, map.height);
    p.color = const Color(0xFFE3CF93);
    for (final edge in [
      Rect.fromLTWH(0, 0, map.width, 18),
      Rect.fromLTWH(0, 0, 18, map.height),
      Rect.fromLTWH(map.width - 18, 0, 18, map.height),
    ]) {
      if (edge.overlaps(cull)) c.drawRect(edge, p);
    }
    p.color = const Color(0xFFD2BC7E);
    c.drawRect(Rect.fromLTWH(0, map.height - 70, map.width, 70), p);
    p.color = const Color(0x55A08350);
    c.drawRect(Rect.fromLTWH(0, map.height - 14, map.width, 14), p);

    for (final d in map.decor) {
      if (!d.rect.overlaps(cull)) continue;
      switch (d.kind) {
        case 'road':
          _road(c, d.rect, p);
        case 'path':
          final rr = RRect.fromRectAndRadius(d.rect, const Radius.circular(22));
          p.color = const Color(0xFFB08A55);
          c.drawRRect(rr.inflate(3), p);
          p.color = const Color(0xFFC9A46B);
          c.drawRRect(rr, p);
          p.color = const Color(0x22000000);
          for (var i = 0; i < 40; i++) {
            final x = d.rect.left + rng.nextDouble() * d.rect.width;
            final y = d.rect.top + 6 + rng.nextDouble() * (d.rect.height - 12);
            c.drawCircle(Offset(x, y), 1.5 + rng.nextDouble() * 2.5, p);
          }
        case 'row':
          p.color = const Color(0x1E000000);
          c.drawRect(d.rect, p);
          p.color = const Color(0x14FFFFFF);
          c.drawRect(Rect.fromLTWH(d.rect.left, d.rect.top - 3, d.rect.width, 3), p);
        default:
          final shade = switch (d.kind) {
            'blotch_forest' => const Color(0x26002200),
            'blotch_beach' => const Color(0x1CFFFFFF),
            'blotch_town' => const Color(0x10000000),
            _ => const Color(0x1C1B5E20),
          };
          p.color = shade;
          c.drawOval(d.rect, p);
      }
    }

    for (final b in map.buildings) {
      if (!b.rect.overlaps(cull)) continue;
      _floor(c, b.rect, b.style, b.floorColor, p);
    }

    // Soft contact shadows of upright things (they are drawn in 3D later).
    p.color = const Color(0x30000000);
    for (final b in map.buildings) {
      if (!b.rect.overlaps(cull)) continue;
      c.drawRect(b.rect.shift(const Offset(16, 12)).inflate(6), p);
      p.color = const Color(0x22000000);
      c.drawRect(b.rect.shift(const Offset(8, 6)).inflate(3), p);
      p.color = const Color(0x30000000);
    }
    for (final o in map.obstacles) {
      if (o.x + o.r * 4 < cull.left || o.x - o.r * 4 > cull.right) continue;
      if (o.y + o.r * 4 < cull.top || o.y - o.r * 4 > cull.bottom) continue;
      final r = o.kind == 'palm' ? o.r * 2.4 : o.r * 1.35;
      p.color = const Color(0x22000000);
      c.drawOval(Rect.fromCenter(center: Offset(o.x + r * 0.7, o.y + r * 0.45), width: r * 2.6, height: r * 1.8), p);
      p.color = const Color(0x26000000);
      c.drawOval(Rect.fromCenter(center: Offset(o.x + r * 0.55, o.y + r * 0.35), width: r * 2.0, height: r * 1.35), p);
    }
    s
      ..color = const Color(0x40000000)
      ..strokeWidth = 3;
    c.drawRect(land, s);
    return rec.endRecording();
  }

  void _groundDetail(Canvas c, String type, Rect area, math.Random rng, Paint p, Paint s) {
    if (area.isEmpty) return;
    final n = (area.width * area.height / 1000).round();
    Offset rnd() => Offset(area.left + rng.nextDouble() * area.width, area.top + rng.nextDouble() * area.height);

    void tufts(int count, Color dark, Color light) {
      for (var i = 0; i < count; i++) {
        final o = rnd();
        s
          ..strokeWidth = 1.8
          ..color = rng.nextBool() ? dark : light;
        final h = 5 + rng.nextDouble() * 5;
        c.drawLine(o, o.translate(-3, -h), s);
        c.drawLine(o, o.translate(0, -h * 1.2), s);
        c.drawLine(o, o.translate(3, -h), s);
      }
    }

    switch (type) {
      case 'forest':
        p.color = const Color(0x332A1B0E);
        for (var i = 0; i < n * 0.9; i++) {
          final o = rnd();
          c.drawOval(Rect.fromCenter(center: o, width: 5 + rng.nextDouble() * 6, height: 3 + rng.nextDouble() * 3), p);
        }
        p.color = const Color(0x33A5D6A7);
        for (var i = 0; i < n * 0.15; i++) {
          c.drawCircle(rnd(), 6 + rng.nextDouble() * 14, p);
        }
        tufts((n * 0.5).round(), const Color(0xFF2E6B2B), const Color(0xFF4F9447));
      case 'plantation':
        tufts((n * 0.55).round(), const Color(0xFF5E9238), const Color(0xFF94C463));
        p.color = const Color(0x22795548);
        for (var i = 0; i < n * 0.08; i++) {
          c.drawOval(
            Rect.fromCenter(center: rnd(), width: 20 + rng.nextDouble() * 30, height: 10 + rng.nextDouble() * 12),
            p,
          );
        }
      case 'kampung':
        tufts((n * 0.6).round(), const Color(0xFF6FA444), const Color(0xFFB4DA82));
        const flowers = [Color(0xFFFFF176), Color(0xFFFFFFFF), Color(0xFFF48FB1), Color(0xFFFFB74D)];
        for (var i = 0; i < n * 0.12; i++) {
          final o = rnd();
          p.color = flowers[rng.nextInt(flowers.length)];
          for (var k = 0; k < 3; k++) {
            c.drawCircle(o.translate(rng.nextDouble() * 8 - 4, rng.nextDouble() * 8 - 4), 1.8, p);
          }
        }
      case 'town':
        s
          ..strokeWidth = 1
          ..color = const Color(0x14000000);
        final x0 = (area.left / 40).floor() * 40.0, y0 = (area.top / 40).floor() * 40.0;
        for (var x = x0; x < area.right; x += 40) {
          c.drawLine(Offset(x, area.top), Offset(x, area.bottom), s);
        }
        for (var y = y0; y < area.bottom; y += 40) {
          c.drawLine(Offset(area.left, y), Offset(area.right, y), s);
        }
        s.color = const Color(0x22000000);
        for (var i = 0; i < n * 0.04; i++) {
          final o = rnd();
          c.drawLine(o, o.translate(rng.nextDouble() * 20 - 10, rng.nextDouble() * 20 - 10), s);
        }
      case 'beach':
        p.color = const Color(0x22806020);
        for (var i = 0; i < n * 1.2; i++) {
          c.drawCircle(rnd(), 0.8 + rng.nextDouble() * 1.2, p);
        }
        p.color = const Color(0x40FFFFFF);
        for (var i = 0; i < n * 0.6; i++) {
          c.drawCircle(rnd(), 0.8 + rng.nextDouble(), p);
        }
        s
          ..strokeWidth = 2
          ..color = const Color(0x1A8B6B35);
        for (var i = 0; i < n * 0.05; i++) {
          final o = rnd();
          c.drawArc(Rect.fromCenter(center: o, width: 40, height: 14), math.pi * 1.1, math.pi * 0.8, false, s);
        }
        p.color = const Color(0xFFF5F0E6);
        for (var i = 0; i < n * 0.02; i++) {
          c.drawOval(Rect.fromCenter(center: rnd(), width: 6, height: 4), p);
        }
    }
  }

  void _road(Canvas c, Rect r, Paint p) {
    final horizontal = r.width > r.height;
    // Kerb + pavement either side.
    p.color = const Color(0xFFD8DCDE);
    c.drawRect(horizontal ? r.copyWithY(r.top - 16, r.bottom + 16) : r.copyWithX(r.left - 16, r.right + 16), p);
    p.color = const Color(0xFF8E979C);
    c.drawRect(horizontal ? r.copyWithY(r.top - 3, r.bottom + 3) : r.copyWithX(r.left - 3, r.right + 3), p);
    p.color = const Color(0xFF545E63);
    c.drawRect(r, p);
    p.color = const Color(0x18FFFFFF);
    c.drawRect(horizontal ? r.copyWithY(r.top, r.top + 10) : r.copyWithX(r.left, r.left + 10), p);
    p.color = const Color(0xE6FFF59D);
    final len = horizontal ? r.width : r.height;
    for (var t = 0.0; t < len; t += 60) {
      c.drawRect(
        horizontal
            ? Rect.fromLTWH(r.left + t, r.center.dy - 2, 30, 4)
            : Rect.fromLTWH(r.center.dx - 2, r.top + t, 4, 30),
        p,
      );
    }
    // Zebra crossings near both ends.
    p.color = const Color(0xCCFFFFFF);
    for (final at in [0.25, 0.75]) {
      for (var k = 0; k < 6; k++) {
        if (horizontal) {
          c.drawRect(Rect.fromLTWH(r.left + r.width * at + k * 12, r.top + 6, 7, r.height - 12), p);
        } else {
          c.drawRect(Rect.fromLTWH(r.left + 6, r.top + r.height * at + k * 12, r.width - 12, 7), p);
        }
      }
    }
  }

  void _floor(Canvas c, Rect r, String style, Color floor, Paint p) {
    p.color = floor;
    c.drawRect(r, p);
    switch (style) {
      case 'town':
        p.color = const Color(0x0F000000);
        for (var y = r.top; y < r.bottom; y += 24) {
          for (var x = r.left + ((y - r.top) / 24).floor() % 2 * 24; x < r.right; x += 48) {
            c.drawRect(Rect.fromLTWH(x, y, 24, 24), p);
          }
        }
      case 'kampung':
      case 'forest':
        p.color = const Color(0x1C000000);
        for (var x = r.left + 14; x < r.right; x += 14) {
          c.drawRect(Rect.fromLTWH(x, r.top, 1.5, r.height), p);
        }
        p.color = const Color(0x0CFFFFFF);
        for (var x = r.left + 3; x < r.right; x += 28) {
          c.drawRect(Rect.fromLTWH(x, r.top, 5, r.height), p);
        }
      default:
        p.color = const Color(0x14000000);
        for (var y = r.top + 18; y < r.bottom; y += 18) {
          c.drawRect(Rect.fromLTWH(r.left, y, r.width, 2), p);
        }
    }
    // Darker corners (ambient occlusion).
    p.color = const Color(0xFFFFFFFF);
    p.shader = Gradient.radial(r.center, r.shortestSide * 0.8, [const Color(0x00000000), const Color(0x26000000)]);
    c.drawRect(r, p);
    p.shader = null;
  }

  void drawEffects(Canvas canvas, Rect cull) {
    for (final e in sim.effects.items) {
      if (!e.active || !cull.contains(Offset(e.x, e.y))) continue;
      final t = e.life / e.maxLife;
      final color = Color(e.color).withValues(alpha: t * 0.8);
      if (e.kind == 0) {
        canvas.drawCircle(Offset(e.x, e.y), e.radius * (1.1 - t * 0.6), _line(color, 6 * t + 1));
        canvas.drawCircle(Offset(e.x, e.y), e.radius * (1.1 - t * 0.6), _fill(color.withValues(alpha: t * 0.25)));
      } else {
        canvas.drawCircle(Offset(e.x, e.y), e.radius * (1.4 - t * 0.4), _fill(color));
      }
    }
  }

  void drawZoneLines(Canvas canvas) {
    final z = sim.zone;
    if (!z.finished) {
      // Dashed white ring: where the safe zone will shrink to.
      const dashes = 72;
      final paint = _line(const Color(0xDDFFFFFF), 3 / zoom);
      for (var i = 0; i < dashes; i++) {
        final a0 = i / dashes * math.pi * 2 + clock * 0.05;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(z.nextX, z.nextY), radius: z.nextR),
          a0,
          math.pi / dashes,
          false,
          paint,
        );
      }
    }
  }

  void drawAimLine(Canvas canvas) {
    final p = sim.player;
    final w = p.weapon;
    if (!p.alive || w == null || aimInput.length2 < 0.0025) return;
    final o = Offset(p.pos.x, p.pos.y);
    final r = w.stats.range;
    final cos = math.cos(p.aimAngle), sin = math.sin(p.aimAngle);
    // Dotted range guide that fades towards max range.
    for (var d = 34.0; d < r; d += 22) {
      final a = (1 - d / r) * 0.5;
      canvas.drawCircle(o.translate(cos * d, sin * d), 3.2, _fill(Color.fromRGBO(255, 255, 255, a)));
    }
  }

  /// World position of a point on screen (used by mouse aiming).
  Vector2 screenToWorld(double x, double y) {
    final (wx, wy) = renderer.unproject(x, y);
    return Vector2(wx, wy);
  }
}

class HazeParticle {
  HazeParticle(math.Random rng)
    : x = 0,
      y = 0,
      vx = 12 + rng.nextDouble() * 22,
      vy = -6 + rng.nextDouble() * 12,
      size = 50 + rng.nextDouble() * 70,
      life = 0,
      maxLife = 1;

  double x, y, vx, vy, size, life, maxLife;
}

extension on Rect {
  Rect copyWithY(double top, double bottom) => Rect.fromLTRB(left, top, right, bottom);
  Rect copyWithX(double l, double r) => Rect.fromLTRB(l, top, r, bottom);
}
