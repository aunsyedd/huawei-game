import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../components/actor.dart';
import '../haze_royale_game.dart';
import '../systems/match_manager.dart';
import '../world/block_world.dart';
import 'camera3d.dart';
import 'fx.dart';
import 'mesh.dart';
import 'models.dart';
import 'sky.dart';
import 'sprites.dart';
import 'voxels.dart';

/// Full 3D renderer. A real orbit camera ([Camera3D]) can be turned and
/// tilted freely; the flat ground goes through its 4x4 plane transform while
/// every upright thing — buildings, voxels, trees, characters, shots — is
/// projected vertex by vertex, lit, fogged and depth-sorted into one
/// `drawVertices` call.
///
/// World axes: x east, y south, z up. The simulation itself stays 2D.
///
/// Performance: repeated flat things are single blits from [Sprites.atlas];
/// groups (splats, shadows, smoke, droplets, glows) are batched into one
/// `drawRawAtlas` each; [HazeRoyaleGame.quality] (3 = ultra … 0 = minimal)
/// drops shadows, texture detail and particles on slower devices.
class PerspectiveRenderer {
  PerspectiveRenderer(this.game);

  final HazeRoyaleGame game;
  late final Image _atlas = Sprites.build(skins: [for (final k in game.config.progression.skins) k.color]).atlas;

  /// Default camera tilt from straight down, and eye distance.
  static const double tilt = Camera3D.defaultTilt;
  static const double distance = 1200;

  final Camera3D cam = Camera3D()..distance = distance;
  final SkyBox sky = SkyBox();
  late final VoxelRenderer voxels = VoxelRenderer(game.config.blocks);

  /// Sun direction, light colours and fog for the current time of day.
  Lighting light = Lighting.forTime(0.42, 0.25);

  /// Triangles queued in the last frame (diagnostics).
  int lastTriangles = 0;

  double get _px => cam.px;
  double get _py => cam.py;
  double get _ps => cam.ps;

  /// Screen position from the last successful [project] call.
  Offset get projected => cam.projected;

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
  final Paint _outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = const Color(0xCCFFFFFF);

  // Batches (one draw call each).
  final AtlasBatch _groundShadows = AtlasBatch(160);
  final AtlasBatch _groundDecals = AtlasBatch(180);
  final AtlasBatch _groundGlows = AtlasBatch(200);
  final AtlasBatch _overlayTinted = AtlasBatch(600);
  final AtlasBatch _overlayGlows = AtlasBatch(500);

  Paint? _vignette;
  double _vignetteFor = -1;

  Paint _fill(Color c) => _p..color = c;
  Paint _line(Color c, double w) => _s
    ..color = c
    ..strokeWidth = w;

  void onResize() => _vignette = null;

  int get _q => game.quality;

  static int _argb(double a, int rgb) => ((a.clamp(0.0, 1.0) * 255).round() << 24) | (rgb & 0xFFFFFF);

  // --------------------------------------------------------------- camera

  void setCamera(double camX, double camY) {
    final g = game;
    cam
      ..targetX = camX
      ..targetY = camY
      ..yaw = g.camYaw
      ..tilt = g.camTilt
      ..zoom = g.zoom
      ..viewW = g.viewW
      ..viewH = g.viewH
      ..update();
  }

  /// Projects a world point; result in [projected], scale in [_ps].
  bool project(double x, double y, double z) => cam.project(x, y, z);

  /// Screen point → ground point (z = 0).
  (double, double) unproject(double sx, double sy) => cam.unproject(sx, sy);

  /// How thick the air is right now, 0..1 (drives sky tint and fog).
  double get hazeAmount {
    final sim = game.sim;
    if (!sim.hazeActive) return 0.06;
    return (0.26 + 0.1 * sim.zone.phaseIndex).clamp(0.0, 0.8);
  }

  // --------------------------------------------------------------- frame

  void render(Canvas canvas, double camX, double camY) {
    final g = game;
    final sim = g.sim;
    setCamera(camX, camY);
    final haze = hazeAmount;
    light = Lighting.forTime(g.timeOfDay, haze);
    voxels.prepare(light, cam);
    sky.draw(canvas, cam, light, haze, g.clock, _q);

    final visible = cam.visibleGround();
    final cull = visible.inflate(120);
    final running = sim.phase != MatchPhase.dropping;
    final skyLine = math.max(0.0, cam.horizonY);

    // Ground layer through the camera's plane transform. Anything above the
    // horizon line would fold back on itself, so it is clipped away.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, skyLine, g.viewW, g.viewH));
    canvas.transform(cam.matrix);
    _drawShore(canvas, visible);
    g.drawChunks(canvas, visible);
    _tintGround(canvas, visible);
    if (!running) {
      canvas.restore();
      return; // The landing map covers the screen; skip the 3D world.
    }
    _drawBubbles(canvas, cull);
    _groundBatches(canvas, cull);
    g.drawEffects(canvas, cull);
    g.drawZoneLines(canvas);
    g.drawAimLine(canvas);
    canvas.restore();

    // Everything standing up is a lit 3D mesh, depth-sorted per triangle.
    _drawAirBand(canvas, skyLine);

    _emitWorld(cull);
    lastTriangles = _tris.n + _shadowTris.n;
    _shadowTris.draw(canvas);
    _tris.draw(canvas);
    _drawBlockTarget(canvas);
    _drawLabels(canvas);

    if (sim.hazeActive) {
      _drawHaze(canvas, visible, skyLine);
      _drawHazeWall(canvas, cull);
      if (_q >= 2) _addHazeSmoke();
    }
    _addFxParticles(cull);
    _overlayTinted.draw(canvas, _atlas, _img);
    _overlayGlows.draw(canvas, _atlas, _additive);
  }

  /// The baked ground textures are painted for full daylight, so dusk and
  /// night are applied as a multiply over the ground layer. Without this the
  /// island would stay sunlit while everything standing on it turns blue.
  void _tintGround(Canvas canvas, Rect visible) {
    const ref = 1.26; // roughly the daytime top-face light
    final k = light.lz * 0.95;
    final r = ((light.ar + light.dr * k) / ref).clamp(0.0, 1.0);
    final g = ((light.ag + light.dg * k) / ref).clamp(0.0, 1.0);
    final b = ((light.ab + light.db * k) / ref).clamp(0.0, 1.0);
    if (r > 0.985 && g > 0.985 && b > 0.985) return;
    canvas.drawRect(
      visible.inflate(200),
      Paint()
        ..color = Color.fromRGBO((r * 255).round(), (g * 255).round(), (b * 255).round(), 1)
        ..blendMode = BlendMode.modulate,
    );
  }

  /// A band of air between the far ground and the sky, so the island melts
  /// into the horizon instead of ending at a hard edge.
  void _drawAirBand(Canvas canvas, double skyLine) {
    if (skyLine > game.viewH) return;
    final top = math.max(0.0, skyLine);
    final depth = game.viewH * 0.42;
    canvas.drawRect(
      Rect.fromLTRB(0, top, game.viewW, top + depth),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, top),
          Offset(0, top + depth),
          [light.fog.withValues(alpha: 0.96), light.fog.withValues(alpha: 0)],
        ),
    );
  }

  /// See-through when this object sits between the camera and the player.
  bool _occludesFocus(double l, double r, double bottom, double height, double fx, double fy) =>
      fx > l - 30 && fx < r + 30 && fy < bottom && fy > bottom - height * 2.2 - 40;

  // --------------------------------------------------------------- ground layer

  /// Animated foam lines where the sea meets the island.
  void _drawShore(Canvas canvas, Rect visible) {
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

  /// Clean-air bubbles: planted trees and air-filter blocks.
  void _drawBubbles(Canvas canvas, Rect cull) {
    final t = game.clock;
    void bubble(double x, double y, double r, Color fillColor, Color edge) {
      final o = Offset(x, y);
      if (!cull.inflate(r).contains(o)) return;
      canvas.drawCircle(o, r, _fill(fillColor));
      canvas.drawCircle(o, r, _line(edge, 4));
      if (_q >= 2) {
        final pr = r * (0.55 + 0.45 * ((t * 0.5 + x * 0.001) % 1));
        canvas.drawCircle(o, pr, _line(Color.fromRGBO(200, 255, 200, 0.35 * (1 - pr / r)), 3));
      }
    }

    for (final tree in game.sim.trees) {
      if (!tree.alive || tree.bubble <= 0) continue;
      bubble(tree.x, tree.y, tree.bubble, const Color(0x2481C784), const Color(0xBB7CDB80));
    }
    final blocks = game.sim.blocks;
    for (final col in blocks.filters) {
      final bx = BlockWorld.keyX(col), by = BlockWorld.keyY(col);
      var r = 0.0;
      final h = blocks.height(bx, by);
      for (var z = 0; z < h; z++) {
        final ty = blocks.typeAt(bx, by, z);
        if (ty >= 0 && blocks.cfg.types[ty].bubble > r) r = blocks.cfg.types[ty].bubble;
      }
      if (r > 0) bubble(blocks.wx(bx), blocks.wy(by), r, const Color(0x2680DEEA), const Color(0xAA4DD0E1));
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
    // At ultra the characters cast real mesh shadows instead of blobs.
    if (_q < 3) {
      for (final a in sim.actors) {
        if (!a.alive || !cull.contains(Offset(a.pos.x, a.pos.y))) continue;
        _groundShadows.add(Sprites.shadowOval, a.pos.x + 7, a.pos.y + 6, 56, 0xFFFFFFFF);
      }
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
      // Drawn as a polygon: a circle this close to the camera comes out
      // lopsided once the ground plane transform is applied to its curves.
      _path.reset();
      const steps = 28;
      for (var i = 0; i <= steps; i++) {
        final a = i / steps * math.pi * 2;
        final x = p.pos.x + math.cos(a) * 28 * pulse, y = p.pos.y + math.sin(a) * 28 * pulse;
        if (i == 0) {
          _path.moveTo(x, y);
        } else {
          _path.lineTo(x, y);
        }
      }
      canvas.drawPath(_path, _line(const Color(0xAA4FC3F7), 3));
    }
  }

  // --------------------------------------------------------------- 3D meshes

  late final ModelLibrary models = ModelLibrary(game.config, game.sim.map);
  final TriangleBatch _tris = TriangleBatch(26000);
  final TriangleBatch _shadowTris = TriangleBatch(4000);
  Float32List _sx = Float32List(512), _sy = Float32List(512), _sw = Float32List(512);
  Float32List _wx = Float32List(512), _wy = Float32List(512), _wz = Float32List(512);
  final Map<int, double> _walkPhase = {};

  double _fogNear = 1150, _fogFar = 2600;
  static const double _fogMax = 0.82;

  /// Projects one model instance into the triangle batch: transform, light,
  /// back-face cull, fog, then queue for the depth-sorted draw.
  void _emit(
    Mesh m,
    double px,
    double py,
    double pz, {
    double yaw = 0,
    double scale = 1,
    double bend = 0,
    double bendHeight = 80,
    double kick = 0,
    double alpha = 1,
    double flash = 0,
    double haze = 0,
  }) {
    final vc = m.vertexCount;
    if (_sx.length < vc) {
      _sx = Float32List(vc * 2);
      _sy = Float32List(vc * 2);
      _sw = Float32List(vc * 2);
      _wx = Float32List(vc * 2);
      _wy = Float32List(vc * 2);
      _wz = Float32List(vc * 2);
    }
    final cs = math.cos(yaw), sn = math.sin(yaw);
    final v = m.verts;
    final tx = cam.targetX, ty = cam.targetY;
    final nx0 = cam.nx, ny0 = cam.ny, nz0 = cam.nz;
    final rx0 = cam.rx, ry0 = cam.ry;
    final ux0 = cam.ux, uy0 = cam.uy, uz0 = cam.uz;
    final f = cam.f, w2 = cam.w2, h0 = cam.h0, dist = cam.distance;
    for (var i = 0; i < vc; i++) {
      var lx = v[i * 3];
      final ly = v[i * 3 + 1], lz = v[i * 3 + 2];
      if (kick != 0 && lz < 16) lx += kick * (16 - lz) / 16;
      if (bend != 0) lx += bend * (lz / bendHeight) * (lz / bendHeight);
      final x = px + (lx * cs - ly * sn) * scale;
      final y = py + (lx * sn + ly * cs) * scale;
      final z = pz + lz * scale;
      _wx[i] = x;
      _wy[i] = y;
      _wz[i] = z;
      final dx = x - tx, dy = y - ty;
      final w = dist - (dx * nx0 + dy * ny0 + z * nz0);
      _sw[i] = w;
      if (w < 20) continue;
      _sx[i] = w2 + f * (dx * rx0 + dy * ry0) / w;
      _sy[i] = h0 - f * (dx * ux0 + dy * uy0 + z * uz0) / w;
    }
    final eyeX = cam.eyeX, eyeY = cam.eyeY, eyeZ = cam.eyeZ;
    final t = m.tris, n = m.normals, col = m.colors;
    final tc = m.triCount;
    final fog = light.fog;
    final fogR = ((fog.toARGB32() >> 16) & 0xFF).toDouble();
    final fogG = ((fog.toARGB32() >> 8) & 0xFF).toDouble();
    final fogB = (fog.toARGB32() & 0xFF).toDouble();
    for (var k = 0; k < tc; k++) {
      final a = t[k * 3], b = t[k * 3 + 1], c = t[k * 3 + 2];
      final wa = _sw[a], wb = _sw[b], wc = _sw[c];
      if (wa < 20 || wb < 20 || wc < 20) continue;
      final onx = n[k * 3], ony = n[k * 3 + 1], nz = n[k * 3 + 2];
      final nx = onx * cs - ony * sn, ny = onx * sn + ony * cs;
      final mx = (_wx[a] + _wx[b] + _wx[c]) / 3,
          my = (_wy[a] + _wy[b] + _wy[c]) / 3,
          mz = (_wz[a] + _wz[b] + _wz[c]) / 3;
      if (nx * (eyeX - mx) + ny * (eyeY - my) + nz * (eyeZ - mz) <= 0) continue; // faces away
      final depth = (wa + wb + wc) / 3;
      final diffuse = math.max(0.0, nx * light.lx + ny * light.ly + nz * light.lz);
      final sky = 0.1 * math.max(0.0, nz);
      final base = col[k];
      var r = ((base >> 16) & 0xFF) * (light.ar + light.dr * diffuse + sky);
      var gr = ((base >> 8) & 0xFF) * (light.ag + light.dg * diffuse + sky);
      var bl = (base & 0xFF) * (light.ab + light.db * diffuse + sky);
      if (flash > 0) {
        r += (255 - r) * flash;
        gr += (255 - gr) * flash;
        bl += (255 - bl) * flash;
      }
      if (haze > 0) {
        r += (150 - r) * haze;
        gr += (115 - gr) * haze;
        bl += (80 - bl) * haze;
      }
      final fogK = ((depth - _fogNear) / (_fogFar - _fogNear)).clamp(0.0, _fogMax);
      if (fogK > 0) {
        r += (fogR - r) * fogK;
        gr += (fogG - gr) * fogK;
        bl += (fogB - bl) * fogK;
      }
      final al = ((base >> 24) & 0xFF) * alpha;
      final argb =
          (al.round().clamp(0, 255) << 24) |
          (r.round().clamp(0, 255) << 16) |
          (gr.round().clamp(0, 255) << 8) |
          bl.round().clamp(0, 255);
      _tris.add(_sx[a], _sy[a], _sx[b], _sy[b], _sx[c], _sy[c], argb, depth);
    }
  }

  final Float32List _shq = Float32List(8);
  static const List<(double, double)> _unitCorners = [(-1, -1), (1, -1), (1, 1), (-1, 1)];

  /// A cast shadow for an upright object: its footprint flattened onto the
  /// ground along the shadow direction. One quad, so nothing double-darkens.
  void _castShadow(double x, double y, double halfX, double halfY, double height, double yaw, double alpha) {
    final ox = Lighting.shadowX * height, oy = Lighting.shadowY * height;
    final cs = math.cos(yaw), sn = math.sin(yaw);
    for (var k = 0; k < 4; k++) {
      final lx = _unitCorners[k].$1 * halfX, ly = _unitCorners[k].$2 * halfY;
      if (!cam.project(x + lx * cs - ly * sn + ox, y + lx * sn + ly * cs + oy, 0)) return;
      _shq[k * 2] = cam.px;
      _shq[k * 2 + 1] = cam.py;
    }
    final c = _argb(alpha, 0);
    final depth = cam.depthOf(x + ox, y + oy, 0);
    _shadowTris.add(_shq[0], _shq[1], _shq[2], _shq[3], _shq[4], _shq[5], c, depth);
    _shadowTris.add(_shq[0], _shq[1], _shq[4], _shq[5], _shq[6], _shq[7], c, depth);
  }

  bool _inView(Rect cull, double x, double y) => x > cull.left && x < cull.right && y > cull.top && y < cull.bottom;

  /// Everything that stands up: buildings, voxels, nature, characters, trees,
  /// loot and shots.
  void _emitWorld(Rect cull) {
    final sim = game.sim;
    final map = sim.map;
    final f = sim.focus.pos;
    final t = game.clock;
    _fogNear = cam.distance * 0.92;
    _fogFar = cam.distance * (1.6 + 1.9 / math.max(0.25, cam.sinT));
    final meshShadows = _q >= 3;

    for (var i = 0; i < map.buildings.length; i++) {
      final b = map.buildings[i];
      if (!b.rect.overlaps(cull)) continue;
      final inside = b.contains(f.x, f.y);
      final h = ModelLibrary.wallHeight(b);
      final hide = !inside && _occludesFocus(b.rect.left, b.rect.right, b.rect.bottom, h, f.x, f.y);
      final alpha = hide ? 0.38 : 1.0;
      _emit(inside ? models.buildingLow[i] : models.buildingFull[i], 0, 0, 0, alpha: alpha);
      if (!inside) _emit(models.roofs[i], 0, 0, 0, alpha: hide ? 0.3 : 1.0);
    }

    // The voxel layer.
    voxels.emit(
      world: sim.blocks,
      cam: cam,
      out: _tris,
      cull: cull,
      light: light,
      quality: _q,
      shadows: _q >= 2 ? _shadowTris : null,
      glows: _overlayGlows,
    );

    for (var i = 0; i < map.obstacles.length; i++) {
      final o = map.obstacles[i];
      if (!_inView(cull, o.x, o.y)) continue;
      final near = (o.x - f.x).abs() < o.r * 2 + 20 && o.y > f.y && o.y - f.y < 110;
      final alpha = near ? 0.4 : 1.0;
      // Cube models must stay axis aligned, so yaw snaps to quarter turns.
      final quarter = (((o.x + o.y) / 71).floor() % 4) * (math.pi / 2);
      switch (o.kind) {
        case 'tree':
          final far = _q <= 1 || cam.depthOf(o.x, o.y, 0) > cam.distance * 1.25;
          final set = far ? models.treesLow : models.trees;
          _emit(set[i & 3], o.x, o.y, 0, yaw: quarter, scale: o.r / ModelLibrary.treeRef, alpha: alpha);
        case 'rock':
          _emit(models.rocks[i % 3], o.x, o.y, 0, yaw: quarter, scale: o.r / ModelLibrary.rockRef, alpha: alpha);
        default:
          final sway = math.sin(t * 1.4 + o.x * 0.05) * 5;
          _emit(models.palm, o.x, o.y, 0, yaw: o.x * 0.01, scale: o.r / 14, bend: sway, bendHeight: 78, alpha: alpha);
      }
    }

    for (final tr in sim.trees) {
      if (!tr.alive || !_inView(cull, tr.x, tr.y)) continue;
      final r = game.config.trees.trunkRadius[tr.stage];
      _emit(
        models.sapling,
        tr.x,
        tr.y,
        0,
        yaw: (tr.x * 0.02).roundToDouble() * math.pi / 2,
        scale: r * 1.15,
        flash: tr.hitFlash > 0 ? 0.7 : 0,
      );
    }

    for (final a in sim.actors) {
      if (!a.alive || !_inView(cull, a.pos.x, a.pos.y)) continue;
      final color = a.isPlayer && game.playerSkin < game.config.progression.skins.length
          ? game.config.progression.skins[game.playerSkin].color
          : a.color;
      final moving = a.vel.length2 > 100;
      final phase = _walkPhase[a.id] = (_walkPhase[a.id] ?? 0) + (moving ? 0.25 : 0);
      final swing = moving ? math.sin(phase) * 6 : 0.0;
      final bob = moving ? math.sin(phase * 2).abs() * 1.5 : 0.0;
      final flash = a.hitFlash > 0 ? 0.75 : 0.0;
      final inHaze = !sim.isSafeAt(a.pos.x, a.pos.y) ? 0.25 : 0.0;
      final yaw = a.aimAngle;
      final mining = a.action == ActorAction.mining;
      // Mining swings the arms: a short forward jab on every blow.
      final swingArm = mining ? math.sin(a.actionTime / math.max(0.08, a.actionDuration) * math.pi * 3) * 10 : 0.0;
      _emit(models.leg(color, left: true), a.pos.x, a.pos.y, 0, yaw: yaw, kick: swing, flash: flash, haze: inHaze);
      _emit(models.leg(color, left: false), a.pos.x, a.pos.y, 0, yaw: yaw, kick: -swing, flash: flash, haze: inHaze);
      if (meshShadows) _castShadow(a.pos.x, a.pos.y, 13, 10.5, 46, yaw, 0.3);
      _emit(
        models.upper(color, detail: _q >= 2),
        a.pos.x,
        a.pos.y,
        bob,
        yaw: yaw,
        flash: flash,
        haze: inHaze,
        bend: swingArm,
        bendHeight: 40,
      );
      if (a.armour > 0) _emit(models.vest, a.pos.x, a.pos.y, bob, yaw: yaw, flash: flash);
      if (a.hazeShield > 0) _emit(models.mask, a.pos.x, a.pos.y, bob, yaw: yaw);
      if (mining) {
        _emit(models.pickaxe, a.pos.x, a.pos.y, bob, yaw: yaw, bend: swingArm, bendHeight: 40);
      } else {
        final w = a.weapon;
        if (w != null) {
          _emit(models.gun(w.stats), a.pos.x, a.pos.y, bob, yaw: yaw, flash: flash);
          if (game.sim.time - game.lastShot[a.id] < 0.08) {
            final len = 40.0 + w.stats.rank * 6;
            if (project(a.pos.x + math.cos(yaw) * len, a.pos.y + math.sin(yaw) * len, 27)) {
              _overlayGlows.add(Sprites.glow, _px, _py, 44 * _ps, w.stats.color.toARGB32());
            }
          }
        }
      }
    }

    for (final l in sim.loot) {
      if (l.taken || !_inView(cull, l.x, l.y)) continue;
      final bob = 14 + math.sin(t * 3 + l.x * 0.1) * 4;
      _emit(models.loot(l.refId), l.x, l.y, bob, yaw: t * 1.8 + l.x * 0.05, scale: 1.1);
    }

    for (final p in sim.projectiles.items) {
      if (!p.active || !_inView(cull, p.x, p.y)) continue;
      final w = p.weapon;
      _emit(models.shot(w.color), p.x, p.y, 27, scale: w.projectileRadius * 1.2);
      if (project(p.x, p.y, 27)) {
        _overlayGlows.add(Sprites.glow, _px, _py, w.projectileRadius * 6 * _ps, _argb(0.75, w.color.toARGB32()));
      }
      if (project(p.x - p.vx * 0.03, p.y - p.vy * 0.03, 27)) {
        _overlayTinted.add(Sprites.dot, _px, _py, w.projectileRadius * 1.4 * _ps, _argb(0.35, w.color.toARGB32()));
      }
    }
  }

  /// Wireframe box on the column the player is about to mine or build on.
  void _drawBlockTarget(Canvas canvas) {
    final sim = game.sim;
    final p = sim.player;
    if (!p.alive || p.brain != null || !game.showBlockTarget) return;
    final (bx, by) = sim.targetColumn(p);
    final has = sim.blocks.height(bx, by) > 0;
    final placing = !has || !game.buildMode;
    if (!has && p.carried(p.selected) <= 0) return;
    _outline.color = has && game.buildMode ? const Color(0xCCFFF59D) : const Color(0xAAFFFFFF);
    voxels.drawTarget(canvas, cam, sim.blocks, bx, by, _outline, placing: placing && !has);
  }

  /// Health bars and action rings, drawn on top of the 3D scene.
  void _drawLabels(Canvas canvas) {
    final sim = game.sim;
    for (final a in sim.actors) {
      if (!a.alive) continue;
      if (a.busy && project(a.pos.x, a.pos.y, 26)) {
        final color = switch (a.action) {
          ActorAction.planting => const Color(0xFF66BB6A),
          ActorAction.mining => const Color(0xFFFFCA28),
          _ => const Color(0xFF4FC3F7),
        };
        canvas.drawArc(
          Rect.fromCircle(center: Offset(_px, _py), radius: 30 * _ps),
          -math.pi / 2,
          math.pi * 2 * a.actionProgress,
          false,
          _line(color, 5 * _ps),
        );
      }
      if (!a.isPlayer && sim.time - a.lastDamageTime < 3 && project(a.pos.x, a.pos.y, 62)) {
        _bar(canvas, _px, _py, a.health / a.maxHealth, const Color(0xFFEF5350));
      }
    }
    for (final t in sim.trees) {
      if (!t.alive || t.health >= t.maxHealth) continue;
      final r = game.config.trees.trunkRadius[t.stage];
      if (project(t.x, t.y, r * 7)) _bar(canvas, _px, _py, t.health / t.maxHealth, const Color(0xFF66BB6A));
    }
  }

  void _bar(Canvas canvas, double x, double y, double frac, Color color) {
    final w = 40 * _ps, h = math.max(3.0, 5 * _ps);
    canvas.drawRect(Rect.fromLTWH(x - w / 2 - 1, y - 1, w + 2, h + 2), _fill(const Color(0xAA000000)));
    canvas.drawRect(Rect.fromLTWH(x - w / 2, y, w * frac.clamp(0, 1), h), _fill(color));
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
        case FxKind.cube:
          _overlayTinted.add(Sprites.cube, _px, _py, p.size * 2.4 * s, _argb(math.min(1, t * 2.2), p.color), p.spin);
      }
    }
  }

  // --------------------------------------------------------------- haze

  static final _hazePaint = Paint()..color = const Color(0x99A8784A);
  static const _hazeEdge = 0x9C7A55;

  /// Haze outside the safe circle and the clean-air bubbles, as one path (no
  /// offscreen layer, which is expensive on phones).
  void _drawHaze(Canvas canvas, Rect visible, double skyLine) {
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
    final blocks = game.sim.blocks;
    for (final col in blocks.filters) {
      final bx = BlockWorld.keyX(col), by = BlockWorld.keyY(col);
      final ty = blocks.top(bx, by);
      final r = ty?.bubble ?? 0;
      if (r <= 0) continue;
      final b = Rect.fromCircle(center: Offset(blocks.wx(bx), blocks.wy(by)), radius: r);
      if (b.overlaps(area)) _path2.addOval(b);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, skyLine, game.viewW, game.viewH));
    canvas.transform(cam.matrix);
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
      if (cam.depthOf(x0, y0, 0) < cam.distance * 0.25) continue; // nearly edge-on: it would smear
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

    if (_q >= 1 && sim.hazeActive) {
      // The far (top) part of the view fades into hazy air, thicker each phase.
      final strength = (0.18 + 0.06 * sim.zone.phaseIndex).clamp(0.0, 0.45);
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
    final inHaze = sim.hazeActive && !sim.isSafeAt(p.pos.x, p.pos.y);
    if (!inHaze && g.hurtTimer <= 0) return;
    final color = g.hurtTimer > 0 ? const Color(0x88D32F2F) : const Color(0x998D6E3A);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.radial(rect.center, rect.longestSide * 0.6, [const Color(0x00000000), color], [0.55, 1.0]),
    );
  }
}
