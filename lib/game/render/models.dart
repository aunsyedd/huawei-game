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
      buildingFull.add(_building(b, cutaway: false));
      buildingLow.add(_building(b, cutaway: true));
      roofs.add(_roof(b));
    }
  }

  final GameConfig config;
  final MapLayout map;

  final List<Mesh> buildingFull = [], buildingLow = [], roofs = [];

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

  Mesh _building(Building b, {required bool cutaway}) {
    final m = MeshBuilder();
    final h = cutaway ? 22.0 : wallHeight(b);
    final wall = wallColor(b);
    final topC = _shade(wall, 0.45);
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
        m.box(r.left, r.top, 0, r.right, r.bottom, h, wall, top: topC);
        if (!cutaway) {
          // Base trim (darker skirting).
          m.box(r.left - 0.8, r.top - 0.8, 0, r.right + 0.8, r.bottom + 0.8, h * 0.1, _shade(wall, 0.25));
        }
      }
    }
    if (!cutaway) _windows(m, b, h);
    return m.build();
  }

  /// Windows on the outside of every wall (back faces are culled anyway).
  void _windows(MeshBuilder m, Building b, double h) {
    final r = b.rect;
    final glass = const Color(0xFF9FD3EE);
    final frame = const Color(0xFFFAFAFA);
    final shutter = const Color(0xFF8C969C);
    final storeys = b.style == 'town' ? const [0.58, 0.18] : const [0.36];
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
        for (final z0 in storeys) {
          final shop = b.style == 'town' && z0 < 0.5;
          final zb = h * z0 - (shop ? h * 0.08 : 0), zt = h * (z0 + 0.24);
          _panel(m, cx, cy, ux, uy, nx, ny, half + 2, zb - 2, zt + 2, 0.6, frame);
          _panel(m, cx, cy, ux, uy, nx, ny, half, zb, zt, 1.2, shop ? shutter : glass);
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

  Mesh _roof(Building b) {
    final m = MeshBuilder();
    final r = b.rect.inflate(7);
    final h = wallHeight(b) + 1;
    final ridge = h + math.min(r.width, r.height) * 0.3;
    final c = b.roofColor;
    final cap = _shade(c, 0.3);
    if (r.width >= r.height) {
      final mid = r.center.dy;
      const strips = 4;
      for (var k = 0; k < strips; k++) {
        final x0 = r.left + r.width * k / strips, x1 = r.left + r.width * (k + 1) / strips;
        final cx = (x0 + x1) / 2;
        // North slope
        var a = m.vert(x0, r.top, h), bb = m.vert(x1, r.top, h), d = m.vert(x1, mid, ridge), e = m.vert(x0, mid, ridge);
        m.quad(a, bb, d, e, c, cx, mid, h - 40);
        // South slope
        a = m.vert(x0, mid, ridge);
        bb = m.vert(x1, mid, ridge);
        d = m.vert(x1, r.bottom, h);
        e = m.vert(x0, r.bottom, h);
        m.quad(a, bb, d, e, c, cx, mid, h - 40);
      }
      for (final x in [r.left, r.right]) {
        final a = m.vert(x, r.top, h), bb = m.vert(x, r.bottom, h), d = m.vert(x, mid, ridge);
        m.tri(a, bb, d, _shade(c, 0.15), r.center.dx, mid, h);
      }
      m.box(r.left, mid - 2.5, ridge - 1, r.right, mid + 2.5, ridge + 2.5, cap);
    } else {
      final mid = r.center.dx;
      const strips = 4;
      for (var k = 0; k < strips; k++) {
        final y0 = r.top + r.height * k / strips, y1 = r.top + r.height * (k + 1) / strips;
        final cy = (y0 + y1) / 2;
        var a = m.vert(r.left, y0, h),
            bb = m.vert(r.left, y1, h),
            d = m.vert(mid, y1, ridge),
            e = m.vert(mid, y0, ridge);
        m.quad(a, bb, d, e, c, mid, cy, h - 40);
        a = m.vert(mid, y0, ridge);
        bb = m.vert(mid, y1, ridge);
        d = m.vert(r.right, y1, h);
        e = m.vert(r.right, y0, h);
        m.quad(a, bb, d, e, c, mid, cy, h - 40);
      }
      for (final y in [r.top, r.bottom]) {
        final a = m.vert(r.left, y, h), bb = m.vert(r.right, y, h), d = m.vert(mid, y, ridge);
        m.tri(a, bb, d, _shade(c, 0.15), mid, r.center.dy, h);
      }
      m.box(mid - 2.5, r.top, ridge - 1, mid + 2.5, r.bottom, ridge + 2.5, cap);
    }
    if (b.style == 'town') {
      // Air-con unit and water tank on shop-house roofs.
      final p = b.rect.center;
      m.box(p.dx - 30, p.dy + 4, h, p.dx - 12, p.dy + 18, ridge - 6, const Color(0xFFB0BEC5));
      m.cylinder(p.dx + 22, p.dy - 6, ridge - 10, ridge + 6, 7, 7, 6, const Color(0xFF90A4AE));
    }
    return m.build();
  }

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
