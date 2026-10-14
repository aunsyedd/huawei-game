import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../data/game_config.dart';
import '../services/feedback_service.dart';
import 'components/actor.dart';
import 'components/loot.dart';
import 'components/tree.dart';
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
    String playerName = 'You',
    int? seed,
  }) : sim = MatchSimulation(config, seed: seed, playerName: playerName) {
    sim.listener = this;
    camX = sim.map.width / 2;
    camY = sim.map.height / 2;
    final rng = math.Random(7);
    for (var i = 0; i < 70; i++) {
      particles.add(HazeParticle(rng));
    }
  }

  final GameConfig config;
  final String lang;
  final FeedbackService feedback;
  final MatchSimulation sim;
  double aimSensitivity;

  // ---- Input written by the Flutter overlays ----
  final Vector2 moveInput = Vector2.zero();
  final Vector2 aimInput = Vector2.zero();
  bool fireHeld = false;

  // ---- Notifications to the HUD ----
  final ValueNotifier<int> hudTick = ValueNotifier(0);
  final ValueNotifier<MatchPhase> phase = ValueNotifier(MatchPhase.dropping);
  void Function(PlayerResult result)? onPlayerFinishedCallback;
  double fps = 60;
  double hurtTimer = 0;

  // ---- Camera ----
  double viewW = 0, viewH = 0, zoom = 1, camX = 0, camY = 0;
  double _shake = 0, _shakeTime = 0;
  final _rng = math.Random();
  double _hudAccum = 0;

  final Map<int, Picture> _chunks = {};
  static const double _chunkSize = 500;
  final List<HazeParticle> particles = [];
  late final PerspectiveRenderer renderer = PerspectiveRenderer(this);

  @override
  Color backgroundColor() => const Color(0xFF2D7FB8);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    viewW = size.x;
    viewH = size.y;
    zoom = math.min(viewW / 1100, viewH / 620).clamp(0.45, 2.0);
  }

  void startMatch(double x, double y) {
    sim.start(x, y);
    final p = sim.player.pos;
    camX = p.x;
    camY = p.y;
    phase.value = MatchPhase.running;
  }

  // ------------------------------------------------------------------ update

  @override
  void update(double dt) {
    if (dt <= 0) return;
    fps = fps * 0.95 + (1 / dt) * 0.05;
    dt = math.min(dt, 0.05);

    final p = sim.player;
    if (p.alive && p.brain == null && sim.phase == MatchPhase.running) {
      p.moveInput.setFrom(moveInput);
      if (aimInput.length2 > 0.0025) {
        p.aimAngle = math.atan2(aimInput.y, aimInput.x);
      } else if (moveInput.length2 > 0.01) {
        p.aimAngle = math.atan2(moveInput.y, moveInput.x);
      }
      p.wantFire = fireHeld;
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
    if (_shakeTime > 0) _shakeTime -= dt;
    if (hurtTimer > 0) hurtTimer -= dt;

    _updateParticles(dt);

    _hudAccum += dt;
    if (_hudAccum > 1 / 12) {
      _hudAccum = 0;
      hudTick.value++;
    }
  }

  void _updateParticles(double dt) {
    final hw = viewW / 2 / zoom, hh = viewH / 2 / zoom;
    for (final p in particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.life -= dt;
      if (p.life <= 0 || (p.x - camX).abs() > hw + 40 || (p.y - camY).abs() > hh + 40) {
        p.x = camX + (_rng.nextDouble() * 2 - 1) * hw;
        p.y = camY + (_rng.nextDouble() * 2 - 1) * hh;
        p.life = 2 + _rng.nextDouble() * 4;
      }
    }
  }

  // ------------------------------------------------------------- listeners

  void _addShake(double mag, double time) {
    _shake = math.max(_shake, mag);
    _shakeTime = math.max(_shakeTime, time);
  }

  @override
  void onDamaged(Actor a, double amount, Actor? source) {
    if (identical(a, sim.player)) {
      _addShake(5 + amount * 0.3, 0.18);
      hurtTimer = 0.35;
      feedback.playerHit(sim.time);
    }
  }

  @override
  void onShot(Actor a) {
    if (identical(a, sim.player)) feedback.shot(a.weapon?.stats.id ?? '');
  }

  @override
  void onSplash(double x, double y) {
    final p = sim.player.pos;
    final dx = p.x - x, dy = p.y - y;
    if (dx * dx + dy * dy < 400 * 400) {
      _addShake(4, 0.15);
      feedback.splash();
    }
  }

  @override
  void onTagOut(Actor victim, Actor? by, String cause) {
    if (identical(by, sim.player)) feedback.tagOut(sim.time);
    if (identical(victim, sim.player)) {
      feedback.playerTaggedOut(sim.time);
      _addShake(12, 0.4);
    }
  }

  @override
  void onPickup(Actor a, LootItem item) {
    if (identical(a, sim.player)) feedback.pickup();
  }

  @override
  void onTreePlanted(Actor a, Tree t) {
    if (identical(a, sim.player)) feedback.treePlanted(sim.time);
  }

  @override
  void onPlayerFinished(PlayerResult r) => onPlayerFinishedCallback?.call(r);

  // ------------------------------------------------------------------ render

  static final _paint = Paint();
  static final _stroke = Paint()..style = PaintingStyle.stroke;

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
    renderer.drawVignette(canvas);
  }

  void drawChunks(Canvas canvas, Rect visible) {
    final cols = (sim.map.width / _chunkSize).ceil();
    final rows = (sim.map.height / _chunkSize).ceil();
    final x0 = math.max(0, (visible.left / _chunkSize).floor());
    final y0 = math.max(0, (visible.top / _chunkSize).floor());
    final x1 = math.min(cols - 1, (visible.right / _chunkSize).floor());
    final y1 = math.min(rows - 1, (visible.bottom / _chunkSize).floor());
    for (var cy = y0; cy <= y1; cy++) {
      for (var cx = x0; cx <= x1; cx++) {
        final key = cy * 1000 + cx;
        final pic = _chunks[key] ??= _recordChunk(cx, cy);
        canvas.drawPicture(pic);
      }
    }
  }

  static const _areaColors = {
    'forest': Color(0xFF3E7D3A),
    'plantation': Color(0xFF7BAF4A),
    'kampung': Color(0xFF9CCB65),
    'town': Color(0xFFB8BEC2),
    'beach': Color(0xFFEBD9A4),
  };

  Picture _recordChunk(int cx, int cy) {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    final clip = Rect.fromLTWH(cx * _chunkSize, cy * _chunkSize, _chunkSize, _chunkSize);
    // Overlap neighbours by a pixel so anti-aliased edges don't show seams.
    c.clipRect(clip.inflate(1.5));
    final p = Paint();
    final s = Paint()..style = PaintingStyle.stroke;
    final map = sim.map;
    final cull = clip.inflate(80);

    for (final a in map.config.areas) {
      if (!a.rect.overlaps(clip)) continue;
      p.color = _areaColors[a.type] ?? const Color(0xFF9CCB65);
      c.drawRect(a.rect, p);
    }
    // Shoreline: wet sand + foam along the bottom of the island.
    p.color = const Color(0xFFD8C48A);
    c.drawRect(Rect.fromLTWH(0, map.height - 60, map.width, 60), p);
    p.color = const Color(0x88FFFFFF);
    c.drawRect(Rect.fromLTWH(0, map.height - 6, map.width, 6), p);

    for (final d in map.decor) {
      if (!d.rect.overlaps(cull)) continue;
      switch (d.kind) {
        case 'road':
          p.color = const Color(0xFF5F6A70);
          c.drawRect(d.rect, p);
          p.color = const Color(0xCCFFFFFF);
          final horizontal = d.rect.width > d.rect.height;
          for (var t = 0.0; t < (horizontal ? d.rect.width : d.rect.height); t += 60) {
            c.drawRect(
              horizontal
                  ? Rect.fromLTWH(d.rect.left + t, d.rect.center.dy - 2, 30, 4)
                  : Rect.fromLTWH(d.rect.center.dx - 2, d.rect.top + t, 4, 30),
              p,
            );
          }
        case 'path':
          p.color = const Color(0xFFC9A46B);
          c.drawRRect(RRect.fromRectAndRadius(d.rect, const Radius.circular(20)), p);
        case 'row':
          p.color = const Color(0x22000000);
          c.drawRect(d.rect, p);
        default:
          final shade = switch (d.kind) {
            'blotch_forest' => const Color(0x22002200),
            'blotch_beach' => const Color(0x18FFFFFF),
            'blotch_town' => const Color(0x10000000),
            _ => const Color(0x1A1B5E20),
          };
          p.color = shade;
          c.drawOval(d.rect, p);
      }
    }

    for (final b in map.buildings) {
      if (!b.rect.overlaps(cull)) continue;
      p.color = b.floorColor;
      c.drawRect(b.rect, p);
      p.color = const Color(0x14000000);
      for (var y = b.rect.top + 18; y < b.rect.bottom; y += 18) {
        c.drawRect(Rect.fromLTWH(b.rect.left, y, b.rect.width, 2), p);
      }
    }
    // Shadows of upright things (drawn in 3D by PerspectiveRenderer).
    p.color = const Color(0x38000000);
    for (final b in map.buildings) {
      if (b.rect.overlaps(cull)) c.drawRect(b.rect.shift(const Offset(14, 10)).inflate(4), p);
    }
    for (final o in map.obstacles) {
      if (o.x + o.r * 4 < cull.left || o.x - o.r * 4 > cull.right) continue;
      if (o.y + o.r * 4 < cull.top || o.y - o.r * 4 > cull.bottom) continue;
      final r = o.kind == 'palm' ? o.r * 2.4 : o.r * 1.3;
      c.drawOval(Rect.fromCenter(center: Offset(o.x + r * 0.6, o.y + r * 0.35), width: r * 2.2, height: r * 1.5), p);
    }
    s
      ..color = const Color(0x55000000)
      ..strokeWidth = 4;
    c.drawRect(Rect.fromLTWH(0, 0, map.width, map.height), s);
    return rec.endRecording();
  }

  void drawLoot(Canvas canvas, Rect cull) {
    final pulse = 1 + math.sin(sim.time * 4) * 0.08;
    for (final l in sim.loot) {
      if (l.taken || !cull.contains(Offset(l.x, l.y))) continue;
      final o = Offset(l.x, l.y);
      canvas.drawCircle(o, 16 * pulse, _fill(const Color(0xCCFFFFFF)));
      final (color, label) = switch (l.kind) {
        LootKind.weapon => (config.weapons[l.refId]?.color ?? const Color(0xFF000000), 0),
        LootKind.armour => (l.refId == 'vest_2' ? const Color(0xFF1565C0) : const Color(0xFF64B5F6), 1),
        LootKind.water => (const Color(0xFF29B6F6), 2),
        LootKind.mask => (const Color(0xFF90A4AE), 3),
        LootKind.seed => (const Color(0xFF43A047), 4),
      };
      canvas.drawCircle(o, 16 * pulse, _line(color, 3));
      switch (label) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 20, height: 9), const Radius.circular(3)),
            _fill(color),
          );
        case 1:
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 14, height: 16), const Radius.circular(5)),
            _fill(color),
          );
        case 2:
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 8, height: 16), const Radius.circular(3)),
            _fill(color),
          );
        case 3:
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 16, height: 10), const Radius.circular(4)),
            _fill(color),
          );
        default:
          canvas.drawCircle(o.translate(0, 3), 5, _fill(const Color(0xFF795548)));
          canvas.drawOval(Rect.fromCenter(center: o.translate(3, -4), width: 10, height: 6), _fill(color));
      }
    }
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
    if (z.r > 0) {
      canvas.drawCircle(Offset(z.cx, z.cy), z.r, _line(const Color(0xCCFF8A3D), 5 / zoom));
    }
    if (!z.finished) {
      canvas.drawCircle(Offset(z.nextX, z.nextY), z.nextR, _line(const Color(0xDDFFFFFF), 2.5 / zoom));
    }
  }

  void drawAimLine(Canvas canvas) {
    final p = sim.player;
    final w = p.weapon;
    if (!p.alive || w == null || aimInput.length2 < 0.0025) return;
    final o = Offset(p.pos.x, p.pos.y);
    final r = w.stats.range;
    canvas.drawLine(
      o.translate(math.cos(p.aimAngle) * 30, math.sin(p.aimAngle) * 30),
      o.translate(math.cos(p.aimAngle) * r, math.sin(p.aimAngle) * r),
      _line(const Color(0x40FFFFFF), 3 / zoom),
    );
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
      vx = 10 + rng.nextDouble() * 25,
      vy = -5 + rng.nextDouble() * 10,
      size = 3 + rng.nextDouble() * 6,
      life = 0;

  double x, y, vx, vy, size, life;
}
