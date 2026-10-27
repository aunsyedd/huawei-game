import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../data/game_config.dart';
import '../world/block_world.dart';
import 'camera3d.dart';
import 'mesh.dart';
import 'sky.dart';
import 'sprites.dart';

/// Draws the voxel layer: every cube face that touches air, lit per face the
/// way Minecraft does it (bright lid, dimmer sides), shaded per corner with
/// ambient occlusion and roughened with a deterministic grain so a wall of
/// one block type never looks like flat paint.
///
/// Faces go straight into the shared [TriangleBatch], so the whole voxel
/// world costs one draw call together with the rest of the 3D scene.
class VoxelRenderer {
  VoxelRenderer(this.cfg);

  final BlockConfig cfg;

  /// Minecraft-style fixed face brightness: lid, east, west, south, north.
  static const List<double> _faceLight = [1.0, 0.86, 0.78, 0.94, 0.82];
  static const List<double> _nx = [0, 1, -1, 0, 0];
  static const List<double> _ny = [0, 0, 0, 1, -1];
  static const List<double> _nz = [1, 0, 0, 0, 0];

  // Per-frame, per-face light (5 faces x rgb).
  final Float32List _light = Float32List(15);
  final Float32List _spec = Float32List(5);

  // Scratch: screen positions of one column's 4 corners at two heights.
  final Float32List _ax = Float32List(4), _bx = Float32List(4), _cx = Float32List(4);
  final Float32List _lowX = Float32List(4), _lowY = Float32List(4);
  final Float32List _hiX = Float32List(4), _hiY = Float32List(4);
  final Float32List _qx = Float32List(9), _qy = Float32List(9);

  /// Blocks drawn in the last frame (for the FPS overlay / debugging).
  int drawn = 0;

  void prepare(Lighting light, Camera3D cam) {
    for (var d = 0; d < 5; d++) {
      // Wrapped diffuse: a face turned away from the sun still catches sky
      // light, so no side of a cube ever goes black.
      final diff = 0.58 + 0.42 * math.max(0.0, _nx[d] * light.lx + _ny[d] * light.ly + _nz[d] * light.lz);
      final k = _faceLight[d];
      _light[d * 3] = (light.ar + light.dr * diff) * k;
      _light[d * 3 + 1] = (light.ag + light.dg * diff) * k;
      _light[d * 3 + 2] = (light.ab + light.db * diff) * k;
      // Blinn-style highlight with a per-frame view vector (good enough for
      // cubes, and it costs nothing per block).
      final hx = light.lx - cam.nx, hy = light.ly - cam.ny, hz = light.lz - cam.nz;
      final hl = math.sqrt(hx * hx + hy * hy + hz * hz) + 1e-6;
      final nh = (_nx[d] * hx + _ny[d] * hy + _nz[d] * hz) / hl;
      final s = nh <= 0 ? 0.0 : math.pow(nh, 22).toDouble();
      _spec[d] = s * math.max(0.0, light.sunUp) * 255;
    }
  }

  /// Emits every visible face of every column inside [cull].
  void emit({
    required BlockWorld world,
    required Camera3D cam,
    required TriangleBatch out,
    required Rect cull,
    required Lighting light,
    required int quality,
    TriangleBatch? shadows,
    AtlasBatch? glows,
  }) {
    drawn = 0;
    if (world.heights.isEmpty) return;
    final s = world.size;
    final x0 = world.gx(cull.left), x1 = world.gx(cull.right);
    final y0 = world.gy(cull.top), y1 = world.gy(cull.bottom);
    if (x1 < x0 || y1 < y0) return;
    final detailRange = quality >= 3 ? 1100.0 : 0.0;
    final shadowRange = quality >= 3 ? 1500.0 : (quality >= 2 ? 900.0 : 0.0);

    for (var by = y0; by <= y1; by++) {
      for (var bx = x0; bx <= x1; bx++) {
        final h = world.height(bx, by);
        if (h == 0) continue;
        if (out.n > out.capacity - 80) return;
        _column(world, cam, out, shadows, glows, light, quality, bx, by, h, s, detailRange, shadowRange);
      }
    }
  }

  void _column(
    BlockWorld world,
    Camera3D cam,
    TriangleBatch out,
    TriangleBatch? shadows,
    AtlasBatch? glows,
    Lighting light,
    int quality,
    int bx,
    int by,
    int h,
    double s,
    double detailRange,
    double shadowRange,
  ) {
    // Corner order: (0,0) (1,0) (1,1) (0,1) in grid-local units.
    final wx0 = bx * s, wy0 = by * s, wx1 = wx0 + s, wy1 = wy0 + s;
    const ci = [0, 1, 1, 0], cj = [0, 0, 1, 1];
    for (var k = 0; k < 4; k++) {
      final dx = (ci[k] == 0 ? wx0 : wx1) - cam.targetX;
      final dy = (cj[k] == 0 ? wy0 : wy1) - cam.targetY;
      _ax[k] = dx * cam.nx + dy * cam.ny;
      _bx[k] = dx * cam.rx + dy * cam.ry;
      _cx[k] = dx * cam.ux + dy * cam.uy;
    }

    final east = cam.eyeX > wx1, west = cam.eyeX < wx0;
    final south = cam.eyeY > wy1, north = cam.eyeY < wy0;
    final hE = world.height(bx + 1, by), hW = world.height(bx - 1, by);
    final hS = world.height(bx, by + 1), hN = world.height(bx, by - 1);
    final crack = world.crackAt(bx, by);
    final depth = cam.depthOf(wx0 + s * 0.5, wy0 + s * 0.5, 0);
    final detail = depth < detailRange;

    // Project the bottom ring once, then walk up level by level.
    if (!_ring(cam, 0, _lowX, _lowY)) return;
    for (var z = 0; z < h; z++) {
      if (!_ring(cam, (z + 1) * s, _hiX, _hiY)) break;
      final t = world.typeAt(bx, by, z);
      if (t < 0) {
        _copyRing();
        continue;
      }
      final type = cfg.types[t];
      final seed = BlockWorld.cellKey(bx, by, z);
      final isTop = z == h - 1;
      final dim = isTop ? 1 - 0.42 * crack : 1.0;
      final alpha = (type.alpha * 255).round().clamp(0, 255);

      // Lid.
      if (isTop) {
        final ao0 = _topAo(world, bx, by, z, 0, 0);
        final ao1 = _topAo(world, bx, by, z, 1, 0);
        final ao2 = _topAo(world, bx, by, z, 1, 1);
        final ao3 = _topAo(world, bx, by, z, 0, 1);
        _face(out, _hiX, _hiY, const [0, 1, 2, 3], 0, type, type.top, seed * 7 + 1, alpha, dim, detail, [
          ao0,
          ao1,
          ao2,
          ao3,
        ], light, depth);
        drawn++;
      }
      // Sides: emit only the faces turned towards the eye and touching air.
      if (east && hE <= z) _side(out, 1, 1, 2, type, seed, alpha, dim, detail, light, depth, z, h);
      if (west && hW <= z) _side(out, 2, 3, 0, type, seed, alpha, dim, detail, light, depth, z, h);
      if (south && hS <= z) _side(out, 3, 2, 3, type, seed, alpha, dim, detail, light, depth, z, h);
      if (north && hN <= z) _side(out, 4, 0, 1, type, seed, alpha, dim, detail, light, depth, z, h);

      // Lamps only really glow once the light goes; in daylight a halo
      // washes the whole scene out.
      if (glows != null && type.glow > 0 && light.night > 0.15) {
        final g = type.glow * (light.night - 0.15) * 0.9;
        if (g > 0.05 && cam.project(wx0 + s / 2, wy0 + s / 2, (z + 0.5) * s)) {
          glows.add(
            Sprites.glow,
            cam.px,
            cam.py,
            s * 2.6 * cam.ps,
            (((g * 200).round().clamp(0, 255)) << 24) | (type.top.toARGB32() & 0xFFFFFF),
          );
        }
      }
      _copyRing();
    }

    // One flattened quad per column is an exact shadow for a box of cubes.
    if (shadows != null && depth < shadowRange) {
      final zTop = h * s;
      final ox = Lighting.shadowX * zTop, oy = Lighting.shadowY * zTop;
      var ok = true;
      for (var k = 0; k < 4; k++) {
        if (!cam.project((ci[k] == 0 ? wx0 : wx1) + ox, (cj[k] == 0 ? wy0 : wy1) + oy, 0)) {
          ok = false;
          break;
        }
        _qx[k] = cam.px;
        _qy[k] = cam.py;
      }
      if (ok) {
        const shade = 0x44000000;
        shadows.add(_qx[0], _qy[0], _qx[1], _qy[1], _qx[2], _qy[2], shade, depth);
        shadows.add(_qx[0], _qy[0], _qx[2], _qy[2], _qx[3], _qy[3], shade, depth);
      }
    }
  }

  /// Projects the column's 4 corners at height [z] into [_hiX] / [_hiY].
  bool _ring(Camera3D cam, double z, Float32List outX, Float32List outY) {
    for (var k = 0; k < 4; k++) {
      final w = cam.distance - _ax[k] - z * cam.nz;
      if (w < 20) return false;
      outX[k] = cam.w2 + cam.f * _bx[k] / w;
      outY[k] = cam.h0 - cam.f * (_cx[k] + z * cam.uz) / w;
    }
    return true;
  }

  void _copyRing() {
    for (var k = 0; k < 4; k++) {
      _lowX[k] = _hiX[k];
      _lowY[k] = _hiY[k];
    }
  }

  /// Corner darkening from the three columns that touch this top corner.
  double _topAo(BlockWorld w, int bx, int by, int z, int i, int j) {
    final nxp = bx + i - 1, nyp = by + j - 1;
    var n = 0;
    if (w.height(nxp, nyp) > z + 1) n++;
    if (w.height(nxp + 1, nyp) > z + 1) n++;
    if (w.height(nxp, nyp + 1) > z + 1) n++;
    if (w.height(nxp + 1, nyp + 1) > z + 1) n++;
    return 1 - 0.1 * n;
  }

  /// One vertical face, between corners [a] and [b] of the ring.
  void _side(
    TriangleBatch out,
    int dir,
    int a,
    int b,
    BlockType type,
    int seed,
    int alpha,
    double dim,
    bool detail,
    Lighting light,
    double depth,
    int z,
    int h,
  ) {
    // Lower corners sit in the ground's shadow, upper ones catch the sky.
    final lo = 1 - 0.2 / (1 + z);
    _qx[0] = _lowX[a];
    _qy[0] = _lowY[a];
    _qx[1] = _lowX[b];
    _qy[1] = _lowY[b];
    _qx[2] = _hiX[b];
    _qy[2] = _hiY[b];
    _qx[3] = _hiX[a];
    _qy[3] = _hiY[a];
    final color = type.side;
    final ao = [lo, lo, 1.0, 1.0];
    _quad(out, _qx, _qy, dir, type, color, seed * 31 + dir, alpha, dim, detail, ao, light, depth);
    // Grass-style rim: the top slice of a side face takes the lid colour.
    if (type.rim && z == h - 1) {
      const rim = 0.26;
      final r0x = _qx[0] + (_qx[3] - _qx[0]) * (1 - rim), r0y = _qy[0] + (_qy[3] - _qy[0]) * (1 - rim);
      final r1x = _qx[1] + (_qx[2] - _qx[1]) * (1 - rim), r1y = _qy[1] + (_qy[2] - _qy[1]) * (1 - rim);
      _qx[0] = r0x;
      _qy[0] = r0y;
      _qx[1] = r1x;
      _qy[1] = r1y;
      _quad(out, _qx, _qy, dir, type, type.top, seed * 31 + dir + 9, alpha, dim, false, const [
        0.94,
        0.94,
        1.0,
        1.0,
      ], light, depth - 0.4);
    }
  }

  void _face(
    TriangleBatch out,
    Float32List rx,
    Float32List ry,
    List<int> order,
    int dir,
    BlockType type,
    Color color,
    int seed,
    int alpha,
    double dim,
    bool detail,
    List<double> ao,
    Lighting light,
    double depth,
  ) {
    for (var k = 0; k < 4; k++) {
      _qx[k] = rx[order[k]];
      _qy[k] = ry[order[k]];
    }
    _quad(out, _qx, _qy, dir, type, color, seed, alpha, dim, detail, ao, light, depth);
  }

  /// Emits a quad given 4 screen corners in [_qx] / [_qy] (indices 0..3).
  void _quad(
    TriangleBatch out,
    Float32List qx,
    Float32List qy,
    int dir,
    BlockType type,
    Color color,
    int seed,
    int alpha,
    double dim,
    bool detail,
    List<double> ao,
    Lighting light,
    double depth,
  ) {
    final base = color.toARGB32();
    final br = (base >> 16) & 0xFF, bg = (base >> 8) & 0xFF, bb = base & 0xFF;
    final lr = _light[dir * 3] * dim, lg = _light[dir * 3 + 1] * dim, lb = _light[dir * 3 + 2] * dim;
    final spec = _spec[dir] * type.shine;
    final emit = type.glow * (0.25 + 0.75 * light.night) * 150;

    int shade(double k, int grainSeed) {
      final g = 1 + _grain(grainSeed) * type.grain;
      final m = k * g;
      final r = br * lr * m + spec + emit;
      final gg = bg * lg * m + spec + emit * 0.92;
      final b = bb * lb * m + spec * 0.9 + emit * 0.7;
      return (alpha << 24) |
          (r.round().clamp(0, 255) << 16) |
          (gg.round().clamp(0, 255) << 8) |
          b.round().clamp(0, 255);
    }

    if (!detail) {
      final c0 = shade(ao[0], seed), c1 = shade(ao[1], seed), c2 = shade(ao[2], seed), c3 = shade(ao[3], seed);
      out.add(qx[0], qy[0], qx[1], qy[1], qx[2], qy[2], c0, depth, c1, c2);
      out.add(qx[0], qy[0], qx[2], qy[2], qx[3], qy[3], c0, depth, c2, c3);
      return;
    }

    // Ultra: split the face into 2x2 texels, each with its own grain, so the
    // surface reads as a pixel texture instead of a flat polygon.
    final gx = _qx, gy = _qy;
    final p0x = qx[0], p0y = qy[0], p1x = qx[1], p1y = qy[1], p2x = qx[2], p2y = qy[2], p3x = qx[3], p3y = qy[3];
    for (var j = 0; j < 3; j++) {
      final tj = j / 2;
      final ex = p0x + (p3x - p0x) * tj, ey = p0y + (p3y - p0y) * tj;
      final fx2 = p1x + (p2x - p1x) * tj, fy2 = p1y + (p2y - p1y) * tj;
      for (var i = 0; i < 3; i++) {
        final ti = i / 2;
        gx[j * 3 + i] = ex + (fx2 - ex) * ti;
        gy[j * 3 + i] = ey + (fy2 - ey) * ti;
      }
    }
    for (var j = 0; j < 2; j++) {
      for (var i = 0; i < 2; i++) {
        final k = ao[0] + (ao[3] - ao[0]) * (j + 0.5) / 2 + (ao[1] - ao[0]) * (i + 0.5) / 2;
        final c = shade(k.clamp(0.4, 1.3), seed * 4 + j * 2 + i);
        final a = j * 3 + i, b = j * 3 + i + 1, cc = (j + 1) * 3 + i + 1, d = (j + 1) * 3 + i;
        out.add(gx[a], gy[a], gx[b], gy[b], gx[cc], gy[cc], c, depth);
        out.add(gx[a], gy[a], gx[cc], gy[cc], gx[d], gy[d], c, depth);
      }
    }
  }

  /// Cheap deterministic noise in -1..1.
  static double _grain(int a) {
    var h = (a * 0x27d4eb2d) & 0x7FFFFFFF;
    h ^= h >> 15;
    h = (h * 0x2545F491) & 0x7FFFFFFF;
    h ^= h >> 13;
    return ((h & 0xFFFF) / 0x8000) - 1;
  }

  /// Wireframe outline of the column the player is aiming at.
  void drawTarget(Canvas canvas, Camera3D cam, BlockWorld world, int bx, int by, Paint paint, {bool placing = false}) {
    final s = world.size;
    final h = world.height(bx, by);
    final z = placing ? h * s : math.max(0.0, (h - 1) * s);
    final top = placing ? (h + 1) * s : h * s;
    final x0 = bx * s, y0 = by * s, x1 = x0 + s, y1 = y0 + s;
    final pts = <Offset>[];
    for (final zz in [z, top]) {
      for (final p in [
        (x0, y0),
        (x1, y0),
        (x1, y1),
        (x0, y1),
      ]) {
        if (!cam.project(p.$1, p.$2, zz)) return;
        pts.add(Offset(cam.px, cam.py));
      }
    }
    final path = Path();
    for (var k = 0; k < 4; k++) {
      final n = (k + 1) % 4;
      path
        ..moveTo(pts[k].dx, pts[k].dy)
        ..lineTo(pts[n].dx, pts[n].dy)
        ..moveTo(pts[4 + k].dx, pts[4 + k].dy)
        ..lineTo(pts[4 + n].dx, pts[4 + n].dy)
        ..moveTo(pts[k].dx, pts[k].dy)
        ..lineTo(pts[4 + k].dx, pts[4 + k].dy);
    }
    canvas.drawPath(path, paint);
  }
}
