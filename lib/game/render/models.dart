import 'dart:math' as math;
import 'dart:ui';

import '../../data/game_config.dart';
import '../components/building.dart';
import '../world/map_layout.dart';
import 'mesh.dart';

Color _shade(Color c, double t) => Color.lerp(c, const Color(0xFF000000), t)!;
Color _tint(Color c, double t) => Color.lerp(c, const Color(0xFFFFFFFF), t)!;

/// Every 3D model in the game, built once from primitives.
/// Local axes: x = forward (facing direction), y = right, z = up.
///
/// The island's own trees, rocks and the characters are built out of cubes so
/// they sit naturally beside the voxel layer; palms keep their fronds so the
/// Malaysian flavour survives the blocky makeover.
class ModelLibrary {
  ModelLibrary(this.config, this.map) {
    for (var i = 0; i < map.buildings.length; i++) {
      final b = map.buildings[i];
      windowLights.add([]);
      buildingFull.add(_building(b, cutaway: false));
      buildingLow.add(_building(b, cutaway: true));
      roofs.add(_roof(b));
    }
    _placeLamps();
  }

  final GameConfig config;
  final MapLayout map;

  final List<Mesh> buildingFull = [], buildingLow = [], roofs = [];

  /// Per building: centres of the windows that light up at night (for bloom).
  final List<List<(double, double, double, double, double)>> windowLights = [];

  /// Street lamps along both pavements of every road: x, y, facing yaw.
  final List<(double, double, double)> lamps = [];

  /// Height of a lamp head, for its glow.
  static const double lampHeight = 74;

  static const skin = Color(0xFFE0AC7E);

  /// Reference sizes the instanced obstacle meshes are built at.
  static const double treeRef = 26, rockRef = 18;

  // ------------------------------------------------------------------ static

  static double wallHeight(Building b) => switch (b.style) {
    'town' => 88.0,
    'kampung' => 64.0,
    'beach' => 50.0,
    _ => 58.0,
  };

  static Color wallColor(Building b) => switch (b.style) {
    'town' => const Color(0xFFF1EBE2),
    'kampung' => const Color(0xFFA0704A),
    'beach' => const Color(0xFFDCC392),
    'plantation' => const Color(0xFF9AACB4),
    _ => const Color(0xFF80604A),
  };

  /// Window storeys as fractions of the wall height (bottom of the glass).
  static List<double> _storeys(Building b) => b.style == 'town' ? const [0.58, 0.18] : const [0.36];

  /// Glass bottom/top of a storey; town ground floors are taller shopfronts.
  static (double, double) _windowSpan(Building b, double h, double z0) {
    final shop = b.style == 'town' && z0 < 0.5;
    return (h * z0 - (shop ? h * 0.08 : 0), h * (z0 + 0.24));
  }

  Mesh _building(Building b, {required bool cutaway}) {
    final m = MeshBuilder();
    final h = cutaway ? 22.0 : wallHeight(b);
    final wall = wallColor(b);
    final topC = _shade(wall, 0.45);
    // Walls are stacked in bands that break exactly at the window edges, so
    // a window never straddles one big wall triangle (painter's sort safe).
    final breaks = <double>[0];
    if (!cutaway) {
      for (final z0 in _storeys(b).reversed) {
        final (zb, zt) = _windowSpan(b, h, z0);
        breaks
          ..add(zb - 2)
          ..add(zt + 2);
      }
    }
    breaks.add(h);
    for (final w in b.walls) {
      // Split long walls so depth sorting stays correct next to characters.
      final horizontal = w.width >= w.height;
      final len = horizontal ? w.width : w.height;
      final parts = math.max(1, (len / 45).ceil());
      for (var k = 0; k < parts; k++) {
        final a = k / parts, c = (k + 1) / parts;
        final r = horizontal
            ? Rect.fromLTRB(w.left + w.width * a, w.top, w.left + w.width * c, w.bottom)
            : Rect.fromLTRB(w.left, w.top + w.height * a, w.right, w.top + w.height * c);
        for (var j = 0; j + 1 < breaks.length; j++) {
          final last = j + 2 == breaks.length;
          // A slightly darker band under the eaves reads as a painted cornice.
          final band = !cutaway && last && b.style == 'town' ? _shade(wall, 0.08) : wall;
          m.box(r.left, r.top, breaks[j], r.right, r.bottom, breaks[j + 1], band, top: topC, lid: last);
        }
      }
      if (!cutaway) {
        // Base trim (darker skirting): low enough to stay one box per wall.
        m.box(w.left - 0.8, w.top - 0.8, 0, w.right + 0.8, w.bottom + 0.8, h * 0.1, _shade(wall, 0.25));
      }
    }
    if (!cutaway) _windows(m, b, h, windowLights.last);
    return m.build();
  }

  /// Windows on the outside of every wall (back faces are culled anyway).
  /// Each window sorts by its own centre, so frame, sill and glass stay in
  /// order and never fight the wall behind them. Some light up at night.
  void _windows(MeshBuilder m, Building b, double h, List<(double, double, double, double, double)> lit) {
    final r = b.rect;
    const glass = Color(0xFF8CCBEA);
    const frame = Color(0xFFFAFAFA);
    const shutter = Color(0xFF8C969C);
    final sill = _shade(wallColor(b), 0.3);
    final rng = math.Random((r.left * 31 + r.top * 17).round());
    void face(double x0, double y0, double x1, double y1, double nx, double ny) {
      final len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
      final n = (len / 70).floor();
      if (n <= 0) return;
      for (var k = 0; k < n; k++) {
        final t = (k + 0.5) / n;
        final cx = x0 + (x1 - x0) * t, cy = y0 + (y1 - y0) * t;
        // Skip the door gap.
        if (_nearDoor(b, cx, cy)) continue;
        final ux = (x1 - x0) / len, uy = (y1 - y0) / len;
        final half = math.min(len / n * 0.25, 15.0);
        for (final z0 in _storeys(b)) {
          final shop = b.style == 'town' && z0 < 0.5;
          final (zb, zt) = _windowSpan(b, h, z0);
          m.anchor = (x: cx + nx * 1.2, y: cy + ny * 1.2, z: (zb + zt) / 2, bias: 10.0);
          _panel(m, cx, cy, ux, uy, nx, ny, half + 2.5, zb - 2, zt + 2, 0.6, frame);
          if (!shop) {
            // Sill: a little ledge that catches the light.
            final sx = cx + nx * 2.5, sy = cy + ny * 2.5;
            final ex = ux.abs() * (half + 4) + nx.abs() * 2.5, ey = uy.abs() * (half + 4) + ny.abs() * 2.5;
            m.box(sx - ex, sy - ey, zb - 4.5, sx + ex, sy + ey, zb - 2, sill, top: _tint(sill, 0.25));
          }
          m.glow = shop ? 0 : (rng.nextDouble() < 0.6 ? 0.9 : 0);
          if (m.glow > 0) lit.add((cx + nx * 4, cy + ny * 4, (zb + zt) / 2, nx, ny));
          _panel(m, cx, cy, ux, uy, nx, ny, half, zb, zt, 1.2, shop ? shutter : glass);
          m.glow = 0;
          if (!shop) {
            // Mullion so the glass reads as a real window.
            _panel(m, cx, cy, ux, uy, nx, ny, 0.9, zb, zt, 1.5, frame);
          } else {
            // Shopfront awning in the roof colour.
            final w0 = half + 6;
            final a = m.vert(cx - ux * w0 + nx * 0.5, cy - uy * w0 + ny * 0.5, zt + 7);
            final bb = m.vert(cx + ux * w0 + nx * 0.5, cy + uy * w0 + ny * 0.5, zt + 7);
            final d = m.vert(cx + ux * w0 + nx * 16, cy + uy * w0 + ny * 16, zt - 1);
            final e = m.vert(cx - ux * w0 + nx * 16, cy - uy * w0 + ny * 16, zt - 1);
            m.quad(a, bb, d, e, b.roofColor, cx - nx * 20, cy - ny * 20, zt - 30);
          }
          m.anchor = null;
        }
      }
    }

    face(r.left, r.bottom, r.right, r.bottom, 0, 1); // south
    face(r.left, r.top, r.right, r.top, 0, -1); // north
    face(r.left, r.top, r.left, r.bottom, -1, 0); // west
    face(r.right, r.top, r.right, r.bottom, 1, 0); // east
  }

  bool _nearDoor(Building b, double x, double y) => (x - b.doorOutside.dx).abs() + (y - b.doorOutside.dy).abs() < 75;

  /// A flat rectangle on a wall face, pushed [out] units away from the wall.
  void _panel(
    MeshBuilder m,
    double cx,
    double cy,
    double ux,
    double uy,
    double nx,
    double ny,
    double half,
    double z0,
    double z1,
    double out,
    Color c,
  ) {
    final ox = cx + nx * out, oy = cy + ny * out;
    final a = m.vert(ox - ux * half, oy - uy * half, z0);
    final b = m.vert(ox + ux * half, oy + uy * half, z0);
    final d = m.vert(ox + ux * half, oy + uy * half, z1);
    final e = m.vert(ox - ux * half, oy - uy * half, z1);
    m.quad(a, b, d, e, c, ox - nx * 10, oy - ny * 10, (z0 + z1) / 2);
  }

  /// Gabled roof. It is drawn with one shared depth key, so triangles land in
  /// the order they are added here: fascia, tile rows, gables, ridge, extras.
  Mesh _roof(Building b) {
    final m = MeshBuilder();
    final r = b.rect.inflate(7);
    final h = wallHeight(b) + 1;
    final ridge = h + math.min(r.width, r.height) * 0.3;
    final c = b.roofColor;
    final cap = _shade(c, 0.3);
    final fascia = _shade(c, 0.45);
    final along = r.width >= r.height;
    // Fascia boards under the eaves.
    if (along) {
      m.box(r.left, r.top, h - 4, r.right, r.top + 2, h, fascia, lid: false);
      m.box(r.left, r.bottom - 2, h - 4, r.right, r.bottom, h, fascia, lid: false);
    } else {
      m.box(r.left, r.top, h - 4, r.left + 2, r.bottom, h, fascia, lid: false);
      m.box(r.right - 2, r.top, h - 4, r.right, r.bottom, h, fascia, lid: false);
    }
    // Tile rows parallel to the ridge, alternating shade, darker at the eave.
    const rows = 5;
    final rowCols = [
      for (var k = 0; k < rows; k++) k == 0 ? _shade(c, 0.16) : (k.isOdd ? _shade(c, 0.05) : _tint(c, 0.04)),
    ];
    final cx0 = r.center.dx, cy0 = r.center.dy;
    // One slope from the eave line at [from] up to the ridge line at [mid].
    void slope(double from, double mid) {
      for (var k = 0; k < rows; k++) {
        final t0 = k / rows, t1 = (k + 1) / rows;
        final za = h + (ridge - h) * t0, zb = h + (ridge - h) * t1;
        final p0 = from + (mid - from) * t0, p1 = from + (mid - from) * t1;
        final int a, bb, d, e;
        if (along) {
          a = m.vert(r.left, p0, za);
          bb = m.vert(r.right, p0, za);
          d = m.vert(r.right, p1, zb);
          e = m.vert(r.left, p1, zb);
        } else {
          a = m.vert(p0, r.top, za);
          bb = m.vert(p0, r.bottom, za);
          d = m.vert(p1, r.bottom, zb);
          e = m.vert(p1, r.top, zb);
        }
        m.quad(a, bb, d, e, rowCols[k], cx0, cy0, h - 40);
      }
    }

    if (along) {
      slope(r.top, cy0);
      slope(r.bottom, cy0);
      for (final x in [r.left, r.right]) {
        final a = m.vert(x, r.top, h), bb = m.vert(x, r.bottom, h), d = m.vert(x, cy0, ridge);
        m.tri(a, bb, d, _shade(c, 0.15), cx0, cy0, h);
      }
      m.box(r.left, cy0 - 2.5, ridge - 1, r.right, cy0 + 2.5, ridge + 2.5, cap);
    } else {
      slope(r.left, cx0);
      slope(r.right, cx0);
      for (final y in [r.top, r.bottom]) {
        final a = m.vert(r.left, y, h), bb = m.vert(r.right, y, h), d = m.vert(cx0, y, ridge);
        m.tri(a, bb, d, _shade(c, 0.15), cx0, cy0, h);
      }
      m.box(cx0 - 2.5, r.top, ridge - 1, cx0 + 2.5, r.bottom, ridge + 2.5, cap);
    }
    // Roof height at a point, so fixtures sit on the slope instead of
    // standing on the ceiling (the shared depth key draws them whole).
    double slopeZ(double x, double y) {
      final t = along ? 1 - (y - cy0).abs() / (r.height / 2) : 1 - (x - cx0).abs() / (r.width / 2);
      return h + (ridge - h) * t.clamp(0.0, 1.0);
    }

    // Fixtures go on the slope facing south (or east), halfway up.
    final fx = along ? cx0 : cx0 + r.width * 0.22, fy = along ? cy0 + r.height * 0.22 : cy0;
    if (b.style == 'town') {
      // Air-con unit and a water tank on shop-house roofs.
      final ax = fx - (along ? 26 : 0), ay = fy - (along ? 0 : 26);
      final za = slopeZ(ax, along ? ay - 7 : ay);
      m.box(ax - 9, ay - 7, za - 2, ax + 9, ay + 7, za + 11, const Color(0xFFB0BEC5), top: const Color(0xFFCFD8DC));
      m.box(ax - 6, ay - 4.5, za + 11, ax + 6, ay + 4.5, za + 11.6, const Color(0xFF78909C));
      final tx = fx + (along ? 28 : 0), ty = fy + (along ? 0 : 28);
      final zt = slopeZ(tx, along ? ty - 7 : ty);
      m.cylinder(tx, ty, zt - 2, zt + 16, 7, 7, 6, const Color(0xFF90A4AE), cap: const Color(0xFFB0BEC5));
    } else if (b.style == 'kampung') {
      // A small chimney vent poking out of the slope.
      final zc = slopeZ(fx, along ? fy - 5 : fy);
      m.box(fx - 5, fy - 5, zc - 2, fx + 5, fy + 5, zc + 16, const Color(0xFF8D6E63), top: const Color(0xFF4E342E));
    }
    return m.build();
  }

  // ------------------------------------------------------------ street lamps

  void _placeLamps() {
    const spacing = 250.0;
    for (final d in map.decor) {
      if (d.kind != 'road') continue;
      final r = d.rect;
      final horizontal = r.width > r.height;
      final len = horizontal ? r.width : r.height;
      for (var t = spacing * 0.5; t < len; t += spacing) {
        for (final side in [-1.0, 1.0]) {
          final x = horizontal ? r.left + t : (side < 0 ? r.left - 10 : r.right + 10);
          final y = horizontal ? (side < 0 ? r.top - 10 : r.bottom + 10) : r.top + t;
          // Not in a junction, inside a building or on top of another road.
          final spot = Rect.fromCircle(center: Offset(x, y), radius: 14);
          if (map.buildings.any((b) => b.rect.inflate(10).overlaps(spot))) continue;
          if (map.decor.any((o) => o.kind == 'road' && !identical(o, d) && o.rect.inflate(30).overlaps(spot))) continue;
          // The arm reaches out over the road.
          final yaw = horizontal ? (side < 0 ? math.pi / 2 : -math.pi / 2) : (side < 0 ? 0.0 : math.pi);
          lamps.add((x, y, yaw));
        }
      }
    }
  }

  /// A street lamp: dark pole, a short arm over the road and a lit head.
  late final Mesh lampPost = () {
    final m = MeshBuilder();
    const pole = Color(0xFF455A64);
    m.box(-1.8, -1.8, 0, 1.8, 1.8, lampHeight + 4, pole);
    m.box(0, -1.4, lampHeight + 2, 16, 1.4, lampHeight + 4.5, pole);
    m.box(10, -3.5, lampHeight - 1, 20, 3.5, lampHeight + 3, const Color(0xFF37474F));
    m.glow = 1;
    m.box(11, -2.8, lampHeight - 2.2, 19, 2.8, lampHeight - 0.5, const Color(0xFFFFF3C4), bottom: true);
    m.glow = 0;
    return m.build();
  }();

  // ------------------------------------------------- instanced nature (cubes)

  static const _leafGreens = [
    Color(0xFF3E9A43),
    Color(0xFF47A84C),
    Color(0xFF358A3A),
    Color(0xFF53B457),
  ];

  /// Four cube-built oak trees, origin at the trunk base, built for a crown
  /// radius of [treeRef] so an obstacle scales by `r / treeRef`.
  late final List<Mesh> trees = [for (var v = 0; v < 4; v++) _cubeTree(v)];

  /// Cheap stand-ins for trees far from the camera or slow devices: the same
  /// silhouette out of a handful of cubes instead of two dozen.
  late final List<Mesh> treesLow = [for (var v = 0; v < 4; v++) _cubeTreeLow(v)];

  Mesh _cubeTreeLow(int variant) {
    final m = MeshBuilder();
    final trunkH = 42.0 + variant * 7;
    const log = Color(0xFF6B4A33);
    m.box(-6.5, -6.5, 0, 6.5, 6.5, trunkH, log, top: _tint(log, 0.1));
    final c = treeRef * 0.46;
    final leaf = _leafGreens[variant % _leafGreens.length];
    m.box(-c * 1.5, -c * 1.5, trunkH - c * 0.4, c * 1.5, c * 1.5, trunkH + c * 0.9, leaf, top: _tint(leaf, 0.16));
    m.box(-c * 0.8, -c * 0.8, trunkH + c * 0.9, c * 0.8, c * 0.8, trunkH + c * 1.8, leaf, top: _tint(leaf, 0.22));
    return m.build();
  }

  Mesh _cubeTree(int variant) {
    final m = MeshBuilder();
    final rng = math.Random(variant * 977 + 13);
    final trunkH = 42.0 + variant * 7;
    const log = Color(0xFF6B4A33);
    const bark = Color(0xFF7C5740);
    final tw = 6.5;
    for (var z = 0.0; z < trunkH; z += 13) {
      final h = math.min(13.0, trunkH - z);
      m.box(-tw, -tw, z, tw, tw, z + h, z % 26 < 13 ? log : bark, top: _tint(log, 0.1));
    }
    // Minecraft-style canopy: a wide slab, a narrower one, then a cap.
    final cube = treeRef * 0.46;
    void layer(double z, int radius, double keep) {
      for (var i = -radius; i <= radius; i++) {
        for (var j = -radius; j <= radius; j++) {
          if (i.abs() == radius && j.abs() == radius && rng.nextDouble() > 0.35) continue;
          if (rng.nextDouble() > keep) continue;
          final c = _leafGreens[(i + j + variant).abs() % _leafGreens.length];
          m.box(
            i * cube - cube / 2,
            j * cube - cube / 2,
            z,
            i * cube + cube / 2,
            j * cube + cube / 2,
            z + cube,
            c,
            top: _tint(c, 0.16),
          );
        }
      }
    }

    layer(trunkH - cube * 0.4, 2, 0.95);
    layer(trunkH + cube * 0.6, 2, 0.7);
    layer(trunkH + cube * 1.6, 1, 0.9);
    return m.build();
  }

  /// Three cube boulders, built for radius [rockRef].
  late final List<Mesh> rocks = [for (var v = 0; v < 3; v++) _cubeRock(v)];

  Mesh _cubeRock(int variant) {
    final m = MeshBuilder();
    final rng = math.Random(variant * 331 + 5);
    const stone = Color(0xFF8A9297);
    final c = rockRef * 0.8;
    m.box(-c, -c, 0, c, c, c * 1.1, stone, top: _tint(stone, 0.12));
    for (var i = 0; i < 3; i++) {
      final s = c * (0.4 + rng.nextDouble() * 0.35);
      final ox = (rng.nextDouble() - 0.5) * c * 1.4, oy = (rng.nextDouble() - 0.5) * c * 1.4;
      final z = c * 1.1;
      final shade = rng.nextBool() ? _shade(stone, 0.12) : _tint(stone, 0.06);
      m.box(ox - s, oy - s, z - s * 0.2, ox + s, oy + s, z + s * 1.3, shade, top: _tint(shade, 0.14));
    }
    return m.build();
  }

  /// Palm with origin at the trunk base; scale by obstacle radius / 14.
  late final Mesh palm = () {
    final m = MeshBuilder();
    const h = 78.0;
    for (var k = 0; k < 3; k++) {
      final z0 = h * k / 3, z1 = h * (k + 1) / 3;
      final x0 = 8.0 * (k / 3) * (k / 3);
      final c = k.isEven ? const Color(0xFF8D6E4F) : const Color(0xFF7A5C42);
      m.cylinder(x0, 0, z0, z1, 4.6 - k * 0.5, 4.1 - k * 0.5, 5, c, topCap: false);
    }
    for (var k = 0; k < 7; k++) {
      final a = k * math.pi * 2 / 7;
      m.frond(
        8,
        0,
        h,
        a,
        42,
        7,
        24,
        k.isEven ? const Color(0xFF2E7D32) : const Color(0xFF43A047),
        const Color(0xFF558B2F),
      );
    }
    m.blob(8, 0, h - 3, 5, 5, 4, const Color(0xFF6D4C41));
    return m.build();
  }();

  /// Planted tree, unit size (scale by trunk radius): a little cube oak.
  late final Mesh sapling = () {
    final m = MeshBuilder();
    const log = Color(0xFF6B4A33);
    m.box(-0.34, -0.34, 0, 0.34, 0.34, 2.8, log, top: const Color(0xFF8A6244));
    const leaf = Color(0xFF47A84C);
    const leafDark = Color(0xFF358A3A);
    const c = 0.82;
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        if (i != 0 && j != 0 && (i + j).isEven) continue;
        final col = (i + j).isEven ? leaf : leafDark;
        m.box(
          i * c - c / 2,
          j * c - c / 2,
          2.5,
          i * c + c / 2,
          j * c + c / 2,
          2.5 + c,
          col,
          top: _tint(col, 0.18),
        );
      }
    }
    m.box(-c / 2, -c / 2, 2.5 + c, c / 2, c / 2, 2.5 + c * 1.9, leaf, top: _tint(leaf, 0.22));
    return m.build();
  }();

  // ------------------------------------------------------------------ characters

  final Map<int, Mesh> _upper = {}, _upperPlain = {}, _legL = {}, _legR = {};

  /// Torso, head, cap and arms in the actor's colour, all cubes.
  /// [detail] adds the face; it is dropped on slow devices.
  Mesh upper(Color c, {bool detail = true}) {
    final cache = detail ? _upper : _upperPlain;
    return cache[c.toARGB32()] ??= _upperMesh(c, detail);
  }

  Mesh _upperMesh(Color c, bool detail) {
    final m = MeshBuilder();
    final dark = _shade(c, 0.4);
    m.box(-5.5, -9, 17, 5.5, 9, 33, c, top: _tint(c, 0.1)); // torso
    m.box(-6, -9.6, 16, 6, 9.6, 19.5, dark); // belt
    m.box(-7, -7.5, 33, 7, 7.5, 47, skin, top: skin); // head
    m.box(-7.4, -7.9, 44.4, 7.4, 7.9, 48.4, dark, top: _shade(c, 0.28)); // cap
    m.box(5, -7.9, 43.4, 13.5, 7.9, 45.6, dark); // cap brim
    if (detail) {
      // Eyes and mouth on the front (+x) face.
      for (final side in [-1.0, 1.0]) {
        m.box(7.05, side * 2.4, 38.5, 7.7, side * 5.6, 41.6, const Color(0xFFF5F5F5));
        m.box(7.1, side * 3.4, 39.2, 7.8, side * 5.2, 41.0, const Color(0xFF3E4A5B));
      }
      m.box(7.05, -2.4, 35.6, 7.6, 2.4, 36.8, const Color(0xFFB07A66));
    }
    // Arms reaching forward to the blaster.
    for (final side in [-1.0, 1.0]) {
      m.box(-1.5, side * 12.8 - 2.2, 22, 13, side * 12.8 + 2.2, 29.4, c, top: _tint(c, 0.08));
      m.box(13, side * 12.8 - 2.0, 22.4, 17.4, side * 12.8 + 2.0, 27.4, skin);
    }
    return m.build();
  }

  Mesh leg(Color c, {required bool left}) {
    final cache = left ? _legL : _legR;
    return cache[c.toARGB32()] ??= () {
      final m = MeshBuilder();
      final pants = _shade(c, 0.5);
      final y0 = left ? -8.6 : 1.4, y1 = left ? -1.4 : 8.6;
      m.box(-3.6, y0, 3.2, 3.6, y1, 17, pants, top: _tint(pants, 0.08));
      m.box(-4.2, y0 - 0.5, 0, 6, y1 + 0.5, 3.6, const Color(0xFF37474F)); // shoe
      return m.build();
    }();
  }

  final Map<String, Mesh> _guns = {};

  Mesh gun(WeaponStats w) => _guns[w.id] ??= () {
    final m = MeshBuilder();
    final len = 28.0 + w.rank * 6;
    final c = w.color;
    m.box(8, -3, 24, 8 + len, 3, 30, c, top: _tint(c, 0.15));
    m.box(8 + len, -2, 25, 12 + len, 2, 29, _shade(c, 0.4)); // nozzle
    m.cylinder(16, 0, 30, 38.0 + w.rank * 2, 5.0 + w.rank, 5.0 + w.rank, 7, _tint(c, 0.45), cap: _tint(c, 0.6)); // tank
    m.box(12, -2, 18, 16, 2, 24, _shade(c, 0.3)); // grip
    return m.build();
  }();

  /// Held while mining: a chunky cube pickaxe.
  late final Mesh pickaxe = () {
    final m = MeshBuilder();
    const wood = Color(0xFF8A6244);
    const iron = Color(0xFFB9C4C9);
    m.box(10, -2, 20, 15, 2, 42, wood, top: _tint(wood, 0.1)); // handle
    m.box(6, -2.4, 38, 21, 2.4, 42.5, iron, top: _tint(iron, 0.18)); // head
    m.box(2, -2.0, 34.5, 7, 2.0, 40, _shade(iron, 0.1)); // back prong
    m.box(20, -2.0, 34.5, 25, 2.0, 40, _shade(iron, 0.05)); // front prong
    return m.build();
  }();

  late final Mesh vest = () {
    final m = MeshBuilder();
    m.box(-6.6, -10, 17, 6.6, 10, 31, const Color(0xFF1E88E5), top: const Color(0xFF42A5F5));
    return m.build();
  }();

  late final Mesh mask = () {
    final m = MeshBuilder();
    m.box(6.6, -6, 35, 10.6, 6, 41, const Color(0xFFECEFF1), top: const Color(0xFFFAFAFA));
    return m.build();
  }();

  // ------------------------------------------------------------------ loot & shots

  final Map<String, Mesh> _loot = {};

  Mesh loot(String refId) => _loot[refId] ??= () {
    final m = MeshBuilder();
    switch (refId) {
      case 'water_bottle':
        m.cylinder(0, 0, -9, 7, 5, 5, 8, const Color(0xFF29B6F6), cap: const Color(0xFF81D4FA));
        m.cylinder(0, 0, 7, 11, 2.5, 2.5, 6, const Color(0xFF1565C0));
      case 'air_mask':
        m.box(-7, -9, -4, 7, 9, 5, const Color(0xFFECEFF1));
        m.box(-2, -12, -1, 2, 12, 2, const Color(0xFF90A4AE));
      case 'seed_pack':
        m.box(-6, -8, -8, 6, 8, 6, const Color(0xFF8D6E63), top: const Color(0xFFA1887F));
        m.blob(0, 0, 10, 5, 3, 3, const Color(0xFF66BB6A));
      case 'vest_1' || 'vest_2':
        final c = refId == 'vest_2' ? const Color(0xFF1565C0) : const Color(0xFF64B5F6);
        m.box(-5, -10, -9, 5, 10, 9, c, top: _tint(c, 0.2));
      default:
        final w = config.weapons[refId];
        final c = w?.color ?? const Color(0xFFFFFFFF);
        final len = 22.0 + (w?.rank ?? 1) * 5;
        m.box(-len / 2, -3, -3, len / 2, 3, 3, c, top: _tint(c, 0.2));
        m.cylinder(-len / 4, 0, 3, 11, 4.5, 4.5, 7, _tint(c, 0.45));
    }
    return m.build();
  }();

  /// A floating cube of one block type, for dropped-block pickups.
  final Map<int, Mesh> _blockItems = {};

  Mesh blockItem(BlockType t) => _blockItems[t.index] ??= () {
    final m = MeshBuilder();
    m.box(-7, -7, -7, 7, 7, 7, t.side, top: t.top, bottom: true);
    return m.build();
  }();

  final Map<int, Mesh> _shots = {};

  Mesh shot(Color c) => _shots[c.toARGB32()] ??= () {
    final m = MeshBuilder();
    m.blob(0, 0, 0, 1, 1, 1, _tint(c, 0.25), alt: c);
    return m.build();
  }();
}
