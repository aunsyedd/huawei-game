import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart' show Alignment, RadialGradient;

import '../components/actor.dart';
import '../components/building.dart';
import '../haze_royale_game.dart';
import '../systems/match_manager.dart';

/// Something standing up out of the ground, depth-sorted each frame.
class _Item {
  int kind = 0; // 0 obstacle, 1 wall, 2 roof, 3 actor, 4 tree, 5 projectile
  int index = 0;
  double key = 0;
}

/// Tilted 3D camera ("2.5D"): the ground is drawn through a perspective
/// matrix, upright things (walls, roofs, trees, players, shots) are projected
/// point by point and painted back-to-front.
///
/// World axes: x right, y towards the camera (south), z up.
class PerspectiveRenderer {
  PerspectiveRenderer(this.game) {
    final map = game.sim.map;
    for (var b = 0; b < map.buildings.length; b++) {
      for (final _ in map.buildings[b].walls) {
        _wallBuilding.add(b);
      }
      final bld = map.buildings[b];
      _heights.add(switch (bld.style) {
        'town' => 88.0,
        'kampung' => 64.0,
        'beach' => 50.0,
        _ => 58.0,
      });
      _roofDark.add(Color.lerp(bld.roofColor, const Color(0xFF000000), 0.28)!);
      _roofLight.add(Color.lerp(bld.roofColor, const Color(0xFFFFFFFF), 0.12)!);
      final wall = switch (bld.style) {
        'town' => const Color(0xFFEDE7DF),
        'kampung' => const Color(0xFF9C6B45),
        'beach' => const Color(0xFFD9C08E),
        'plantation' => const Color(0xFF90A4AE),
        _ => const Color(0xFF7B5A43),
      };
      _wallFront.add(wall);
      _wallSide.add(Color.lerp(wall, const Color(0xFF000000), 0.25)!);
      _wallTop.add(Color.lerp(wall, const Color(0xFF000000), 0.45)!);
    }
    for (var i = 0; i < 700; i++) {
      _pool.add(_Item());
    }
  }

  final HazeRoyaleGame game;

  /// Camera tilt from straight down, and distance to the look-at point.
  static const double tilt = 0.74; // ~42°
  static const double distance = 1200;
  static final double _sinT = math.sin(tilt), _cosT = math.cos(tilt);

  // Per-frame camera.
  double _cx = 0, _cy = 0, _f = 1, _w2 = 0, _h0 = 0;
  final Float64List _m = Float64List(16);

  // Last projection result.
  double _px = 0, _py = 0, _ps = 1;

  /// Screen position from the last successful [project] call.
  Offset get projected => Offset(_px, _py);

  final List<int> _wallBuilding = [];
  final List<double> _heights = [];
  final List<Color> _roofDark = [], _roofLight = [], _wallFront = [], _wallSide = [], _wallTop = [];
  final List<_Item> _pool = [];
  final List<_Item> _draw = [];
  int _used = 0;

  final Path _path = Path();
  final Paint _p = Paint();
  final Paint _s = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final _clear = Paint()..blendMode = BlendMode.clear;

  Paint _fill(Color c) => _p..color = c;
  Paint _line(Color c, double w) => _s
    ..color = c
    ..strokeWidth = w;

  // --------------------------------------------------------------- camera

  void setCamera(double camX, double camY) {
    final g = game;
    _cx = camX;
    _cy = camY;
    _f = g.zoom * distance;
    _w2 = g.viewW / 2;
    _h0 = g.viewH * 0.6;
    final d = distance + camY * _sinT;
    // Row-major thinking, column-major storage: index = col * 4 + row.
    void set(int row, int col, double v) => _m[col * 4 + row] = v;
    _m.fillRange(0, 16, 0);
    set(0, 0, _f);
    set(0, 1, -_w2 * _sinT);
    set(0, 2, -_w2 * _cosT);
    set(0, 3, _w2 * d - _f * camX);
    set(1, 1, -_h0 * _sinT + _f * _cosT);
    set(1, 2, -_h0 * _cosT - _f * _sinT);
    set(1, 3, _h0 * d - _f * _cosT * camY);
    set(2, 2, 1);
    set(3, 1, -_sinT);
    set(3, 2, -_cosT);
    set(3, 3, d);
  }

  /// Projects a world point; result in [_px], [_py], scale in [_ps].
  bool project(double x, double y, double z) {
    final w = distance - (y - _cy) * _sinT - z * _cosT;
    if (w < 20) return false;
    _px = _w2 + _f * (x - _cx) / w;
    _py = _h0 + _f * (_cosT * (y - _cy) - _sinT * z) / w;
    _ps = _f / w;
    return true;
  }

  /// Screen point → ground point (z = 0).
  (double, double) unproject(double sx, double sy) {
    final a = sy - _h0;
    final denom = math.max(_f * _cosT + a * _sinT, 1.0);
    final dy = a * distance / denom;
    final w = distance - dy * _sinT;
    final dx = (sx - _w2) * w / _f;
    return (_cx + dx, _cy + dy);
  }

  Rect _visibleGround() {
    final g = game;
    final (x0, y0) = unproject(0, 0);
    final (x1, _) = unproject(g.viewW, 0);
    final (x2, y2) = unproject(0, g.viewH);
    final (x3, _) = unproject(g.viewW, g.viewH);
    return Rect.fromLTRB(
      math.min(math.min(x0, x2), math.min(x1, x3)),
      y0,
      math.max(math.max(x0, x2), math.max(x1, x3)),
      y2,
    );
  }

  // --------------------------------------------------------------- frame

  void render(Canvas canvas, double camX, double camY) {
    final g = game;
    final sim = g.sim;
    setCamera(camX, camY);
    final visible = _visibleGround();
    final cull = visible.inflate(120);
    final running = sim.phase != MatchPhase.dropping;

    // Ground layer through the perspective matrix.
    canvas.save();
    canvas.transform(_m);
    g.drawChunks(canvas, visible);
    if (running) {
      _drawTreeBubbles(canvas, cull);
      g.drawLoot(canvas, cull);
      _drawShadows(canvas, cull);
      g.drawEffects(canvas, cull);
      g.drawZoneLines(canvas);
      g.drawAimLine(canvas);
    }
    canvas.restore();

    // Upright things, back to front.
    _collect(cull, running);
    final f = sim.focus.pos;
    for (final it in _draw) {
      switch (it.kind) {
        case 0:
          _drawObstacle(canvas, it.index, f.x, f.y);
        case 1:
          _drawWall(canvas, it.index, f.x, f.y, running);
        case 2:
          _drawRoof(canvas, it.index, f.x, f.y);
        case 3:
          _drawActor(canvas, sim.actors[it.index]);
        case 4:
          _drawTree(canvas, it.index);
        case 5:
          _drawProjectile(canvas, it.index);
      }
    }

    if (running) {
      _drawHaze(canvas, visible);
      _drawHazeWall(canvas, cull);
      _drawParticles(canvas);
    }
  }

  void _add(int kind, int index, double key) {
    if (_used >= _pool.length) _pool.add(_Item());
    final it = _pool[_used++]
      ..kind = kind
      ..index = index
      ..key = key;
    _draw.add(it);
  }

  void _collect(Rect cull, bool running) {
    final sim = game.sim;
    final map = sim.map;
    _draw.clear();
    _used = 0;
    for (var i = 0; i < map.obstacles.length; i++) {
      final o = map.obstacles[i];
      if (o.x > cull.left && o.x < cull.right && o.y > cull.top && o.y < cull.bottom) _add(0, i, o.y);
    }
    for (var i = 0; i < map.walls.length; i++) {
      final w = map.walls[i];
      if (w.overlaps(cull)) _add(1, i, w.bottom - 0.01);
    }
    final f = sim.focus.pos;
    for (var i = 0; i < map.buildings.length; i++) {
      final b = map.buildings[i];
      if (!b.rect.overlaps(cull)) continue;
      // No roof over the building the camera's player is in (cutaway view).
      if (running && b.contains(f.x, f.y)) continue;
      _add(2, i, b.rect.bottom + 0.5);
    }
    if (running) {
      for (var i = 0; i < sim.actors.length; i++) {
        final a = sim.actors[i];
        if (a.alive && cull.contains(Offset(a.pos.x, a.pos.y))) _add(3, i, a.pos.y);
      }
      for (var i = 0; i < sim.trees.length; i++) {
        final t = sim.trees[i];
        if (t.alive && cull.contains(Offset(t.x, t.y))) _add(4, i, t.y);
      }
      final ps = sim.projectiles.items;
      for (var i = 0; i < ps.length; i++) {
        final p = ps[i];
        if (p.active && cull.contains(Offset(p.x, p.y))) _add(5, i, p.y);
      }
    }
    _draw.sort((a, b) => a.key.compareTo(b.key));
  }

  /// See-through when this object sits between the camera and the player.
  bool _occludesFocus(double l, double r, double bottom, double height, double fx, double fy) {
    if (!game.sim.player.alive && game.sim.phase == MatchPhase.dropping) return false;
    return fx > l - 30 && fx < r + 30 && fy < bottom && fy > bottom - height * 2.2 - 40;
  }

  // --------------------------------------------------------------- ground layer

  void _drawTreeBubbles(Canvas canvas, Rect cull) {
    for (final t in game.sim.trees) {
      if (!t.alive || t.bubble <= 0) continue;
      final o = Offset(t.x, t.y);
      if (!cull.inflate(t.bubble).contains(o)) continue;
      canvas.drawCircle(o, t.bubble, _fill(const Color(0x2281C784)));
      canvas.drawCircle(o, t.bubble, _line(const Color(0xAA66BB6A), 4));
    }
  }

  void _drawShadows(Canvas canvas, Rect cull) {
    final sim = game.sim;
    _p.color = const Color(0x40000000);
    for (final a in sim.actors) {
      if (!a.alive || !cull.contains(Offset(a.pos.x, a.pos.y))) continue;
      canvas.drawOval(Rect.fromCenter(center: Offset(a.pos.x + 6, a.pos.y + 4), width: 40, height: 30), _p);
    }
    for (final t in sim.trees) {
      if (!t.alive || !cull.contains(Offset(t.x, t.y))) continue;
      final r = game.config.trees.trunkRadius[t.stage] * 2.2;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(t.x + r * 0.5, t.y + r * 0.3), width: r * 2.4, height: r * 1.6),
        _p,
      );
    }
  }

  // --------------------------------------------------------------- upright things

  void _quad(
    Canvas canvas,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
    double x3,
    double y3,
    double z3,
    Color color,
  ) {
    _path.reset();
    if (!project(x0, y0, z0)) return;
    _path.moveTo(_px, _py);
    if (!project(x1, y1, z1)) return;
    _path.lineTo(_px, _py);
    if (!project(x2, y2, z2)) return;
    _path.lineTo(_px, _py);
    if (!project(x3, y3, z3)) return;
    _path.lineTo(_px, _py);
    _path.close();
    canvas.drawPath(_path, _fill(color));
  }

  void _tri(
    Canvas canvas,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
    Color color,
  ) {
    _path.reset();
    if (!project(x0, y0, z0)) return;
    _path.moveTo(_px, _py);
    if (!project(x1, y1, z1)) return;
    _path.lineTo(_px, _py);
    if (!project(x2, y2, z2)) return;
    _path.lineTo(_px, _py);
    _path.close();
    canvas.drawPath(_path, _fill(color));
  }

  void _drawWall(Canvas canvas, int i, double fx, double fy, bool running) {
    final w = game.sim.map.walls[i];
    final b = _wallBuilding[i];
    final bld = game.sim.map.buildings[b];
    final inside = running && bld.contains(fx, fy);
    final h = inside ? 22.0 : _heights[b];
    var alpha = 1.0;
    if (!inside && running && _occludesFocus(bld.rect.left, bld.rect.right, bld.rect.bottom, h, fx, fy)) alpha = 0.4;
    final front = _wallFront[b].withValues(alpha: alpha);
    final side = _wallSide[b].withValues(alpha: alpha);
    final top = _wallTop[b].withValues(alpha: alpha);
    final camWorldX = _cx;
    if (camWorldX > w.right) {
      _quad(canvas, w.right, w.top, 0, w.right, w.bottom, 0, w.right, w.bottom, h, w.right, w.top, h, side);
    } else if (camWorldX < w.left) {
      _quad(canvas, w.left, w.top, 0, w.left, w.bottom, 0, w.left, w.bottom, h, w.left, w.top, h, side);
    }
    _quad(canvas, w.left, w.bottom, 0, w.right, w.bottom, 0, w.right, w.bottom, h, w.left, w.bottom, h, front);
    _quad(canvas, w.left, w.top, h, w.right, w.top, h, w.right, w.bottom, h, w.left, w.bottom, h, top);
  }

  void _drawRoof(Canvas canvas, int i, double fx, double fy) {
    final Building b = game.sim.map.buildings[i];
    final r = b.rect.inflate(6);
    final h = _heights[i] + 1;
    final ridge = h + math.min(r.width, r.height) * 0.28;
    final alpha = _occludesFocus(r.left, r.right, r.bottom, ridge, fx, fy) ? 0.35 : 1.0;
    final dark = _roofDark[i].withValues(alpha: alpha);
    final light = _roofLight[i].withValues(alpha: alpha);
    final base = b.roofColor.withValues(alpha: alpha);
    if (r.width >= r.height) {
      // Ridge runs east-west: north slope, gable ends, south slope.
      final c = r.center.dy;
      _quad(canvas, r.left, r.top, h, r.right, r.top, h, r.right, c, ridge, r.left, c, ridge, light);
      if (_cx > r.right) _tri(canvas, r.right, r.top, h, r.right, r.bottom, h, r.right, c, ridge, dark);
      if (_cx < r.left) _tri(canvas, r.left, r.top, h, r.left, r.bottom, h, r.left, c, ridge, dark);
      _quad(canvas, r.left, c, ridge, r.right, c, ridge, r.right, r.bottom, h, r.left, r.bottom, h, base);
      if (project(r.left, c, ridge)) {
        final x0 = _px, y0 = _py;
        if (project(r.right, c, ridge)) canvas.drawLine(Offset(x0, y0), Offset(_px, _py), _line(dark, 3 * _ps));
      }
    } else {
      // Ridge runs north-south: far slope first, then the near one, then the south gable.
      final c = r.center.dx;
      void west() => _quad(canvas, r.left, r.top, h, c, r.top, ridge, c, r.bottom, ridge, r.left, r.bottom, h, light);
      void east() => _quad(canvas, c, r.top, ridge, r.right, r.top, h, r.right, r.bottom, h, c, r.bottom, ridge, base);
      if (_cx > c) {
        west();
        east();
      } else {
        east();
        west();
      }
      _tri(canvas, r.left, r.bottom, h, r.right, r.bottom, h, c, r.bottom, ridge, dark);
    }
  }

  void _drawObstacle(Canvas canvas, int i, double fx, double fy) {
    final o = game.sim.map.obstacles[i];
    final near = (o.x - fx).abs() < o.r * 2 + 20 && o.y > fy && o.y - fy < 110;
    final a = near ? 0.45 : 1.0;
    switch (o.kind) {
      case 'tree':
        const trunkH = 34.0;
        if (!project(o.x, o.y, 0)) return;
        final bx = _px, by = _py, bs = _ps;
        project(o.x, o.y, trunkH);
        canvas.drawLine(Offset(bx, by), Offset(_px, _py), _line(Color.fromRGBO(93, 64, 55, a), 8 * bs));
        project(o.x, o.y, trunkH + o.r * 0.9);
        canvas.drawCircle(Offset(_px, _py), o.r * 1.25 * _ps, _fill(Color.fromRGBO(27, 85, 32, a)));
        canvas.drawCircle(
          Offset(_px - o.r * 0.3 * _ps, _py - o.r * 0.35 * _ps),
          o.r * 0.8 * _ps,
          _fill(Color.fromRGBO(46, 125, 50, a)),
        );
        canvas.drawCircle(
          Offset(_px - o.r * 0.45 * _ps, _py - o.r * 0.55 * _ps),
          o.r * 0.35 * _ps,
          _fill(Color.fromRGBO(102, 187, 106, a * 0.8)),
        );
      case 'palm':
        const h = 78.0;
        if (!project(o.x, o.y, 0)) return;
        final bx = _px, by = _py, bs = _ps;
        project(o.x + 8, o.y, h);
        final tx = _px, ty = _py, ts = _ps;
        canvas.drawLine(Offset(bx, by), Offset(tx, ty), _line(Color.fromRGBO(121, 85, 72, a), 6 * bs));
        final frond = _line(Color.fromRGBO(46, 125, 50, a), 7 * ts);
        for (var k = 0; k < 7; k++) {
          final ang = k * math.pi * 2 / 7 + o.x * 0.01;
          if (project(o.x + 8 + math.cos(ang) * o.r * 2.8, o.y + math.sin(ang) * o.r * 2.8, h - 16)) {
            canvas.drawLine(Offset(tx, ty), Offset(_px, _py), frond);
          }
        }
        canvas.drawCircle(Offset(tx, ty), 5 * ts, _fill(Color.fromRGBO(109, 76, 65, a)));
      default:
        if (!project(o.x, o.y, o.r * 0.35)) return;
        final rr = o.r * _ps;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(_px, _py), width: rr * 2.1, height: rr * 1.6),
          _fill(Color.fromRGBO(120, 128, 133, a)),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(_px - rr * 0.3, _py - rr * 0.3), width: rr * 1.0, height: rr * 0.7),
          _fill(Color.fromRGBO(176, 183, 187, a)),
        );
    }
  }

  void _drawTree(Canvas canvas, int i) {
    final t = game.sim.trees[i];
    final tr = game.config.trees.trunkRadius[t.stage];
    final h = 14.0 + tr * 2.2;
    if (!project(t.x, t.y, 0)) return;
    final bx = _px, by = _py, bs = _ps;
    project(t.x, t.y, h);
    canvas.drawLine(Offset(bx, by), Offset(_px, _py), _line(const Color(0xFF6D4C41), tr * 0.6 * bs));
    project(t.x, t.y, h + tr * 1.4);
    final flash = t.hitFlash > 0;
    canvas.drawCircle(
      Offset(_px, _py),
      tr * 1.9 * _ps,
      _fill(flash ? const Color(0xFFFFFFFF) : const Color(0xFF388E3C)),
    );
    canvas.drawCircle(
      Offset(_px - tr * 0.5 * _ps, _py - tr * 0.6 * _ps),
      tr * 1.1 * _ps,
      _fill(const Color(0xFF66BB6A)),
    );
    if (t.health < t.maxHealth && project(t.x, t.y, h + tr * 3.6)) {
      _bar(canvas, _px, _py, t.health / t.maxHealth, const Color(0xFF66BB6A));
    }
  }

  void _bar(Canvas canvas, double x, double y, double frac, Color color) {
    final w = 40 * _ps, h = math.max(3.0, 5 * _ps);
    canvas.drawRect(Rect.fromLTWH(x - w / 2, y, w, h), _fill(const Color(0x99000000)));
    canvas.drawRect(Rect.fromLTWH(x - w / 2, y, w * frac.clamp(0, 1), h), _fill(color));
  }

  void _drawActor(Canvas canvas, Actor a) {
    const r = Actor.radius;
    const z = r;
    final cos = math.cos(a.aimAngle), sin = math.sin(a.aimAngle);
    final w = a.weapon;
    final behind = sin < 0; // aiming away from the camera: gun is behind the body

    void gun() {
      if (w != null) {
        final len = 18.0 + w.stats.rank * 5;
        final width = 6.0 + w.stats.rank * 2;
        if (!project(a.pos.x + cos * 6, a.pos.y + sin * 6, z - 2)) return;
        final x0 = _px, y0 = _py;
        if (!project(a.pos.x + cos * (r + len), a.pos.y + sin * (r + len), z - 2)) return;
        canvas.drawLine(Offset(x0, y0), Offset(_px, _py), _line(w.stats.color, width * _ps));
      }
      for (final side in const [-1.0, 1.0]) {
        if (project(a.pos.x + cos * r * 0.9 - sin * 9 * side, a.pos.y + sin * r * 0.9 + cos * 9 * side, z - 3)) {
          canvas.drawCircle(Offset(_px, _py), 6 * _ps, _fill(a.color));
          canvas.drawCircle(Offset(_px, _py), 6 * _ps, _line(const Color(0x66000000), 1.5 * _ps));
        }
      }
    }

    if (behind) gun();
    if (!project(a.pos.x, a.pos.y, z)) return;
    final o = Offset(_px, _py);
    final rr = r * _ps;
    canvas.drawCircle(o, rr, _fill(a.hitFlash > 0 ? const Color(0xFFFFFFFF) : a.color));
    // Shading for a rounder, 3D look.
    canvas.drawCircle(o.translate(rr * 0.25, rr * 0.3), rr * 0.75, _fill(const Color(0x22000000)));
    canvas.drawCircle(o.translate(-rr * 0.35, -rr * 0.4), rr * 0.38, _fill(const Color(0x55FFFFFF)));
    if (a.armour > 0) {
      canvas.drawCircle(
        o,
        rr - 4 * _ps,
        _line(a.vest?.tier == 2 ? const Color(0xFF1565C0) : const Color(0xFF90CAF9), 4 * _ps),
      );
    }
    canvas.drawCircle(
      o,
      rr,
      _line(a.isPlayer ? const Color(0xFFFFFFFF) : const Color(0xAA000000), (a.isPlayer ? 3.5 : 2) * _ps),
    );
    if (a.hazeShield > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: o.translate(0, rr * 0.25), width: 16 * _ps, height: 8 * _ps),
          Radius.circular(3 * _ps),
        ),
        _fill(const Color(0xFFECEFF1)),
      );
    }
    final ps = _ps;
    if (!behind) gun();
    if (a.busy) {
      final color = a.action == ActorAction.planting ? const Color(0xFF66BB6A) : const Color(0xFF4FC3F7);
      canvas.drawArc(
        Rect.fromCircle(center: o, radius: rr + 8 * ps),
        -math.pi / 2,
        math.pi * 2 * a.actionProgress,
        false,
        _line(color, 5 * ps),
      );
    }
    if (!a.isPlayer && game.sim.time - a.lastDamageTime < 3 && project(a.pos.x, a.pos.y, z + r + 22)) {
      _bar(canvas, _px, _py, a.health / a.maxHealth, const Color(0xFFEF5350));
    }
  }

  void _drawProjectile(Canvas canvas, int i) {
    final p = game.sim.projectiles.items[i];
    final w = p.weapon;
    if (!project(p.x - p.vx * 0.025, p.y - p.vy * 0.025, 16)) return;
    final tx = _px, ty = _py;
    if (!project(p.x, p.y, 16)) return;
    final o = Offset(_px, _py);
    canvas.drawLine(Offset(tx, ty), o, _line(w.color.withValues(alpha: 0.35), w.projectileRadius * 1.6 * _ps));
    canvas.drawCircle(o, w.projectileRadius * _ps, _fill(w.color));
    canvas.drawCircle(
      o.translate(-1.5 * _ps, -1.5 * _ps),
      w.projectileRadius * 0.4 * _ps,
      _fill(const Color(0xCCFFFFFF)),
    );
  }

  // --------------------------------------------------------------- haze

  static final _hazePaint = Paint()..color = const Color(0x99A8784A);

  void _drawHaze(Canvas canvas, Rect visible) {
    final z = game.sim.zone;
    final fx = math.max((visible.left - z.cx).abs(), (visible.right - z.cx).abs());
    final fy = math.max((visible.top - z.cy).abs(), (visible.bottom - z.cy).abs());
    if (fx * fx + fy * fy < z.r * z.r) return;
    canvas.saveLayer(null, Paint());
    canvas.transform(_m);
    canvas.drawRect(visible.inflate(50), _hazePaint);
    if (z.r > 0) canvas.drawCircle(Offset(z.cx, z.cy), z.r, _clear);
    for (final t in game.sim.trees) {
      if (t.alive && t.bubble > 0) canvas.drawCircle(Offset(t.x, t.y), t.bubble, _clear);
    }
    canvas.restore();
  }

  /// The edge of the safe zone rises as a translucent wall of smoke.
  void _drawHazeWall(Canvas canvas, Rect cull) {
    final z = game.sim.zone;
    if (z.r <= 0) return;
    const segments = 96, h = 110.0;
    for (var k = 0; k < segments; k++) {
      final a0 = k / segments * math.pi * 2, a1 = (k + 1) / segments * math.pi * 2;
      final x0 = z.cx + math.cos(a0) * z.r, y0 = z.cy + math.sin(a0) * z.r;
      final x1 = z.cx + math.cos(a1) * z.r, y1 = z.cy + math.sin(a1) * z.r;
      if (!cull.contains(Offset(x0, y0)) && !cull.contains(Offset(x1, y1))) continue;
      _quad(canvas, x0, y0, 0, x1, y1, 0, x1, y1, h, x0, y0, h, const Color(0x40B07A45));
      if (project(x0, y0, h)) {
        final px = _px, py = _py;
        if (project(x1, y1, h)) canvas.drawLine(Offset(px, py), Offset(_px, _py), _line(const Color(0x88FF8A3D), 3));
      }
    }
  }

  void _drawParticles(Canvas canvas) {
    final sim = game.sim;
    for (final p in game.particles) {
      if (sim.isSafeAt(p.x, p.y)) continue;
      if (!project(p.x, p.y, 20 + p.size * 6)) continue;
      final a = (p.life.clamp(0, 1.5) / 1.5) * 0.55;
      canvas.drawCircle(Offset(_px, _py), p.size * _ps * 1.4, _fill(Color.fromRGBO(90, 70, 50, a)));
    }
  }

  // --------------------------------------------------------------- screen

  void drawVignette(Canvas canvas) {
    final g = game;
    final p = g.sim.player;
    if (!p.alive || g.sim.phase != MatchPhase.running) return;
    final inHaze = !g.sim.isSafeAt(p.pos.x, p.pos.y);
    if (!inHaze && g.hurtTimer <= 0) return;
    final color = g.hurtTimer > 0 ? const Color(0x88D32F2F) : const Color(0x998D6E3A);
    final rect = Rect.fromLTWH(0, 0, g.viewW, g.viewH);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [const Color(0x00000000), color],
          stops: const [0.6, 1.0],
        ).createShader(rect),
    );
  }
}
