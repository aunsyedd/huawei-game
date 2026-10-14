import 'dart:math' as math;
import 'dart:ui';

import '../../data/game_config.dart';
import '../components/building.dart';
import '../systems/spatial_grid.dart';

/// Solid round things: forest trees, palms, rocks.
class Obstacle {
  Obstacle(this.x, this.y, this.r, this.kind);
  final double x, y, r;
  final String kind;
}

/// Purely visual ground details.
class Decor {
  Decor(this.rect, this.kind);
  final Rect rect;
  final String kind;
}

/// The island, generated deterministically from `map.json`.
class MapLayout {
  MapLayout._(this.config);

  final MapConfig config;
  final List<Building> buildings = [];
  final List<Rect> walls = [];
  final List<Obstacle> obstacles = [];
  final List<Decor> decor = [];
  final List<Offset> outdoorLootPoints = [];
  late final StaticGrid wallGrid;
  late final StaticGrid obstacleGrid;

  double get width => config.width;
  double get height => config.height;

  static const _townRoofs = [
    Color(0xFFC62828),
    Color(0xFF1565C0),
    Color(0xFFF9A825),
    Color(0xFF00897B),
    Color(0xFF6D4C41),
  ];

  factory MapLayout.generate(MapConfig cfg, {int outdoorLoot = 70}) {
    final m = MapLayout._(cfg);
    final rng = math.Random(cfg.seed);
    m._generate(rng, outdoorLoot);
    return m;
  }

  void _generate(math.Random rng, int outdoorLoot) {
    double between(List<double> r) => r[0] + rng.nextDouble() * (r[1] - r[0]);

    // Town roads first so buildings avoid them.
    for (final a in config.areas.where((a) => a.type == 'town')) {
      decor.add(Decor(Rect.fromLTWH(a.rect.left, a.rect.center.dy - 40, a.rect.width, 80), 'road'));
      decor.add(Decor(Rect.fromLTWH(a.rect.center.dx - 40, a.rect.top, 80, a.rect.height), 'road'));
    }
    for (final a in config.areas.where((a) => a.type == 'kampung')) {
      decor.add(Decor(Rect.fromLTWH(a.rect.left, a.rect.center.dy - 25, a.rect.width, 50), 'path'));
    }

    // Buildings.
    for (final a in config.areas) {
      var placed = 0;
      for (var tries = 0; tries < 400 && placed < a.buildings; tries++) {
        final w = between(a.buildingW), h = between(a.buildingH);
        final inner = a.rect.deflate(70);
        final x = inner.left + rng.nextDouble() * (inner.width - w);
        final y = inner.top + rng.nextDouble() * (inner.height - h);
        final r = Rect.fromLTWH(x, y, w, h);
        final padded = r.inflate(80);
        if (buildings.any((b) => b.rect.overlaps(padded))) continue;
        if (decor.any((d) => d.rect.overlaps(r.inflate(20)))) continue;
        buildings.add(_makeBuilding(r, a.type, rng));
        placed++;
      }
    }
    for (final b in buildings) {
      walls.addAll(b.walls);
    }

    // Obstacles.
    bool free(double x, double y, double r) {
      if (x < r + 20 || y < r + 20 || x > width - r - 20 || y > height - r - 20) {
        return false;
      }
      for (final b in buildings) {
        if (b.rect.inflate(r + 45).contains(Offset(x, y))) return false;
      }
      for (final d in decor) {
        if (d.kind == 'road' && d.rect.inflate(r).contains(Offset(x, y))) {
          return false;
        }
      }
      for (final o in obstacles) {
        final dx = o.x - x, dy = o.y - y, min = o.r + r + 30;
        if (dx * dx + dy * dy < min * min) return false;
      }
      return true;
    }

    for (final a in config.areas) {
      if (a.obstacle == 'palm_grid') {
        final s = a.gridSpacing;
        for (var y = a.rect.top + s / 2; y < a.rect.bottom; y += s) {
          for (var x = a.rect.left + s / 2; x < a.rect.right; x += s) {
            final jx = x + (rng.nextDouble() - 0.5) * 24;
            final jy = y + (rng.nextDouble() - 0.5) * 24;
            final r = between(a.obstacleRadius);
            if (free(jx, jy, r)) obstacles.add(Obstacle(jx, jy, r, 'palm'));
          }
          decor.add(Decor(Rect.fromLTWH(a.rect.left, y + s / 2 - 6, a.rect.width, 12), 'row'));
        }
        continue;
      }
      var placed = 0;
      for (var tries = 0; tries < a.obstacles * 20 && placed < a.obstacles; tries++) {
        final r = between(a.obstacleRadius);
        final x = a.rect.left + rng.nextDouble() * a.rect.width;
        final y = a.rect.top + rng.nextDouble() * a.rect.height;
        if (!free(x, y, r)) continue;
        obstacles.add(Obstacle(x, y, r, a.obstacle));
        placed++;
      }
      // Ground blotches for texture.
      final blotches = (a.rect.width * a.rect.height / 60000).round();
      for (var i = 0; i < blotches; i++) {
        final w = 40 + rng.nextDouble() * 120;
        decor.add(
          Decor(
            Rect.fromLTWH(
              a.rect.left + rng.nextDouble() * (a.rect.width - w),
              a.rect.top + rng.nextDouble() * (a.rect.height - w),
              w,
              w * (0.5 + rng.nextDouble() * 0.5),
            ),
            'blotch_${a.type}',
          ),
        );
      }
    }

    wallGrid = StaticGrid(width, height, 200);
    for (var i = 0; i < walls.length; i++) {
      final w = walls[i];
      wallGrid.insertBox(i, w.left, w.top, w.right, w.bottom);
    }
    obstacleGrid = StaticGrid(width, height, 200);
    for (var i = 0; i < obstacles.length; i++) {
      final o = obstacles[i];
      obstacleGrid.insertBox(i, o.x - o.r, o.y - o.r, o.x + o.r, o.y + o.r);
    }

    for (var i = 0; i < outdoorLoot; i++) {
      final p = randomFreePoint(rng, outdoorOnly: true);
      outdoorLootPoints.add(p);
    }
  }

  Building _makeBuilding(Rect r, String area, math.Random rng) {
    final t = config.wallThickness, dw = config.doorWidth;
    final side = rng.nextInt(4);
    final walls = <Rect>[];
    // Horizontal walls (top/bottom) and vertical (left/right), split at door.
    void hWall(double y, bool door) {
      if (!door) {
        walls.add(Rect.fromLTWH(r.left, y, r.width, t));
      } else {
        final mid = r.center.dx;
        walls.add(Rect.fromLTRB(r.left, y, mid - dw / 2, y + t));
        walls.add(Rect.fromLTRB(mid + dw / 2, y, r.right, y + t));
      }
    }

    void vWall(double x, bool door) {
      if (!door) {
        walls.add(Rect.fromLTWH(x, r.top, t, r.height));
      } else {
        final mid = r.center.dy;
        walls.add(Rect.fromLTRB(x, r.top, x + t, mid - dw / 2));
        walls.add(Rect.fromLTRB(x, mid + dw / 2, x + t, r.bottom));
      }
    }

    hWall(r.top, side == 0);
    vWall(r.right - t, side == 1);
    hWall(r.bottom - t, side == 2);
    vWall(r.left, side == 3);

    final c = r.center;
    late Offset out, inn;
    switch (side) {
      case 0:
        out = Offset(c.dx, r.top - 40);
        inn = Offset(c.dx, r.top + 40);
      case 1:
        out = Offset(r.right + 40, c.dy);
        inn = Offset(r.right - 40, c.dy);
      case 2:
        out = Offset(c.dx, r.bottom + 40);
        inn = Offset(c.dx, r.bottom - 40);
      default:
        out = Offset(r.left - 40, c.dy);
        inn = Offset(r.left + 40, c.dy);
    }
    final inner = r.deflate(t + 26);
    final loot = [
      for (var i = 0; i < 3; i++)
        Offset(inner.left + rng.nextDouble() * inner.width, inner.top + rng.nextDouble() * inner.height),
    ];
    final (roof, floor) = switch (area) {
      'town' => (_townRoofs[rng.nextInt(_townRoofs.length)], const Color(0xFFECEFF1)),
      'kampung' => (const Color(0xFF8D4C2F), const Color(0xFFBCAAA4)),
      'plantation' => (const Color(0xFF78909C), const Color(0xFFA1887F)),
      'beach' => (const Color(0xFFD7B56D), const Color(0xFFEFE3C8)),
      _ => (const Color(0xFF5D4037), const Color(0xFF8D6E63)),
    };
    return Building(
      rect: r,
      style: area,
      doorSide: side,
      walls: walls,
      doorOutside: out,
      doorInside: inn,
      lootPoints: loot,
      roofColor: roof,
      floorColor: floor,
    );
  }

  String areaAt(double x, double y) {
    for (final a in config.areas) {
      if (a.rect.contains(Offset(x, y))) return a.type;
    }
    return 'beach';
  }

  Building? buildingAt(double x, double y) {
    for (final b in buildings) {
      if (b.contains(x, y)) return b;
    }
    return null;
  }

  /// True when a circle at (x, y) overlaps no wall or obstacle.
  bool isFree(double x, double y, double r) {
    if (x < r || y < r || x > width - r || y > height - r) return false;
    for (final i in wallGrid.queryBox(x - r, y - r, x + r, y + r)) {
      final w = walls[i];
      final nx = x.clamp(w.left, w.right), ny = y.clamp(w.top, w.bottom);
      final dx = x - nx, dy = y - ny;
      if (dx * dx + dy * dy < r * r) return false;
    }
    for (final i in obstacleGrid.queryBox(x - r, y - r, x + r, y + r)) {
      final o = obstacles[i];
      final dx = x - o.x, dy = y - o.y, m = r + o.r;
      if (dx * dx + dy * dy < m * m) return false;
    }
    return true;
  }

  Offset randomFreePoint(math.Random rng, {bool outdoorOnly = false, double r = 24}) {
    for (var i = 0; i < 500; i++) {
      final x = 60 + rng.nextDouble() * (width - 120);
      final y = 60 + rng.nextDouble() * (height - 120);
      if (outdoorOnly && buildings.any((b) => b.rect.inflate(30).contains(Offset(x, y)))) {
        continue;
      }
      if (isFree(x, y, r)) return Offset(x, y);
    }
    return Offset(width / 2, height / 2);
  }

  /// Pushes the circle at ([pos]) out of walls, obstacles and map edges.
  /// Writes the result into [out] as (x, y).
  void resolveCircle(double x, double y, double r, List<double> out) {
    for (final i in wallGrid.queryBox(x - r, y - r, x + r, y + r)) {
      final w = walls[i];
      final nx = x.clamp(w.left, w.right), ny = y.clamp(w.top, w.bottom);
      var dx = x - nx, dy = y - ny;
      final d2 = dx * dx + dy * dy;
      if (d2 >= r * r) continue;
      if (d2 < 0.0001) {
        // Centre inside the wall: push out along the shortest axis.
        final pl = x - w.left, pr = w.right - x, pt = y - w.top, pb = w.bottom - y;
        final m = math.min(math.min(pl, pr), math.min(pt, pb));
        if (m == pl) {
          x = w.left - r;
        } else if (m == pr) {
          x = w.right + r;
        } else if (m == pt) {
          y = w.top - r;
        } else {
          y = w.bottom + r;
        }
        continue;
      }
      final d = math.sqrt(d2);
      x += dx / d * (r - d);
      y += dy / d * (r - d);
    }
    for (final i in obstacleGrid.queryBox(x - r, y - r, x + r, y + r)) {
      final o = obstacles[i];
      final dx = x - o.x, dy = y - o.y, m = r + o.r;
      final d2 = dx * dx + dy * dy;
      if (d2 >= m * m || d2 < 0.0001) continue;
      final d = math.sqrt(d2);
      x += dx / d * (m - d);
      y += dy / d * (m - d);
    }
    out[0] = x.clamp(r, width - r);
    out[1] = y.clamp(r, height - r);
  }

  /// True when a point is inside a wall or obstacle (projectile hit test).
  bool pointBlocked(double x, double y, double pad) {
    if (x < 0 || y < 0 || x > width || y > height) return true;
    final c = wallGrid.cells[wallGrid.cy(y) * wallGrid.cols + wallGrid.cx(x)];
    for (final i in c) {
      final w = walls[i];
      if (x > w.left - pad && x < w.right + pad && y > w.top - pad && y < w.bottom + pad) {
        return true;
      }
    }
    final oc = obstacleGrid.cells[obstacleGrid.cy(y) * obstacleGrid.cols + obstacleGrid.cx(x)];
    for (final i in oc) {
      final o = obstacles[i];
      final dx = x - o.x, dy = y - o.y, m = o.r + pad;
      if (dx * dx + dy * dy < m * m) return true;
    }
    return false;
  }

  /// Line of sight: false if a wall blocks the segment. Obstacles are ignored
  /// (you can see past a palm, you just might hit it).
  bool lineOfSight(double x0, double y0, double x1, double y1) {
    for (final i in wallGrid.queryBox(x0, y0, x1, y1)) {
      if (_segmentHitsRect(x0, y0, x1, y1, walls[i])) return false;
    }
    return true;
  }

  static bool _segmentHitsRect(double x0, double y0, double x1, double y1, Rect r) {
    var tMin = 0.0, tMax = 1.0;
    final dx = x1 - x0, dy = y1 - y0;
    bool clip(double p, double q) {
      if (p.abs() < 1e-9) return q >= 0;
      final t = q / p;
      if (p < 0) {
        if (t > tMax) return false;
        if (t > tMin) tMin = t;
      } else {
        if (t < tMin) return false;
        if (t < tMax) tMax = t;
      }
      return true;
    }

    return clip(-dx, x0 - r.left) &&
        clip(dx, r.right - x0) &&
        clip(-dy, y0 - r.top) &&
        clip(dy, r.bottom - y0) &&
        tMin <= tMax;
  }
}
