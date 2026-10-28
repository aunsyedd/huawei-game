import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A low-poly 3D model: vertices in local space (x forward, y right/south,
/// z up), flat-coloured triangles with outward normals.
class Mesh {
  Mesh(this.verts, this.tris, this.colors, this.normals, [this.anchors, this.glow]);

  final Float32List verts; // x,y,z per vertex
  final Int32List tris; // 3 vertex indices per triangle
  final Int32List colors; // ARGB per triangle
  final Float32List normals; // x,y,z per triangle

  /// Optional per-triangle depth anchor (x, y, z, bias). Decals such as
  /// windows sort by one shared point instead of their own centroid, so a
  /// window is never half hidden by the wall it is painted on. NaN x = none.
  final Float32List? anchors;

  /// Optional per-triangle night glow 0..1 (lit windows, lanterns).
  final Float32List? glow;

  int get vertexCount => verts.length ~/ 3;
  int get triCount => tris.length ~/ 3;
}

/// Builds meshes from simple primitives. Every primitive orients its
/// triangle normals away from its own centre, so winding never matters.
class MeshBuilder {
  final List<double> _v = [];
  final List<int> _t = [];
  final List<int> _c = [];
  final List<double> _n = [];
  final List<double> _a = [];
  final List<double> _g = [];
  bool _hasAnchors = false, _hasGlow = false;

  /// Depth anchor applied to the triangles added while it is set.
  ({double x, double y, double z, double bias})? anchor;

  /// Night glow applied to the triangles added while it is non-zero.
  double glow = 0;

  int vert(double x, double y, double z) {
    _v
      ..add(x)
      ..add(y)
      ..add(z);
    return _v.length ~/ 3 - 1;
  }

  /// Triangle a-b-c; the normal points away from (cx, cy, cz).
  void tri(int a, int b, int c, Color color, double cx, double cy, double cz) {
    final ax = _v[a * 3], ay = _v[a * 3 + 1], az = _v[a * 3 + 2];
    final bx = _v[b * 3], by = _v[b * 3 + 1], bz = _v[b * 3 + 2];
    final qx = _v[c * 3], qy = _v[c * 3 + 1], qz = _v[c * 3 + 2];
    var nx = (by - ay) * (qz - az) - (bz - az) * (qy - ay);
    var ny = (bz - az) * (qx - ax) - (bx - ax) * (qz - az);
    var nz = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax);
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-9) return;
    nx /= len;
    ny /= len;
    nz /= len;
    final mx = (ax + bx + qx) / 3 - cx, my = (ay + by + qy) / 3 - cy, mz = (az + bz + qz) / 3 - cz;
    if (nx * mx + ny * my + nz * mz < 0) {
      nx = -nx;
      ny = -ny;
      nz = -nz;
    }
    _t
      ..add(a)
      ..add(b)
      ..add(c);
    _c.add(color.toARGB32());
    _n
      ..add(nx)
      ..add(ny)
      ..add(nz);
    final an = anchor;
    if (an != null) _hasAnchors = true;
    _a
      ..add(an?.x ?? double.nan)
      ..add(an?.y ?? 0)
      ..add(an?.z ?? 0)
      ..add(an?.bias ?? 0);
    if (glow > 0) _hasGlow = true;
    _g.add(glow);
  }

  void quad(int a, int b, int c, int d, Color color, double cx, double cy, double cz) {
    tri(a, b, c, color, cx, cy, cz);
    tri(a, c, d, color, cx, cy, cz);
  }

  /// Axis-aligned box. [top] colours the lid; [bottom] adds the underside.
  void box(
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    Color color, {
    Color? top,
    bool bottom = false,
    bool lid = true,
  }) {
    final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, cz = (z0 + z1) / 2;
    final p = [
      vert(x0, y0, z0),
      vert(x1, y0, z0),
      vert(x1, y1, z0),
      vert(x0, y1, z0),
      vert(x0, y0, z1),
      vert(x1, y0, z1),
      vert(x1, y1, z1),
      vert(x0, y1, z1),
    ];
    quad(p[0], p[1], p[5], p[4], color, cx, cy, cz);
    quad(p[1], p[2], p[6], p[5], color, cx, cy, cz);
    quad(p[2], p[3], p[7], p[6], color, cx, cy, cz);
    quad(p[3], p[0], p[4], p[7], color, cx, cy, cz);
    if (lid) quad(p[4], p[5], p[6], p[7], top ?? color, cx, cy, cz);
    if (bottom) quad(p[0], p[1], p[2], p[3], color, cx, cy, cz);
  }

  /// Vertical cylinder / cone frustum with [sides] facets and a top cap.
  void cylinder(
    double cx,
    double cy,
    double z0,
    double z1,
    double r0,
    double r1,
    int sides,
    Color color, {
    Color? cap,
    bool topCap = true,
  }) {
    final bottomRing = <int>[], topRing = <int>[];
    for (var i = 0; i < sides; i++) {
      final a = i / sides * math.pi * 2;
      bottomRing.add(vert(cx + math.cos(a) * r0, cy + math.sin(a) * r0, z0));
      topRing.add(vert(cx + math.cos(a) * r1, cy + math.sin(a) * r1, z1));
    }
    final mz = (z0 + z1) / 2;
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      quad(bottomRing[i], bottomRing[j], topRing[j], topRing[i], color, cx, cy, mz);
    }
    if (topCap && r1 > 0.01) {
      final c = vert(cx, cy, z1);
      for (var i = 0; i < sides; i++) {
        tri(c, topRing[i], topRing[(i + 1) % sides], cap ?? color, cx, cy, mz);
      }
    }
  }

  /// Icosahedron "blob" (20 faces), optionally squashed and roughened.
  void blob(
    double cx,
    double cy,
    double cz,
    double rx,
    double ry,
    double rz,
    Color color, {
    double rough = 0,
    int seed = 0,
    Color? alt,
  }) {
    final t = (1 + math.sqrt(5)) / 2;
    final base = [
      [-1, t, 0],
      [1, t, 0],
      [-1, -t, 0],
      [1, -t, 0],
      [0, -1, t],
      [0, 1, t],
      [0, -1, -t],
      [0, 1, -t],
      [t, 0, -1],
      [t, 0, 1],
      [-t, 0, -1],
      [-t, 0, 1],
    ];
    final rng = math.Random(seed);
    final idx = <int>[];
    for (final p in base) {
      final l = math.sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
      final k = 1 + (rough > 0 ? (rng.nextDouble() - 0.5) * rough : 0);
      // Icosahedron coordinates: (a, b, c) -> x, y, z.
      idx.add(vert(cx + p[0] / l * rx * k, cy + p[2] / l * ry * k, cz + p[1] / l * rz * k));
    }
    const faces = [
      [0, 11, 5],
      [0, 5, 1],
      [0, 1, 7],
      [0, 7, 10],
      [0, 10, 11],
      [1, 5, 9],
      [5, 11, 4],
      [11, 10, 2],
      [10, 7, 6],
      [7, 1, 8],
      [3, 9, 4],
      [3, 4, 2],
      [3, 2, 6],
      [3, 6, 8],
      [3, 8, 9],
      [4, 9, 5],
      [2, 4, 11],
      [6, 2, 10],
      [8, 6, 7],
      [9, 8, 1],
    ];
    for (var i = 0; i < faces.length; i++) {
      final f = faces[i];
      tri(idx[f[0]], idx[f[1]], idx[f[2]], (alt != null && i.isOdd) ? alt : color, cx, cy, cz);
    }
  }

  /// A drooping leaf/frond strip from (x0,y0,z0) outwards along angle [a].
  void frond(
    double x0,
    double y0,
    double z0,
    double a,
    double len,
    double width,
    double droop,
    Color color,
    Color tip,
  ) {
    final dx = math.cos(a), dy = math.sin(a);
    final nx = -dy * width, ny = dx * width;
    final root = vert(x0, y0, z0);
    final m = len * 0.5;
    final l1 = vert(x0 + dx * m + nx, y0 + dy * m + ny, z0 + len * 0.12);
    final r1 = vert(x0 + dx * m - nx, y0 + dy * m - ny, z0 + len * 0.12);
    final end = vert(x0 + dx * len, y0 + dy * len, z0 - droop);
    final c = (x0 + dx * m, y0 + dy * m, z0 - 50.0); // normals face up-ish
    tri(root, l1, r1, color, c.$1, c.$2, c.$3);
    tri(l1, end, r1, tip, c.$1, c.$2, c.$3);
  }

  Mesh build() => Mesh(
    Float32List.fromList(_v),
    Int32List.fromList(_t),
    Int32List.fromList(_c),
    Float32List.fromList(_n),
    _hasAnchors ? Float32List.fromList(_a) : null,
    _hasGlow ? Float32List.fromList(_g) : null,
  );

  bool get isEmpty => _t.isEmpty;
}

/// Collects projected triangles from every model in view, sorts them
/// back-to-front and draws them all with one `drawVertices` call.
/// Each corner carries its own colour, which is what makes smooth
/// ambient-occlusion shading on voxel faces free.
class TriangleBatch {
  TriangleBatch(int capacity)
    : _pos = Float32List(capacity * 6),
      _col = Int32List(capacity * 3),
      _depth = Float32List(capacity),
      _outPos = Float32List(capacity * 6),
      _outCol = Int32List(capacity * 3),
      _cap = capacity;

  final int _cap;
  final Float32List _pos, _depth, _outPos;
  final Int32List _col, _outCol;
  int n = 0;
  static const _buckets = 2048;
  final Int32List _count = Int32List(_buckets + 1);
  late final Int32List _order = Int32List(_cap);
  final Paint _paint = Paint();

  bool get full => n >= _cap;
  int get capacity => _cap;

  void add(
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    int color,
    double depth, [
    int? color1,
    int? color2,
  ]) {
    if (n >= _cap) return;
    final i = n * 6;
    _pos[i] = x0;
    _pos[i + 1] = y0;
    _pos[i + 2] = x1;
    _pos[i + 3] = y1;
    _pos[i + 4] = x2;
    _pos[i + 5] = y2;
    final c = n * 3;
    _col[c] = color;
    _col[c + 1] = color1 ?? color;
    _col[c + 2] = color2 ?? color;
    _depth[n] = depth;
    n++;
  }

  /// Painter's algorithm via a bucket sort on depth (far first).
  void draw(Canvas canvas) {
    if (n == 0) return;
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 0; i < n; i++) {
      final d = _depth[i];
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    final scale = (hi - lo) < 1e-6 ? 0.0 : (_buckets - 1) / (hi - lo);
    _count.fillRange(0, _buckets + 1, 0);
    for (var i = 0; i < n; i++) {
      // Far (large depth) goes first: bucket index inverted.
      final b = (_buckets - 1) - ((_depth[i] - lo) * scale).floor();
      _count[b + 1]++;
    }
    for (var b = 0; b < _buckets; b++) {
      _count[b + 1] += _count[b];
    }
    for (var i = 0; i < n; i++) {
      final b = (_buckets - 1) - ((_depth[i] - lo) * scale).floor();
      _order[_count[b]++] = i;
    }
    for (var k = 0; k < n; k++) {
      final i = _order[k];
      final s = i * 6, d = k * 6;
      _outPos[d] = _pos[s];
      _outPos[d + 1] = _pos[s + 1];
      _outPos[d + 2] = _pos[s + 2];
      _outPos[d + 3] = _pos[s + 3];
      _outPos[d + 4] = _pos[s + 4];
      _outPos[d + 5] = _pos[s + 5];
      final sc = i * 3, dc = k * 3;
      _outCol[dc] = _col[sc];
      _outCol[dc + 1] = _col[sc + 1];
      _outCol[dc + 2] = _col[sc + 2];
    }
    final v = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_outPos, 0, n * 6),
      colors: Int32List.sublistView(_outCol, 0, n * 3),
    );
    canvas.drawVertices(v, BlendMode.srcOver, _paint);
    v.dispose();
    n = 0;
  }
}
