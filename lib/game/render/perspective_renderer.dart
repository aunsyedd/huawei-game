import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../components/actor.dart';
import '../components/building.dart';
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
/// matrix, upright things are projected point by point and painted
/// back-to-front. World axes: x right, y towards the camera (south), z up.
///
/// Performance: repeated objects are single blits from [Sprites.atlas]; groups
/// (splats, shadows, smoke, droplets, glows) are batched into one
/// `drawRawAtlas` each; [HazeRoyaleGame.quality] drops extras on slow devices.
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
    for (var i = 0; i < 900; i++) {
      _pool.add(_Item());
    }
  }

  final HazeRoyaleGame game;
  final Image _atlas = Sprites.instance.atlas;

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
  final Path _path2 = Path();
  final Paint _p = Paint();
  final Paint _s = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _img = Paint()..filterQuality = FilterQuality.low;
  final Paint _additive = Paint()
    ..filterQuality = FilterQuality.low
    ..blendMode = BlendMode.plus;

  // Batches (one draw call each).
  final AtlasBatch _groundShadows = AtlasBatch(160);
  final AtlasBatch _groundDecals = AtlasBatch(180);
  final AtlasBatch _groundGlows = AtlasBatch(200);
  final AtlasBatch _overlayTinted = AtlasBatch(600);
  final AtlasBatch _overlayGlows = AtlasBatch(500);
  final Float32List _one4 = Float32List(4), _oneRect = Float32List(4);
  final Int32List _oneColor = Int32List(1);

  Paint? _vignette;
  double _vignetteFor = -1;

  Paint _fill(Color c) => _p..color = c;
  Paint _line(Color c, double w) => _s
    ..color = c
    ..strokeWidth = w;

  void onResize() => _vignette = null;

  int get _q => game.quality;

  static int _argb(double a, int rgb) => ((a.clamp(0.0, 1.0) * 255).round() << 24) | (rgb & 0xFFFFFF);

  /// One sprite from the atlas at a screen point (keeps depth order).
  void _blit(Canvas c, Rect src, double cx, double cy, double width, {double alpha = 1, double rot = 0}) {
    if (rot == 0 && alpha >= 1) {
      final h = width * src.height / src.width;
      c.drawImageRect(_atlas, src, Rect.fromCenter(center: Offset(cx, cy), width: width, height: h), _img);
      return;
    }
    final scale = width / src.width;
    final scos = math.cos(rot) * scale, ssin = math.sin(rot) * scale;
    _one4
      ..[0] = scos
      ..[1] = ssin
      ..[2] = cx - scos * src.width / 2 + ssin * src.height / 2
      ..[3] = cy - ssin * src.width / 2 - scos * src.height / 2;
    _oneRect
      ..[0] = src.left
      ..[1] = src.top
      ..[2] = src.right
      ..[3] = src.bottom;
    _oneColor[0] = _argb(alpha, 0xFFFFFF);
    c.drawRawAtlas(_atlas, _one4, _oneRect, _oneColor, BlendMode.modulate, null, _img);
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
    if (!running) {
      canvas.restore();
      return; // The landing map covers the screen; skip the 3D world.
    }
    _drawTreeBubbles(canvas, cull);
    _groundBatches(canvas, cull);
    g.drawEffects(canvas, cull);
    g.drawZoneLines(canvas);
    g.drawAimLine(canvas);
    canvas.restore();

    // Upright things, back to front.
    _collect(cull);
    final f = sim.focus.pos;
    for (final it in _draw) {
      switch (it.kind) {
        case 0:
          _drawObstacle(canvas, it.index, f.x, f.y);
        case 1:
          _drawWall(canvas, it.index, f.x, f.y);
        case 2:
          _drawRoof(canvas, it.index, f.x, f.y);
        case 3:
          _drawActor(canvas, sim.actors[it.index]);
        case 4:
          _drawTree(canvas, it.index);
        case 5:
          _drawProjectile(canvas, it.index);
        case 6:
          _drawLoot(canvas, it.index);
      }
    }

    _drawHaze(canvas, visible);
    _drawHazeWall(canvas, cull);
    if (_q >= 2) _addHazeSmoke();
    _addFxParticles(cull);
    _overlayTinted.draw(canvas, _atlas, _img);
    _overlayGlows.draw(canvas, _atlas, _additive);
  }

  void _add(int kind, int index, double key) {
    if (_used >= _pool.length) _pool.add(_Item());
    final it = _pool[_used++]
      ..kind = kind
      ..index = index
      ..key = key;
    _draw.add(it);
  }

  void _collect(Rect cull) {
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
      // No roof over the building the camera's player is in (cutaway view).
      if (b.rect.overlaps(cull) && !b.contains(f.x, f.y)) _add(2, i, b.rect.bottom + 0.5);
    }
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
    _draw.sort((a, b) => a.key.compareTo(b.key));
  }

  /// See-through when this object sits between the camera and the player.
  bool _occludesFocus(double l, double r, double bottom, double height, double fx, double fy) =>
      fx > l - 30 && fx < r + 30 && fy < bottom && fy > bottom - height * 2.2 - 40;

  // --------------------------------------------------------------- ground layer

  /// Animated foam lines where the sea meets the island.
  void _drawSea(Canvas canvas, Rect visible) {
    final map = game.sim.map;
    final t = game.clock;
    if (visible.left > 30 && visible.right < map.width - 30 && visible.top > 30 && visible.bottom < map.height - 30) {
      return; // no shoreline in view
    }
    for (var k = 0; k < 2; k++) {
      final off = 14.0 + k * 22 + math.sin(t * 1.3 + k) * 6;
      final paint = _line(Color.fromRGBO(255, 255, 255, k == 0 ? 0.75 : 0.35), k == 0 ? 6 : 4);
      _wavyEdge(canvas, visible, paint, map.width, (x) => Offset(x, map.height + off + math.sin(x / 45 + t * 2) * 4));
      _wavyEdge(canvas, visible, paint, map.width, (x) => Offset(x, -off - math.sin(x / 50 + t * 2) * 4));
      _wavyEdge(canvas, visible, paint, map.height, (y) => Offset(-off - math.sin(y / 50 + t * 2) * 4, y));
      _wavyEdge(canvas, visible, paint, map.height, (y) => Offset(map.width + off + math.sin(y / 50 + t * 2) * 4, y));
    }
  }

  void _wavyEdge(Canvas canvas, Rect visible, Paint paint, double to, Offset Function(double) at) {
    final start = at(0), end = at(to);
    if (!Rect.fromPoints(start, end).inflate(40).overlaps(visible)) return;
    final horizontal = (end.dx - start.dx).abs() > (end.dy - start.dy).abs();
    final a = math.max(0.0, horizontal ? visible.left : visible.top);
    final b = math.min(to, horizontal ? visible.right : visible.bottom);
    if (b <= a) return;
    _path.reset();
    var first = true;
    for (var v = a; v <= b; v += 30) {
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

  void _drawTreeBubbles(Canvas canvas, Rect cull) {
    final t = game.clock;
    for (final tree in game.sim.trees) {
      if (!tree.alive || tree.bubble <= 0) continue;
      final o = Offset(tree.x, tree.y);
      if (!cull.inflate(tree.bubble).contains(o)) continue;
      canvas.drawCircle(o, tree.bubble, _fill(const Color(0x2481C784)));
      canvas.drawCircle(o, tree.bubble, _line(const Color(0xBB7CDB80), 4));
      if (_q >= 2) {
        final pr = tree.bubble * (0.55 + 0.45 * ((t * 0.5 + tree.x * 0.001) % 1));
        canvas.drawCircle(o, pr, _line(Color.fromRGBO(200, 255, 200, 0.35 * (1 - pr / tree.bubble)), 3));
      }
    }
  }

  /// Splats, soft shadows and loot glows: three draw calls in total.
  void _groundBatches(Canvas canvas, Rect cull) {
    final sim = game.sim;
    final maxDecals = _q >= 2 ? 160 : 60;
    var decals = 0;
    for (final d in game.fx.decals) {
      if (!d!.active || !cull.contains(Offset(d.x, d.y)) || decals >= maxDecals) continue;
      decals++;
      final fade = (1 - d.age / FxSystem.decalLife).clamp(0.0, 1.0);
      _groundDecals.add(Sprites.splats[d.variant], d.x, d.y, d.size, _argb(0.55 * fade, d.color), d.rot);
    }
    for (final a in sim.actors) {
      if (!a.alive || !cull.contains(Offset(a.pos.x, a.pos.y))) continue;
      _groundShadows.add(Sprites.shadowOval, a.pos.x + 7, a.pos.y + 6, 56, 0xFFFFFFFF);
    }
    for (final t in sim.trees) {
      if (!t.alive || !cull.contains(Offset(t.x, t.y))) continue;
      final r = game.config.trees.trunkRadius[t.stage] * 2.4;
      _groundShadows.add(Sprites.shadowOval, t.x + r * 0.5, t.y + r * 0.3, r * 2.8, 0xFFFFFFFF);
    }
    final t = game.clock;
    for (final l in sim.loot) {
      if (l.taken || !cull.contains(Offset(l.x, l.y))) continue;
      final color = Sprites.lootColors[Sprites.lootIcon(l.refId)];
      final pulse = 1 + math.sin(t * 3 + l.x) * 0.12;
      _groundGlows.add(Sprites.glow, l.x, l.y, 64 * pulse, _argb(0.5, color.toARGB32()));
      _groundShadows.add(Sprites.shadowOval, l.x + 3, l.y + 3, 30, 0xFFFFFFFF);
    }
    _groundDecals.draw(canvas, _atlas, _img);
    _groundShadows.draw(canvas, _atlas, _img);
    _groundGlows.draw(canvas, _atlas, _additive);

    final p = sim.player;
    if (p.alive) {
      final pulse = 1 + math.sin(t * 4) * 0.06;
      canvas.drawCircle(Offset(p.pos.x, p.pos.y), 28 * pulse, _line(const Color(0xAA4FC3F7), 3));
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
    Canvas c,
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
    if (_quadPath(x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3)) c.drawPath(_path, _fill(color));
  }

  /// Vertical face along x at depth y (a south-facing wall face).
  void _faceY(Canvas c, double x0, double x1, double y, double z0, double z1, Color color) =>
      _quad(c, x0, y, z0, x1, y, z0, x1, y, z1, x0, y, z1, color);

  /// Vertical face along y at x (an east/west wall face).
  void _faceX(Canvas c, double x, double y0, double y1, double z0, double z1, Color color) =>
      _quad(c, x, y0, z0, x, y1, z0, x, y1, z1, x, y0, z1, color);

  void _tri(
    Canvas c,
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
    c.drawPath(_path, _fill(color));
  }

  void _seg(Canvas c, double x0, double y0, double z0, double x1, double y1, double z1, Color color, double w) {
    if (!project(x0, y0, z0)) return;
    final ax = _px, ay = _py;
    if (!project(x1, y1, z1)) return;
    c.drawLine(Offset(ax, ay), Offset(_px, _py), _line(color, w * _ps));
  }

  // --------------------------------------------------------------- buildings

  void _drawWall(Canvas canvas, int i, double fx, double fy) {
    final w = game.sim.map.walls[i];
    final b = _wallBuilding[i];
    final bld = game.sim.map.buildings[b];
    final inside = bld.contains(fx, fy);
    final h = inside ? 22.0 : _heights[b];
    final alpha = !inside && _occludesFocus(bld.rect.left, bld.rect.right, bld.rect.bottom, h, fx, fy) ? 0.4 : 1.0;
    if (_cx > w.right) {
      _faceX(canvas, w.right, w.top, w.bottom, 0, h, _wallSide[b].withValues(alpha: alpha));
    } else if (_cx < w.left) {
      _faceX(canvas, w.left, w.top, w.bottom, 0, h, _wallSide[b].withValues(alpha: alpha));
    }
    _faceY(canvas, w.left, w.right, w.bottom, 0, h, _wallFront[b].withValues(alpha: alpha));
    if (_q >= 1 && !inside && w.width > 30 && project(w.center.dx, w.bottom, h * 0.5) && _ps > 0.42) {
      _faceY(canvas, w.left, w.right, w.bottom, 0, h * 0.12, Color.fromRGBO(0, 0, 0, 0.18 * alpha));
      if (_q >= 2) _wallDetail(canvas, bld, w, h, alpha, (w.bottom - bld.rect.bottom).abs() < 1);
    }
    _quad(
      canvas,
      w.left,
      w.top,
      h,
      w.right,
      w.top,
      h,
      w.right,
      w.bottom,
      h,
      w.left,
      w.bottom,
      h,
      _wallTop[b].withValues(alpha: alpha),
    );
  }

  /// Windows, planks or shop shutters on a south-facing wall face.
  void _wallDetail(Canvas c, Building bld, Rect w, double h, double alpha, bool isFront) {
    final y = w.bottom + 0.5;
    switch (bld.style) {
      case 'kampung':
      case 'forest':
        for (var z = h * 0.18; z < h; z += 13) {
          _seg(c, w.left, y, z, w.right, y, z, Color.fromRGBO(60, 35, 20, 0.35 * alpha), 1.4);
        }
      case 'town':
        _faceY(c, w.left, w.right, y, h * 0.5, h * 0.56, bld.roofColor.withValues(alpha: 0.9 * alpha));
      default:
        break;
    }
    final n = (w.width / 70).floor();
    if (n <= 0) return;
    final gap = w.width / n;
    final glass = Color.fromRGBO(170, 215, 240, alpha);
    final frame = Color.fromRGBO(255, 255, 255, 0.85 * alpha);
    final shine = Color.fromRGBO(255, 255, 255, 0.4 * alpha);
    final storeys = bld.style == 'town' ? const [0.62, 0.22] : const [0.38];
    for (var k = 0; k < n; k++) {
      final cx = w.left + gap * (k + 0.5);
      final ww = math.min(gap * 0.5, 30.0);
      for (final z0 in storeys) {
        final wz0 = h * z0, wz1 = h * (z0 + 0.25);
        if (bld.style == 'town' && z0 < 0.5 && isFront) {
          // Roller shutter on the shop floor.
          _faceY(c, cx - ww * 0.7, cx + ww * 0.7, y, wz0 - h * 0.1, wz1, Color.fromRGBO(140, 150, 156, alpha));
          _seg(
            c,
            cx - ww * 0.7,
            y,
            (wz0 + wz1) / 2,
            cx + ww * 0.7,
            y,
            (wz0 + wz1) / 2,
            Color.fromRGBO(90, 100, 106, 0.6 * alpha),
            1.5,
          );
          continue;
        }
        _faceY(c, cx - ww / 2 - 2, cx + ww / 2 + 2, y, wz0 - 2, wz1 + 2, frame);
        _faceY(c, cx - ww / 2, cx + ww / 2, y, wz0, wz1, glass);
        _faceY(c, cx - ww / 2, cx - ww * 0.15, y, wz0 + (wz1 - wz0) * 0.5, wz1, shine);
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
    final corrugated = b.style == 'kampung' || b.style == 'plantation';
    final step = corrugated ? 16.0 : 22.0;
    final detail = _q >= 2;

    if (r.width >= r.height) {
      // Ridge runs east-west: north slope, gable ends, south slope.
      final c = r.center.dy;
      _quad(canvas, r.left, r.top, h, r.right, r.top, h, r.right, c, ridge, r.left, c, ridge, light);
      if (_cx > r.right) _tri(canvas, r.right, r.top, h, r.right, r.bottom, h, r.right, c, ridge, dark);
      if (_cx < r.left) _tri(canvas, r.left, r.top, h, r.left, r.bottom, h, r.left, c, ridge, dark);
      _quad(canvas, r.left, c, ridge, r.right, c, ridge, r.right, r.bottom, h, r.left, r.bottom, h, base);
      if (detail) {
        if (corrugated) {
          for (var x = r.left + step; x < r.right; x += step) {
            _seg(canvas, x, c, ridge, x, r.bottom, h, lines, 2);
          }
        } else {
          for (var k = 1; k < 4; k++) {
            final t = k / 4;
            final yy = c + (r.bottom - c) * t, zz = ridge + (h - ridge) * t;
            _seg(canvas, r.left, yy, zz, r.right, yy, zz, lines, 1.6);
          }
        }
      }
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
      if (detail) {
        for (var y = r.top + step; y < r.bottom; y += step) {
          _seg(canvas, r.left, y, h, c, y, ridge, lines, 1.4);
          _seg(canvas, c, y, ridge, r.right, y, h, lines, 1.4);
        }
      }
      _tri(canvas, r.left, r.bottom, h, r.right, r.bottom, h, c, r.bottom, ridge, dark);
      _seg(canvas, c, r.top, ridge + 1, c, r.bottom, ridge + 1, dark, 4);
    }
  }

  // --------------------------------------------------------------- nature

  void _drawObstacle(Canvas canvas, int i, double fx, double fy) {
    final o = game.sim.map.obstacles[i];
    final near = (o.x - fx).abs() < o.r * 2 + 20 && o.y > fy && o.y - fy < 110;
    final a = near ? 0.45 : 1.0;
    switch (o.kind) {
      case 'tree':
        const trunkH = 34.0;
        _seg(canvas, o.x, o.y, 0, o.x, o.y, trunkH, Color.fromRGBO(93, 64, 55, a), 8);
        if (project(o.x, o.y, trunkH + o.r * 0.9)) {
          _blit(canvas, Sprites.canopy, _px, _py, o.r * 3.6 * _ps, alpha: a);
        }
      case 'palm':
        const h = 78.0;
        final sway = math.sin(game.clock * 1.4 + o.x * 0.05) * 4;
        _seg(canvas, o.x, o.y, 0, o.x + 3 + sway * 0.25, o.y, h * 0.5, Color.fromRGBO(130, 92, 64, a), 6);
        _seg(canvas, o.x + 3 + sway * 0.25, o.y, h * 0.5, o.x + 8 + sway, o.y, h, Color.fromRGBO(110, 78, 64, a), 5.5);
        if (project(o.x + 8 + sway, o.y, h - 6)) {
          final rot = o.x * 0.01 + math.sin(game.clock * 1.6 + o.y * 0.02) * 0.06;
          _blit(canvas, Sprites.palmCrown, _px, _py, o.r * 6.2 * _ps, alpha: a, rot: rot);
        }
      default:
        if (project(o.x, o.y, o.r * 0.35)) _blit(canvas, Sprites.rock, _px, _py, o.r * 2.2 * _ps, alpha: a);
    }
  }

  void _drawTree(Canvas canvas, int i) {
    final t = game.sim.trees[i];
    final tr = game.config.trees.trunkRadius[t.stage];
    final h = 14.0 + tr * 2.2;
    _seg(canvas, t.x, t.y, 0, t.x, t.y, h, const Color(0xFF6D4C41), tr * 0.6);
    if (!project(t.x, t.y, h + tr * 1.4)) return;
    final size = tr * 5.6 * _ps;
    _blit(canvas, Sprites.sapling, _px, _py, size);
    if (t.hitFlash > 0) canvas.drawCircle(Offset(_px, _py), size * 0.36, _fill(const Color(0xAAFFFFFF)));
    if (t.health < t.maxHealth && project(t.x, t.y, h + tr * 3.8)) {
      _bar(canvas, _px, _py, t.health / t.maxHealth, const Color(0xFF66BB6A));
    }
  }

  void _bar(Canvas canvas, double x, double y, double frac, Color color) {
    final w = 40 * _ps, h = math.max(3.0, 5 * _ps);
    canvas.drawRect(Rect.fromLTWH(x - w / 2 - 1, y - 1, w + 2, h + 2), _fill(const Color(0xAA000000)));
    canvas.drawRect(Rect.fromLTWH(x - w / 2, y, w * frac.clamp(0, 1), h), _fill(color));
  }

  // --------------------------------------------------------------- characters

  void _drawActor(Canvas canvas, Actor a) {
    const r = Actor.radius;
    const z = r;
    final cos = math.cos(a.aimAngle), sin = math.sin(a.aimAngle);
    final w = a.weapon;
    final behind = sin < 0; // aiming away from the camera: gun is behind the body
    final skin = Color.lerp(a.color, const Color(0xFFFFE0B2), 0.55)!;

    void gun() {
      if (w != null) {
        final len = 18.0 + w.stats.rank * 5;
        final width = 6.0 + w.stats.rank * 2;
        final ex = a.pos.x + cos * (r + len), ey = a.pos.y + sin * (r + len);
        _seg(canvas, a.pos.x + cos * 6, a.pos.y + sin * 6, z - 1, ex, ey, z - 1, w.stats.color, width);
        if (project(a.pos.x + cos * (r + 4), a.pos.y + sin * (r + 4), z + 6)) {
          canvas.drawCircle(
            Offset(_px, _py),
            (5 + w.stats.rank * 1.5) * _ps,
            _fill(Color.lerp(w.stats.color, const Color(0xFFFFFFFF), 0.45)!),
          );
        }
        if (game.sim.time - game.lastShot[a.id] < 0.08 && project(ex + cos * 6, ey + sin * 6, z - 1)) {
          _overlayGlows.add(Sprites.glow, _px, _py, 40 * _ps, w.stats.color.toARGB32());
        }
      }
      for (final side in const [-1.0, 1.0]) {
        if (project(a.pos.x + cos * r * 0.9 - sin * 9 * side, a.pos.y + sin * r * 0.9 + cos * 9 * side, z - 3)) {
          canvas.drawCircle(Offset(_px, _py), 6 * _ps, _fill(skin));
        }
      }
    }

    if (behind) gun();
    if (!project(a.pos.x, a.pos.y, z)) return;
    final o = Offset(_px, _py);
    final ps = _ps;
    final rr = r * ps;
    final bodyIndex = a.isPlayer ? 0 : 1 + (a.id - 1) % 8;
    _blit(canvas, Sprites.body(bodyIndex), o.dx, o.dy, rr * 2 / 0.84);
    if (a.hitFlash > 0) canvas.drawCircle(o, rr, _fill(const Color(0xCCFFFFFF)));
    if (a.armour > 0) {
      canvas.drawCircle(
        o,
        rr - 3 * ps,
        _line(a.vest?.tier == 2 ? const Color(0xFF1565C0) : const Color(0xFF90CAF9), 4 * ps),
      );
    }
    if (a.hazeShield > 0) {
      canvas.drawRect(
        Rect.fromCenter(center: o.translate(0, rr * 0.3), width: 16 * ps, height: 7 * ps),
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
    final pr = w.projectileRadius * _ps;
    canvas.drawLine(Offset(tx, ty), Offset(_px, _py), _line(w.color.withValues(alpha: 0.4), pr * 1.6));
    canvas.drawCircle(Offset(_px, _py), pr, _fill(w.color));
    _overlayGlows.add(Sprites.glow, _px, _py, pr * 6, _argb(0.8, w.color.toARGB32()));
  }

  void _drawLoot(Canvas canvas, int i) {
    final l = game.sim.loot[i];
    final bob = 12 + math.sin(game.clock * 3 + l.x * 0.1) * 4;
    if (project(l.x, l.y, bob)) _blit(canvas, Sprites.loot(Sprites.lootIcon(l.refId)), _px, _py, 36 * _ps);
  }

  // --------------------------------------------------------------- particles

  void _addFxParticles(Rect cull) {
    final q = _q;
    for (final p in game.fx.particles) {
      if (!p!.active || !cull.contains(Offset(p.x, p.y))) continue;
      if (q == 0 && p.kind != FxKind.muzzle) continue;
      if (!project(p.x, p.y, p.z)) continue;
      final t = p.life / p.maxLife;
      final s = _ps;
      switch (p.kind) {
        case FxKind.droplet:
          _overlayTinted.add(Sprites.dot, _px, _py, p.size * 2 * s, _argb(0.9 * t + 0.1, p.color));
        case FxKind.dust:
          _overlayTinted.add(Sprites.puff, _px, _py, p.size * 2.2 * s, _argb(0.5 * t, p.color));
        case FxKind.leaf:
          _overlayTinted.add(Sprites.leaf, _px, _py, p.size * 2 * s, _argb(math.min(1, t * 2), p.color), p.spin);
        case FxKind.sparkle:
          _overlayGlows.add(Sprites.glow, _px, _py, p.size * 4 * s, _argb(t, p.color));
        case FxKind.muzzle:
          _overlayGlows.add(Sprites.glow, _px, _py, p.size * 3 * s, _argb(t, p.color));
      }
    }
  }

  // --------------------------------------------------------------- haze

  static final _hazePaint = Paint()..color = const Color(0x99A8784A);
  static const _hazeEdge = 0x9C7A55;

  /// Haze outside the safe circle and the tree bubbles, as one path (no
  /// offscreen layer, which is expensive on phones).
  void _drawHaze(Canvas canvas, Rect visible) {
    final z = game.sim.zone;
    final fx = math.max((visible.left - z.cx).abs(), (visible.right - z.cx).abs());
    final fy = math.max((visible.top - z.cy).abs(), (visible.bottom - z.cy).abs());
    if (fx * fx + fy * fy < z.r * z.r) return;
    final area = visible.inflate(60);
    _path
      ..reset()
      ..addRect(area);
    _path2.reset();
    if (z.r > 0) _path2.addOval(Rect.fromCircle(center: Offset(z.cx, z.cy), radius: z.r));
    for (final t in game.sim.trees) {
      if (!t.alive || t.bubble <= 0) continue;
      final b = Rect.fromCircle(center: Offset(t.x, t.y), radius: t.bubble);
      if (b.overlaps(area)) _path2.addOval(b);
    }
    canvas.save();
    canvas.transform(_m);
    canvas.drawPath(Path.combine(PathOperation.difference, _path, _path2), _hazePaint);
    if (z.r > 0) canvas.drawCircle(Offset(z.cx, z.cy), z.r + 18, _line(const Color(0x33A8784A), 36));
    canvas.restore();
  }

  /// The edge of the safe zone rises as a wall of smoke.
  void _drawHazeWall(Canvas canvas, Rect cull) {
    final z = game.sim.zone;
    if (z.r <= 0) return;
    final segments = (2 * math.pi * z.r / 90).clamp(24, 140).round();
    const h = 110.0;
    final t = game.clock;
    _path.reset();
    _path2.reset();
    var any = false;
    for (var k = 0; k < segments; k++) {
      final a0 = k / segments * math.pi * 2, a1 = (k + 1) / segments * math.pi * 2;
      final x0 = z.cx + math.cos(a0) * z.r, y0 = z.cy + math.sin(a0) * z.r;
      final x1 = z.cx + math.cos(a1) * z.r, y1 = z.cy + math.sin(a1) * z.r;
      if (!cull.contains(Offset(x0, y0)) && !cull.contains(Offset(x1, y1))) continue;
      if (!project(x0, y0, 0)) continue;
      final b0 = Offset(_px, _py);
      if (!project(x1, y1, 0)) continue;
      final b1 = Offset(_px, _py);
      if (!project(x1, y1, h * 0.7)) continue;
      final t1 = Offset(_px, _py);
      if (!project(x0, y0, h * 0.7)) continue;
      final t0 = Offset(_px, _py);
      _path.addPolygon([b0, b1, t1, t0], true);
      _path2
        ..moveTo(b0.dx, b0.dy)
        ..lineTo(b1.dx, b1.dy);
      any = true;
      if (_q >= 1) {
        final layers = segments > 70 || _q < 2 ? const [48.0] : const [26.0, 70.0];
        for (final zz in layers) {
          if (!project(x0, y0, zz + math.sin(t * 0.9 + k * 1.7 + zz) * 10)) continue;
          _overlayTinted.add(Sprites.puff, _px, _py, (150 + (k % 3) * 35) * _ps, _argb(0.75, _hazeEdge));
        }
      }
    }
    if (!any) return;
    canvas.drawPath(_path, _fill(const Color(0x2EB07A45)));
    canvas.drawPath(_path2, _line(const Color(0xAAFF8A3D), 3));
  }

  /// Drifting smoke clouds inside the haze.
  void _addHazeSmoke() {
    final sim = game.sim;
    for (final p in game.particles) {
      if (sim.isSafeAt(p.x, p.y) || !project(p.x, p.y, 30)) continue;
      final life = p.life / p.maxLife;
      final a = math.min(1.0, math.min(life * 3, (1 - life) * 3)) * 0.55;
      _overlayTinted.add(Sprites.puff, _px, _py, p.size * 1.6 * _ps, _argb(a, 0x785F46));
    }
  }

  // --------------------------------------------------------------- screen

  /// Distance fog, vignette and damage / haze flashes.
  void drawScreenEffects(Canvas canvas) {
    final g = game;
    final rect = Rect.fromLTWH(0, 0, g.viewW, g.viewH);
    final sim = g.sim;
    if (sim.phase == MatchPhase.dropping) return;

    if (_q >= 1) {
      // The far (top) part of the view fades into hazy air, thicker each phase.
      final strength = (0.22 + 0.06 * sim.zone.phaseIndex).clamp(0.0, 0.5);
      if (_vignetteFor != strength || _vignette == null) {
        _vignetteFor = strength;
        _vignette = Paint()
          ..shader = Gradient.linear(
            Offset.zero,
            Offset(0, g.viewH),
            [
              Color.fromRGBO(196, 170, 135, strength),
              const Color(0x00C4AA87),
              const Color(0x00000000),
              const Color(0x33000000),
            ],
            [0, 0.5, 0.75, 1],
          );
      }
      canvas.drawRect(rect, _vignette!);
    }

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
