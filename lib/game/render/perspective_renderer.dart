import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../components/actor.dart';
import '../components/building.dart';
import '../components/loot.dart';
import '../haze_royale_game.dart';
import '../systems/match_manager.dart';
import 'fx.dart';
import 'sprites.dart';

/// Something standing up out of the ground, depth-sorted each frame.
class _Item {
  int kind = 0; // 0 obstacle, 1 wall, 2 roof, 3 actor, 4 tree, 5 projectile, 6 loot
  int index = 0;
  double key = 0;
}

/// Tilted 3D camera ("2.5D"): the ground is drawn through a perspective
/// matrix, upright things (walls, roofs, trees, players, shots, loot) are
/// projected point by point and painted back-to-front.
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
      _roofDark.add(Color.lerp(bld.roofColor, const Color(0xFF000000), 0.3)!);
      _roofLight.add(Color.lerp(bld.roofColor, const Color(0xFFFFFFFF), 0.14)!);
      final wall = switch (bld.style) {
        'town' => const Color(0xFFF1EBE2),
        'kampung' => const Color(0xFFA0704A),
        'beach' => const Color(0xFFDCC392),
        'plantation' => const Color(0xFF9AACB4),
        _ => const Color(0xFF80604A),
      };
      _wallFront.add(wall);
      _wallSide.add(Color.lerp(wall, const Color(0xFF000000), 0.28)!);
      _wallTop.add(Color.lerp(wall, const Color(0xFF000000), 0.5)!);
    }
    for (var i = 0; i < 800; i++) {
      _pool.add(_Item());
    }
  }

  final HazeRoyaleGame game;
  final Sprites _sprites = Sprites.instance;

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
  final Paint _sp = Paint()..filterQuality = FilterQuality.low;
  static final _clear = Paint()..blendMode = BlendMode.clear;

  // Cached screen-space shaders (rebuilt on resize).
  Paint? _cornerVignette;

  Paint _fill(Color c) => _p..color = c;
  Paint _line(Color c, double w) => _s
    ..color = c
    ..strokeWidth = w;

  void onResize() => _cornerVignette = null;

  /// Draws a white sprite tinted [color] centred at a screen point.
  void _sprite(Canvas c, Image img, double cx, double cy, double w, double h, Color color, {bool additive = false}) {
    // Quantise alpha so the tint cache stays small.
    final a = ((color.a * 15).round() / 15).clamp(0.0, 1.0);
    _sp
      ..colorFilter = _sprites.tint(color.withValues(alpha: a))
      ..blendMode = additive ? BlendMode.plus : BlendMode.srcOver;
    c.drawImageRect(img, Sprites.src, Rect.fromCenter(center: Offset(cx, cy), width: w, height: h), _sp);
  }

  // --------------------------------------------------------------- camera

  void setCamera(double camX, double camY) {
    final g = game;
    _cx = camX;
    _cy = camY;
    _f = g.zoom * distance;
    _w2 = g.viewW / 2;
    _h0 = g.viewH * 0.6;
    final d = distance + camY * _sinT;
    // Column-major storage: index = col * 4 + row.
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
    _drawSea(canvas, visible);
    g.drawChunks(canvas, visible);
    if (running) {
      _drawDecals(canvas, cull);
      _drawTreeBubbles(canvas, cull);
      _drawLootGround(canvas, cull);
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
        case 6:
          _drawLoot(canvas, sim.loot[it.index]);
      }
    }

    if (running) {
      _drawFxParticles(canvas, cull);
      _drawHaze(canvas, visible);
      _drawHazeWall(canvas, cull);
      _drawHazeSmoke(canvas);
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
      for (var i = 0; i < sim.loot.length; i++) {
        final l = sim.loot[i];
        if (!l.taken && cull.contains(Offset(l.x, l.y))) _add(6, i, l.y);
      }
    }
    _draw.sort((a, b) => a.key.compareTo(b.key));
  }

  /// See-through when this object sits between the camera and the player.
  bool _occludesFocus(double l, double r, double bottom, double height, double fx, double fy) {
    if (game.sim.phase == MatchPhase.dropping) return false;
    return fx > l - 30 && fx < r + 30 && fy < bottom && fy > bottom - height * 2.2 - 40;
  }

  // --------------------------------------------------------------- ground layer

  /// Animated foam lines where the sea meets the island.
  void _drawSea(Canvas canvas, Rect visible) {
    final map = game.sim.map;
    final t = game.clock;
    // Sparkles on the open water.
    for (var i = 0; i < 26; i++) {
      final sx = visible.left + ((i * 397 + t * 18) % visible.width);
      final sy = visible.top + ((i * 211) % visible.height);
      if (sx > -10 && sx < map.width + 10 && sy > -10 && sy < map.height + 10) continue;
      final a = 0.25 + 0.25 * math.sin(t * 2 + i);
      canvas.drawLine(Offset(sx, sy), Offset(sx + 14, sy), _line(Color.fromRGBO(255, 255, 255, a), 2.5));
    }
    for (var k = 0; k < 2; k++) {
      final off = 14.0 + k * 22 + math.sin(t * 1.3 + k) * 6;
      final alpha = k == 0 ? 0.75 : 0.35;
      final paint = _line(Color.fromRGBO(255, 255, 255, alpha), k == 0 ? 6 : 4);
      // Bottom shore (beach), then the other three edges.
      _wavyEdge(
        canvas,
        visible,
        paint,
        0,
        map.width,
        (x) => Offset(x, map.height + off + math.sin(x / 45 + t * 2) * 4),
      );
      _wavyEdge(canvas, visible, paint, 0, map.width, (x) => Offset(x, -off - math.sin(x / 50 + t * 2) * 4));
      _wavyEdge(canvas, visible, paint, 0, map.height, (y) => Offset(-off - math.sin(y / 50 + t * 2) * 4, y));
      _wavyEdge(
        canvas,
        visible,
        paint,
        0,
        map.height,
        (y) => Offset(map.width + off + math.sin(y / 50 + t * 2) * 4, y),
      );
    }
  }

  void _wavyEdge(Canvas canvas, Rect visible, Paint paint, double from, double to, Offset Function(double) at) {
    final start = at(from), end = at(to);
    final edgeBox = Rect.fromPoints(start, end).inflate(40);
    if (!edgeBox.overlaps(visible)) return;
    final horizontal = (end.dx - start.dx).abs() > (end.dy - start.dy).abs();
    final a = math.max(from, horizontal ? visible.left : visible.top);
    final b = math.min(to, horizontal ? visible.right : visible.bottom);
    if (b <= a) return;
    _path.reset();
    var first = true;
    for (var v = a; v <= b; v += 24) {
      final o = at(v);
      if (first) {
        _path.moveTo(o.dx, o.dy);
        first = false;
      } else {
        _path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(_path, paint);
  }

  /// Paint splats left by hits; they fade out over time.
  void _drawDecals(Canvas canvas, Rect cull) {
    for (final d in game.fx.decals) {
      if (!d!.active || !cull.contains(Offset(d.x, d.y))) continue;
      final fade = (1 - d.age / FxSystem.decalLife).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(d.x, d.y);
      canvas.rotate(d.rot);
      _sprite(canvas, _sprites.splats[d.variant], 0, 0, d.size, d.size, Color(d.color).withValues(alpha: 0.55 * fade));
      canvas.restore();
    }
  }

  void _drawTreeBubbles(Canvas canvas, Rect cull) {
    final t = game.clock;
    for (final tree in game.sim.trees) {
      if (!tree.alive || tree.bubble <= 0) continue;
      final o = Offset(tree.x, tree.y);
      if (!cull.inflate(tree.bubble).contains(o)) continue;
      canvas.drawCircle(o, tree.bubble, _fill(const Color(0x2081C784)));
      canvas.drawCircle(o, tree.bubble * 0.7, _fill(const Color(0x14C8E6C9)));
      canvas.drawCircle(o, tree.bubble, _line(const Color(0xBB7CDB80), 4));
      // Pulsing inner ring so clean air reads as "alive".
      final pr = tree.bubble * (0.55 + 0.45 * ((t * 0.5 + tree.x * 0.001) % 1));
      canvas.drawCircle(o, pr, _line(Color.fromRGBO(200, 255, 200, 0.35 * (1 - pr / tree.bubble)), 3));
    }
  }

  Color _lootColor(LootItem l) => switch (l.kind) {
    LootKind.weapon => game.config.weapons[l.refId]?.color ?? const Color(0xFFFFFFFF),
    LootKind.armour => l.refId == 'vest_2' ? const Color(0xFF1565C0) : const Color(0xFF64B5F6),
    LootKind.water => const Color(0xFF29B6F6),
    LootKind.mask => const Color(0xFFB0BEC5),
    LootKind.seed => const Color(0xFF43A047),
  };

  void _drawLootGround(Canvas canvas, Rect cull) {
    final t = game.clock;
    for (final l in game.sim.loot) {
      if (l.taken || !cull.contains(Offset(l.x, l.y))) continue;
      final c = _lootColor(l);
      final pulse = 1 + math.sin(t * 3 + l.x) * 0.12;
      _sprite(canvas, _sprites.glow, l.x, l.y, 64 * pulse, 64 * pulse, c.withValues(alpha: 0.55), additive: true);
      _sprite(canvas, _sprites.softShadow, l.x + 3, l.y + 3, 30, 22, const Color(0xFFFFFFFF));
    }
  }

  void _drawShadows(Canvas canvas, Rect cull) {
    final sim = game.sim;
    for (final a in sim.actors) {
      if (!a.alive || !cull.contains(Offset(a.pos.x, a.pos.y))) continue;
      _sprite(canvas, _sprites.softShadow, a.pos.x + 7, a.pos.y + 6, 54, 40, const Color(0xFFFFFFFF));
      if (identical(a, sim.player)) {
        // Ground marker under the player.
        final pulse = 1 + math.sin(game.clock * 4) * 0.06;
        canvas.drawCircle(Offset(a.pos.x, a.pos.y), 28 * pulse, _line(const Color(0xAA4FC3F7), 3));
      }
    }
    for (final t in sim.trees) {
      if (!t.alive || !cull.contains(Offset(t.x, t.y))) continue;
      final r = game.config.trees.trunkRadius[t.stage] * 2.4;
      _sprite(canvas, _sprites.softShadow, t.x + r * 0.5, t.y + r * 0.3, r * 2.8, r * 2.0, const Color(0xFFFFFFFF));
    }
  }

  // --------------------------------------------------------------- upright helpers

  bool _quadPath(
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
  ) {
    _path.reset();
    if (!project(x0, y0, z0)) return false;
    _path.moveTo(_px, _py);
    if (!project(x1, y1, z1)) return false;
    _path.lineTo(_px, _py);
    if (!project(x2, y2, z2)) return false;
    _path.lineTo(_px, _py);
    if (!project(x3, y3, z3)) return false;
    _path.lineTo(_px, _py);
    _path.close();
    return true;
  }

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
    if (_quadPath(x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3)) canvas.drawPath(_path, _fill(color));
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

  void _seg(Canvas canvas, double x0, double y0, double z0, double x1, double y1, double z1, Color color, double w) {
    if (!project(x0, y0, z0)) return;
    final ax = _px, ay = _py;
    if (!project(x1, y1, z1)) return;
    canvas.drawLine(Offset(ax, ay), Offset(_px, _py), _line(color, w * _ps));
  }

  // --------------------------------------------------------------- buildings

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
    if (_cx > w.right) {
      _quad(canvas, w.right, w.top, 0, w.right, w.bottom, 0, w.right, w.bottom, h, w.right, w.top, h, side);
    } else if (_cx < w.left) {
      _quad(canvas, w.left, w.top, 0, w.left, w.bottom, 0, w.left, w.bottom, h, w.left, w.top, h, side);
    }
    _quad(canvas, w.left, w.bottom, 0, w.right, w.bottom, 0, w.right, w.bottom, h, w.left, w.bottom, h, front);

    final isFront = (w.bottom - bld.rect.bottom).abs() < 1; // outer south wall: the face we see most
    if (!inside && w.width > 30 && project(w.center.dx, w.bottom, h * 0.5) && _ps > 0.42) {
      // Base shadow strip (ambient occlusion) and a lighter cap line.
      _quad(
        canvas,
        w.left,
        w.bottom,
        0,
        w.right,
        w.bottom,
        0,
        w.right,
        w.bottom,
        h * 0.12,
        w.left,
        w.bottom,
        h * 0.12,
        Color.fromRGBO(0, 0, 0, 0.18 * alpha),
      );
      _wallDetail(canvas, bld, w, h, alpha, isFront);
    }
    _quad(canvas, w.left, w.top, h, w.right, w.top, h, w.right, w.bottom, h, w.left, w.bottom, h, top);
  }

  /// Windows, planks or shop shutters on a south-facing wall face.
  void _wallDetail(Canvas canvas, Building bld, Rect w, double h, double alpha, bool isFront) {
    final y = w.bottom + 0.5;
    switch (bld.style) {
      case 'kampung':
      case 'forest':
        // Horizontal timber planks.
        for (var z = h * 0.18; z < h; z += 13) {
          _seg(canvas, w.left, y, z, w.right, y, z, Color.fromRGBO(60, 35, 20, 0.35 * alpha), 1.4);
        }
      case 'town':
        // Shop-house: a coloured band and shutters on the ground floor.
        _quad(
          canvas,
          w.left,
          y,
          h * 0.5,
          w.right,
          y,
          h * 0.5,
          w.right,
          y,
          h * 0.56,
          w.left,
          y,
          h * 0.56,
          bld.roofColor.withValues(alpha: 0.9 * alpha),
        );
      default:
        break;
    }
    // Windows every ~70 units.
    final n = (w.width / 70).floor();
    if (n <= 0) return;
    final gap = w.width / n;
    final glass = Color.fromRGBO(170, 215, 240, alpha);
    final frame = Color.fromRGBO(255, 255, 255, 0.85 * alpha);
    final storeys = bld.style == 'town' ? [0.62, 0.22] : [0.38];
    for (var k = 0; k < n; k++) {
      final cx = w.left + gap * (k + 0.5);
      for (final z0 in storeys) {
        final ww = math.min(gap * 0.5, 30.0), wz0 = h * z0, wz1 = h * (z0 + 0.25);
        if (bld.style == 'town' && z0 < 0.5 && isFront) {
          // Roller shutter on the shop floor.
          _quad(
            canvas,
            cx - ww * 0.7,
            y,
            wz0 - h * 0.1,
            cx + ww * 0.7,
            y,
            wz0 - h * 0.1,
            cx + ww * 0.7,
            y,
            wz1,
            cx - ww * 0.7,
            y,
            wz1,
            Color.fromRGBO(140, 150, 156, alpha),
          );
          for (var s = wz0 - h * 0.08; s < wz1; s += 7) {
            _seg(canvas, cx - ww * 0.7, y, s, cx + ww * 0.7, y, s, Color.fromRGBO(90, 100, 106, 0.5 * alpha), 1);
          }
          continue;
        }
        _quad(
          canvas,
          cx - ww / 2 - 2,
          y,
          wz0 - 2,
          cx + ww / 2 + 2,
          y,
          wz0 - 2,
          cx + ww / 2 + 2,
          y,
          wz1 + 2,
          cx - ww / 2 - 2,
          y,
          wz1 + 2,
          frame,
        );
        _quad(canvas, cx - ww / 2, y, wz0, cx + ww / 2, y, wz0, cx + ww / 2, y, wz1, cx - ww / 2, y, wz1, glass);
        // Reflection streak.
        _quad(
          canvas,
          cx - ww / 2,
          y,
          wz0 + (wz1 - wz0) * 0.55,
          cx - ww * 0.1,
          y,
          wz1,
          cx + ww * 0.05,
          y,
          wz1,
          cx - ww / 2,
          y,
          wz0 + (wz1 - wz0) * 0.75,
          Color.fromRGBO(255, 255, 255, 0.45 * alpha),
        );
      }
    }
  }

  void _drawRoof(Canvas canvas, int i, double fx, double fy) {
    final Building b = game.sim.map.buildings[i];
    final r = b.rect.inflate(7);
    final h = _heights[i] + 1;
    final ridge = h + math.min(r.width, r.height) * 0.28;
    final alpha = _occludesFocus(r.left, r.right, r.bottom, ridge, fx, fy) ? 0.35 : 1.0;
    final dark = _roofDark[i].withValues(alpha: alpha);
    final light = _roofLight[i].withValues(alpha: alpha);
    final base = b.roofColor.withValues(alpha: alpha);
    final lines = Color.fromRGBO(0, 0, 0, 0.16 * alpha);
    // Corrugated zinc for kampung/plantation, tile rows elsewhere.
    final step = (b.style == 'kampung' || b.style == 'plantation') ? 16.0 : 22.0;
    final across = b.style == 'kampung' || b.style == 'plantation';

    if (r.width >= r.height) {
      // Ridge runs east-west: north slope, gable ends, south slope.
      final c = r.center.dy;
      _quad(canvas, r.left, r.top, h, r.right, r.top, h, r.right, c, ridge, r.left, c, ridge, light);
      if (_cx > r.right) _tri(canvas, r.right, r.top, h, r.right, r.bottom, h, r.right, c, ridge, dark);
      if (_cx < r.left) _tri(canvas, r.left, r.top, h, r.left, r.bottom, h, r.left, c, ridge, dark);
      _quad(canvas, r.left, c, ridge, r.right, c, ridge, r.right, r.bottom, h, r.left, r.bottom, h, base);
      if (across) {
        for (var x = r.left + step; x < r.right; x += step) {
          _seg(canvas, x, c, ridge, x, r.bottom, h, lines, 2);
        }
      } else {
        for (var k = 1; k < 4; k++) {
          final t = k / 4;
          _seg(
            canvas,
            r.left,
            c + (r.bottom - c) * t,
            ridge + (h - ridge) * t,
            r.right,
            c + (r.bottom - c) * t,
            ridge + (h - ridge) * t,
            lines,
            1.6,
          );
        }
      }
      // Ridge cap and eave edge.
      _seg(canvas, r.left, c, ridge + 1, r.right, c, ridge + 1, dark, 4);
      _seg(canvas, r.left, r.bottom, h, r.right, r.bottom, h, dark, 3);
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
      for (var y = r.top + step; y < r.bottom; y += step) {
        _seg(canvas, r.left, y, h, c, y, ridge, lines, 1.4);
        _seg(canvas, c, y, ridge, r.right, y, h, lines, 1.4);
      }
      _tri(canvas, r.left, r.bottom, h, r.right, r.bottom, h, c, r.bottom, ridge, dark);
      _seg(canvas, c, r.top, ridge + 1, c, r.bottom, ridge + 1, dark, 4);
    }
  }

  // --------------------------------------------------------------- nature

  void _canopy(Canvas canvas, double x, double y, double z, double r, Color dark, Color mid, Color light, double a) {
    if (!project(x, y, z)) return;
    final cx = _px, cy = _py, s = _ps;
    final rr = r * s;
    canvas.drawCircle(Offset(cx + rr * 0.25, cy + rr * 0.2), rr * 0.9, _fill(dark.withValues(alpha: a)));
    canvas.drawCircle(Offset(cx - rr * 0.35, cy + rr * 0.1), rr * 0.75, _fill(dark.withValues(alpha: a)));
    canvas.drawCircle(Offset(cx, cy), rr * 0.95, _fill(mid.withValues(alpha: a)));
    canvas.drawCircle(Offset(cx - rr * 0.3, cy - rr * 0.25), rr * 0.55, _fill(light.withValues(alpha: a)));
    _sprite(canvas, _sprites.sphere, cx, cy, rr * 2.1, rr * 2.1, Color.fromRGBO(255, 255, 255, a));
  }

  void _drawObstacle(Canvas canvas, int i, double fx, double fy) {
    final o = game.sim.map.obstacles[i];
    final near = (o.x - fx).abs() < o.r * 2 + 20 && o.y > fy && o.y - fy < 110;
    final a = near ? 0.45 : 1.0;
    final t = game.clock;
    switch (o.kind) {
      case 'tree':
        const trunkH = 34.0;
        _seg(canvas, o.x, o.y, 0, o.x, o.y, trunkH, Color.fromRGBO(93, 64, 55, a), 8);
        _canopy(
          canvas,
          o.x,
          o.y,
          trunkH + o.r * 0.9,
          o.r * 1.3,
          const Color(0xFF1B5E20),
          const Color(0xFF2E7D32),
          const Color(0xFF66BB6A),
          a,
        );
      case 'palm':
        const h = 78.0;
        final sway = math.sin(t * 1.4 + o.x * 0.05) * 4;
        // Slightly curved trunk with ring marks.
        for (var k = 0; k < 3; k++) {
          final z0 = h * k / 3, z1 = h * (k + 1) / 3;
          final x0 = o.x + 8 * (k / 3) + sway * (k / 3) * (k / 3);
          final x1 = o.x + 8 * ((k + 1) / 3) + sway * ((k + 1) / 3) * ((k + 1) / 3);
          _seg(canvas, x0, o.y, z0, x1, o.y, z1, Color.fromRGBO(k.isEven ? 130 : 110, k.isEven ? 92 : 78, 64, a), 6);
        }
        final tx3 = o.x + 8 + sway;
        if (!project(tx3, o.y, h)) return;
        final tx = _px, ty = _py, ts = _ps;
        for (var k = 0; k < 7; k++) {
          final ang = k * math.pi * 2 / 7 + o.x * 0.01 + math.sin(t * 1.6 + k + o.y * 0.02) * 0.08;
          final len = o.r * 2.9;
          if (!project(tx3 + math.cos(ang) * len, o.y + math.sin(ang) * len, h - 18)) continue;
          _leaf(
            canvas,
            tx,
            ty,
            _px,
            _py,
            7 * ts,
            k.isEven ? Color.fromRGBO(46, 125, 50, a) : Color.fromRGBO(67, 160, 71, a),
          );
        }
        canvas.drawCircle(Offset(tx, ty), 5 * ts, _fill(Color.fromRGBO(109, 76, 65, a)));
        canvas.drawCircle(Offset(tx + 3 * ts, ty + 2 * ts), 3.5 * ts, _fill(Color.fromRGBO(141, 110, 99, a)));
      default:
        if (!project(o.x, o.y, o.r * 0.35)) return;
        final rr = o.r * _ps;
        final cx = _px, cy = _py;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rr * 2.1, height: rr * 1.6),
          _fill(Color.fromRGBO(118, 126, 131, a)),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx - rr * 0.2, cy - rr * 0.2), width: rr * 1.5, height: rr * 1.0),
          _fill(Color.fromRGBO(150, 158, 163, a)),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx + rr * 0.3, cy + rr * 0.35), width: rr * 0.8, height: rr * 0.35),
          _fill(Color.fromRGBO(110, 140, 80, 0.5 * a)),
        );
        _sprite(canvas, _sprites.sphere, cx, cy, rr * 2.1, rr * 1.7, Color.fromRGBO(255, 255, 255, a));
    }
  }

  /// A tapered palm frond from (x0,y0) to (x1,y1) in screen space.
  void _leaf(Canvas canvas, double x0, double y0, double x1, double y1, double width, Color color) {
    final dx = x1 - x0, dy = y1 - y0;
    final len = math.sqrt(dx * dx + dy * dy) + 0.001;
    final nx = -dy / len * width, ny = dx / len * width;
    final mx = x0 + dx * 0.45, my = y0 + dy * 0.45;
    _path.reset();
    _path.moveTo(x0, y0);
    _path.quadraticBezierTo(mx + nx, my + ny, x1, y1);
    _path.quadraticBezierTo(mx - nx, my - ny, x0, y0);
    canvas.drawPath(_path, _fill(color));
    canvas.drawLine(Offset(x0, y0), Offset(x1, y1), _line(const Color(0x33000000), 1));
  }

  void _drawTree(Canvas canvas, int i) {
    final t = game.sim.trees[i];
    final tr = game.config.trees.trunkRadius[t.stage];
    final h = 14.0 + tr * 2.2;
    _seg(canvas, t.x, t.y, 0, t.x, t.y, h, const Color(0xFF6D4C41), tr * 0.6);
    if (t.hitFlash > 0) {
      _canopy(
        canvas,
        t.x,
        t.y,
        h + tr * 1.4,
        tr * 2.0,
        const Color(0xFFFFFFFF),
        const Color(0xFFFFFFFF),
        const Color(0xFFFFFFFF),
        1,
      );
    } else {
      _canopy(
        canvas,
        t.x,
        t.y,
        h + tr * 1.4,
        tr * 2.0,
        const Color(0xFF2E7D32),
        const Color(0xFF43A047),
        const Color(0xFF9CCC65),
        1,
      );
    }
    if (t.health < t.maxHealth && project(t.x, t.y, h + tr * 3.8)) {
      _bar(canvas, _px, _py, t.health / t.maxHealth, const Color(0xFF66BB6A));
    }
  }

  void _bar(Canvas canvas, double x, double y, double frac, Color color) {
    final w = 40 * _ps, h = math.max(3.0, 5 * _ps);
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x - w / 2, y, w, h), Radius.circular(h / 2));
    canvas.drawRRect(r.inflate(1), _fill(const Color(0xAA000000)));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x - w / 2, y, w * frac.clamp(0, 1), h), Radius.circular(h / 2)),
      _fill(color),
    );
  }

  // --------------------------------------------------------------- characters

  void _drawActor(Canvas canvas, Actor a) {
    const r = Actor.radius;
    const z = r;
    final cos = math.cos(a.aimAngle), sin = math.sin(a.aimAngle);
    final w = a.weapon;
    final behind = sin < 0; // aiming away from the camera: gun is behind the body
    final firing = game.sim.time - game.lastShot[a.id] < 0.08;

    void gun() {
      if (w != null) {
        final len = 18.0 + w.stats.rank * 5;
        final width = 6.0 + w.stats.rank * 2;
        final darker = Color.lerp(w.stats.color, const Color(0xFF000000), 0.35)!;
        // Barrel, then a round water tank on top.
        _seg(
          canvas,
          a.pos.x + cos * 6,
          a.pos.y + sin * 6,
          z - 2,
          a.pos.x + cos * (r + len),
          a.pos.y + sin * (r + len),
          z - 2,
          darker,
          width + 2,
        );
        _seg(
          canvas,
          a.pos.x + cos * 6,
          a.pos.y + sin * 6,
          z - 1,
          a.pos.x + cos * (r + len),
          a.pos.y + sin * (r + len),
          z - 1,
          w.stats.color,
          width,
        );
        if (project(a.pos.x + cos * (r + 4), a.pos.y + sin * (r + 4), z + 6)) {
          final tr = (5 + w.stats.rank * 1.5) * _ps;
          canvas.drawCircle(Offset(_px, _py), tr, _fill(Color.lerp(w.stats.color, const Color(0xFFFFFFFF), 0.45)!));
          canvas.drawCircle(Offset(_px - tr * 0.3, _py - tr * 0.3), tr * 0.35, _fill(const Color(0xAAFFFFFF)));
        }
        if (firing && project(a.pos.x + cos * (r + len + 6), a.pos.y + sin * (r + len + 6), z - 1)) {
          _sprite(canvas, _sprites.glow, _px, _py, 40 * _ps, 40 * _ps, w.stats.color, additive: true);
        }
      }
      for (final side in const [-1.0, 1.0]) {
        if (project(a.pos.x + cos * r * 0.9 - sin * 9 * side, a.pos.y + sin * r * 0.9 + cos * 9 * side, z - 3)) {
          canvas.drawCircle(Offset(_px, _py), 6 * _ps, _fill(Color.lerp(a.color, const Color(0xFFFFE0B2), 0.55)!));
          canvas.drawCircle(Offset(_px, _py), 6 * _ps, _line(const Color(0x55000000), 1.5 * _ps));
        }
      }
    }

    if (behind) gun();
    if (!project(a.pos.x, a.pos.y, z)) return;
    final o = Offset(_px, _py);
    final ps = _ps;
    final rr = r * ps;
    if (a.hitFlash > 0) {
      canvas.drawCircle(o, rr, _fill(const Color(0xFFFFFFFF)));
    } else {
      canvas.drawCircle(o, rr, _fill(a.color));
      // Cap / hair, offset towards the facing direction.
      canvas.drawCircle(
        o.translate(-cos * rr * 0.15, -rr * 0.25 - sin * rr * 0.1),
        rr * 0.62,
        _fill(Color.lerp(a.color, const Color(0xFF000000), 0.35)!),
      );
      _sprite(canvas, _sprites.sphere, o.dx, o.dy, rr * 2, rr * 2, const Color(0xFFFFFFFF));
    }
    if (a.armour > 0) {
      canvas.drawCircle(
        o,
        rr - 3 * ps,
        _line(a.vest?.tier == 2 ? const Color(0xFF1565C0) : const Color(0xFF90CAF9), 4 * ps),
      );
    }
    canvas.drawCircle(
      o,
      rr,
      _line(a.isPlayer ? const Color(0xFFFFFFFF) : const Color(0x99000000), (a.isPlayer ? 3.5 : 2) * ps),
    );
    if (a.hazeShield > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: o.translate(0, rr * 0.3), width: 16 * ps, height: 8 * ps),
          Radius.circular(3 * ps),
        ),
        _fill(const Color(0xFFECEFF1)),
      );
    }
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
    if (!project(p.x - p.vx * 0.03, p.y - p.vy * 0.03, 16)) return;
    final tx = _px, ty = _py;
    if (!project(p.x, p.y, 16)) return;
    final o = Offset(_px, _py);
    final pr = w.projectileRadius * _ps;
    canvas.drawLine(Offset(tx, ty), o, _line(w.color.withValues(alpha: 0.35), pr * 1.6));
    _sprite(canvas, _sprites.glow, o.dx, o.dy, pr * 6, pr * 6, w.color.withValues(alpha: 0.8), additive: true);
    canvas.drawCircle(o, pr, _fill(w.color));
    canvas.drawCircle(o.translate(-pr * 0.35, -pr * 0.35), pr * 0.4, _fill(const Color(0xDDFFFFFF)));
  }

  void _drawLoot(Canvas canvas, LootItem l) {
    final bob = 12 + math.sin(game.clock * 3 + l.x * 0.1) * 4;
    if (!project(l.x, l.y, bob)) return;
    final s = _ps;
    final o = Offset(_px, _py);
    final color = _lootColor(l);
    canvas.drawCircle(o, 15 * s, _fill(const Color(0xF2FFFFFF)));
    canvas.drawCircle(o, 15 * s, _line(color, 3 * s));
    RRect box(double w, double h, double rad) =>
        RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: w * s, height: h * s), Radius.circular(rad * s));
    switch (l.kind) {
      case LootKind.weapon:
        canvas.drawRRect(box(20, 8, 3), _fill(color));
        canvas.drawCircle(o.translate(-4 * s, -5 * s), 4 * s, _fill(Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!));
      case LootKind.armour:
        canvas.drawRRect(box(14, 16, 5), _fill(color));
        canvas.drawLine(o.translate(0, -6 * s), o.translate(0, 6 * s), _line(const Color(0x66FFFFFF), 2 * s));
      case LootKind.water:
        canvas.drawRRect(box(8, 16, 3), _fill(color));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: o.translate(0, -9 * s), width: 4 * s, height: 3 * s),
            Radius.circular(1 * s),
          ),
          _fill(const Color(0xFF1565C0)),
        );
      case LootKind.mask:
        canvas.drawRRect(box(16, 10, 4), _fill(color));
        canvas.drawLine(o.translate(-8 * s, 0), o.translate(-12 * s, -3 * s), _line(color, 1.5 * s));
        canvas.drawLine(o.translate(8 * s, 0), o.translate(12 * s, -3 * s), _line(color, 1.5 * s));
      case LootKind.seed:
        canvas.drawCircle(o.translate(0, 3 * s), 5 * s, _fill(const Color(0xFF795548)));
        canvas.drawOval(
          Rect.fromCenter(center: o.translate(3 * s, -4 * s), width: 10 * s, height: 6 * s),
          _fill(color),
        );
        canvas.drawOval(
          Rect.fromCenter(center: o.translate(-3 * s, -3 * s), width: 7 * s, height: 4 * s),
          _fill(const Color(0xFF81C784)),
        );
    }
  }

  // --------------------------------------------------------------- particles

  void _drawFxParticles(Canvas canvas, Rect cull) {
    for (final p in game.fx.particles) {
      if (!p!.active || !cull.contains(Offset(p.x, p.y))) continue;
      if (!project(p.x, p.y, p.z)) continue;
      final t = p.life / p.maxLife;
      final s = _ps;
      final c = Color(p.color);
      switch (p.kind) {
        case FxKind.droplet:
          canvas.drawCircle(Offset(_px, _py), p.size * s, _fill(c.withValues(alpha: 0.9 * t + 0.1)));
        case FxKind.dust:
          _sprite(canvas, _sprites.puff, _px, _py, p.size * 2 * s, p.size * 1.4 * s, c.withValues(alpha: 0.5 * t));
        case FxKind.leaf:
          canvas.save();
          canvas.translate(_px, _py);
          canvas.rotate(p.spin);
          canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: p.size * 2 * s, height: p.size * s),
            _fill(c.withValues(alpha: math.min(1, t * 2))),
          );
          canvas.restore();
        case FxKind.sparkle:
          _sprite(
            canvas,
            _sprites.glow,
            _px,
            _py,
            p.size * 4 * s,
            p.size * 4 * s,
            c.withValues(alpha: t),
            additive: true,
          );
        case FxKind.muzzle:
          _sprite(
            canvas,
            _sprites.glow,
            _px,
            _py,
            p.size * 3 * s,
            p.size * 3 * s,
            c.withValues(alpha: t),
            additive: true,
          );
      }
    }
  }

  // --------------------------------------------------------------- haze

  static final _hazePaint = Paint()..color = const Color(0x99A8784A);
  static const _hazeEdge = Color(0xFF9C7A55);

  void _drawHaze(Canvas canvas, Rect visible) {
    final z = game.sim.zone;
    final fx = math.max((visible.left - z.cx).abs(), (visible.right - z.cx).abs());
    final fy = math.max((visible.top - z.cy).abs(), (visible.bottom - z.cy).abs());
    if (fx * fx + fy * fy < z.r * z.r) return;
    canvas.saveLayer(null, Paint());
    canvas.transform(_m);
    canvas.drawRect(visible.inflate(50), _hazePaint);
    if (z.r > 0) {
      canvas.drawCircle(Offset(z.cx, z.cy), z.r, _clear);
      // Feathered edge: thicker haze right at the boundary.
      canvas.drawCircle(Offset(z.cx, z.cy), z.r + 18, _line(const Color(0x33A8784A), 36));
    }
    for (final t in game.sim.trees) {
      if (t.alive && t.bubble > 0) canvas.drawCircle(Offset(t.x, t.y), t.bubble, _clear);
    }
    canvas.restore();
  }

  /// The edge of the safe zone rises as a billowing wall of smoke.
  void _drawHazeWall(Canvas canvas, Rect cull) {
    final z = game.sim.zone;
    if (z.r <= 0) return;
    final segments = (2 * math.pi * z.r / 90).clamp(24, 140).round();
    const h = 110.0;
    final t = game.clock;
    for (var k = 0; k < segments; k++) {
      final a0 = k / segments * math.pi * 2, a1 = (k + 1) / segments * math.pi * 2;
      final x0 = z.cx + math.cos(a0) * z.r, y0 = z.cy + math.sin(a0) * z.r;
      final x1 = z.cx + math.cos(a1) * z.r, y1 = z.cy + math.sin(a1) * z.r;
      if (!cull.contains(Offset(x0, y0)) && !cull.contains(Offset(x1, y1))) continue;
      _quad(canvas, x0, y0, 0, x1, y1, 0, x1, y1, h * 0.7, x0, y0, h * 0.7, const Color(0x2EB07A45));
      for (final zz in segments > 70 ? const [48.0] : const [26.0, 70.0]) {
        final wob = math.sin(t * 0.9 + k * 1.7 + zz) * 10;
        if (!project(x0, y0, zz + wob)) continue;
        final size = (110 + (k % 3) * 25) * _ps;
        _sprite(canvas, _sprites.puff, _px, _py, size * 1.4, size, _hazeEdge.withValues(alpha: 0.75));
      }
      if (project(x0, y0, 2)) {
        final px = _px, py = _py;
        if (project(x1, y1, 2)) canvas.drawLine(Offset(px, py), Offset(_px, _py), _line(const Color(0xAAFF8A3D), 3));
      }
    }
  }

  /// Drifting smoke clouds inside the haze.
  void _drawHazeSmoke(Canvas canvas) {
    final sim = game.sim;
    for (final p in game.particles) {
      if (sim.isSafeAt(p.x, p.y)) continue;
      if (!project(p.x, p.y, 30)) continue;
      final life = p.life / p.maxLife;
      final a = math.min(1.0, math.min(life * 3, (1 - life) * 3)) * 0.55;
      final s = p.size * _ps;
      _sprite(canvas, _sprites.puff, _px, _py, s * 1.6, s, Color.fromRGBO(120, 95, 70, a));
    }
  }

  // --------------------------------------------------------------- screen

  /// Distance fog, corner vignette and damage / haze flashes.
  void drawScreenEffects(Canvas canvas) {
    final g = game;
    final rect = Rect.fromLTWH(0, 0, g.viewW, g.viewH);
    final sim = g.sim;

    // Distance fog: the far (top) part of the view fades into hazy air,
    // thicker as the haze phases progress.
    final strength = (0.22 + 0.06 * sim.zone.phaseIndex).clamp(0.0, 0.5);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, g.viewW, g.viewH * 0.5),
      Paint()
        ..shader = Gradient.linear(Offset.zero, Offset(0, g.viewH * 0.5), [
          Color.fromRGBO(196, 170, 135, strength),
          const Color(0x00C4AA87),
        ]),
    );
    // Warm sunlight tint.
    canvas.drawRect(rect, _fill(const Color(0x0DFFB74D)));
    canvas.drawRect(
      rect,
      _cornerVignette ??= Paint()
        ..shader = Gradient.radial(
          rect.center,
          rect.longestSide * 0.62,
          [const Color(0x00000000), const Color(0x00000000), const Color(0x55000000)],
          [0.0, 0.6, 1.0],
        ),
    );

    final p = sim.player;
    if (!p.alive || sim.phase != MatchPhase.running) return;
    final inHaze = !sim.isSafeAt(p.pos.x, p.pos.y);
    if (!inHaze && g.hurtTimer <= 0) return;
    final color = g.hurtTimer > 0 ? const Color(0x88D32F2F) : const Color(0x998D6E3A);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.radial(rect.center, rect.longestSide * 0.6, [const Color(0x00000000), color], [0.55, 1.0]),
    );
  }
}
