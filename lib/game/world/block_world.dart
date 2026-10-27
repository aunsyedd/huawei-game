import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../data/game_config.dart';
import 'map_layout.dart';

/// The voxel layer: a sparse grid of cubes sitting on top of the island.
///
/// Blocks stack in columns from the ground up (you always mine the top block
/// and place on top of it), so one column is fully described by its height
/// plus the type of each cube. Everything here is plain Dart so headless
/// tests can mine and build without a renderer.
///
/// Grid coordinates: `bx` east, `by` south, `bz` up. Only columns that hold at
/// least one block exist in [heights], which keeps a 3000x3000 island cheap.
class BlockWorld {
  BlockWorld(this.cfg, this.cols, this.rows);

  /// Builds the island's starting resource patches: logs in the forest, stone
  /// in town, sand on the beach… Deterministic for a given [rng].
  factory BlockWorld.generate(BlockConfig cfg, MapLayout map, String mode, math.Random rng) {
    final w = BlockWorld(cfg, (map.width / cfg.size).ceil(), (map.height / cfg.size).ceil());
    for (final def in cfg.nodes[mode] ?? const <BlockNodeDef>[]) {
      final type = cfg.indexOf[def.block];
      if (type == null) continue;
      final areas = map.config.areas.where((a) => a.type == def.area).toList();
      if (areas.isEmpty) continue;
      for (var c = 0; c < def.clusters; c++) {
        final area = areas[rng.nextInt(areas.length)];
        final count = def.size[0] + rng.nextInt(def.size[1] - def.size[0] + 1);
        // Grow the patch as a random walk so it looks like a natural outcrop.
        var bx = w.gx(area.rect.left + rng.nextDouble() * area.rect.width);
        var by = w.gy(area.rect.top + rng.nextDouble() * area.rect.height);
        for (var i = 0; i < count; i++) {
          final stack = def.stack[0] + rng.nextInt(def.stack[1] - def.stack[0] + 1);
          if (w._clearOutdoors(bx, by, map)) {
            for (var z = 0; z < stack; z++) {
              w.set(bx, by, z, type);
            }
          }
          bx += rng.nextInt(3) - 1;
          by += rng.nextInt(3) - 1;
        }
      }
    }
    return w;
  }

  final BlockConfig cfg;
  final int cols, rows;

  /// Packed cell key -> block type index + 1.
  final Map<int, int> cells = {};

  /// Packed column key -> number of stacked blocks.
  final Map<int, int> heights = {};

  /// Columns holding a clean-air filter block, for [bubbleAt].
  final Set<int> filters = {};

  /// Blaster damage taken by the top block of a column.
  final Map<int, double> _damage = {};

  /// Bumped on every change so the renderer can rebuild cached geometry.
  int revision = 0;

  double get size => cfg.size;
  int get blockCount => cells.length;

  // ----------------------------------------------------------------- keys

  static int columnKey(int bx, int by) => (by << 10) | bx;
  static int cellKey(int bx, int by, int bz) => (bz << 20) | (by << 10) | bx;
  static int keyX(int column) => column & 0x3FF;
  static int keyY(int column) => (column >> 10) & 0x3FF;

  bool inBounds(int bx, int by) => bx >= 0 && by >= 0 && bx < cols && by < rows;

  /// Grid column for a world x / y.
  int gx(double x) => (x / size).floor().clamp(0, cols - 1);
  int gy(double y) => (y / size).floor().clamp(0, rows - 1);

  /// Centre of a block in world units.
  double wx(int bx) => (bx + 0.5) * size;
  double wy(int by) => (by + 0.5) * size;

  // ----------------------------------------------------------------- reads

  int height(int bx, int by) => inBounds(bx, by) ? (heights[columnKey(bx, by)] ?? 0) : 0;

  /// Block type index at a cell, or -1 for air.
  int typeAt(int bx, int by, int bz) => (cells[cellKey(bx, by, bz)] ?? 0) - 1;

  BlockType? top(int bx, int by) {
    final h = height(bx, by);
    if (h == 0) return null;
    final t = typeAt(bx, by, h - 1);
    return t < 0 ? null : cfg.types[t];
  }

  /// True where a block stands on the ground: it stops movement and shots
  /// exactly like a wall does.
  bool solidAt(double x, double y) => height(gx(x), gy(y)) > 0;

  /// Clean air from filter blocks, so building a filter wall shelters you.
  bool bubbleAt(double x, double y) {
    for (final col in filters) {
      final bx = keyX(col), by = keyY(col);
      var r = 0.0;
      final h = height(bx, by);
      for (var z = 0; z < h; z++) {
        final t = typeAt(bx, by, z);
        if (t >= 0 && cfg.types[t].bubble > r) r = cfg.types[t].bubble;
      }
      if (r <= 0) continue;
      final dx = wx(bx) - x, dy = wy(by) - y;
      if (dx * dx + dy * dy < r * r) return true;
    }
    return false;
  }

  /// Generated patches keep well clear of walls, doorways and buildings so
  /// they can never seal a bot in. Players may build anywhere legal.
  bool _clearOutdoors(int bx, int by, MapLayout map) {
    if (!inBounds(bx, by) || height(bx, by) > 0) return false;
    final x = wx(bx), y = wy(by);
    if (x < size * 2 || y < size * 2 || x > map.width - size * 2 || y > map.height - size * 2) return false;
    for (final b in map.buildings) {
      if (b.rect.inflate(size * 2.5).contains(Offset(x, y))) return false;
    }
    for (final d in map.decor) {
      if (d.kind == 'road' && d.rect.inflate(size).contains(Offset(x, y))) return false;
    }
    return map.isFree(x, y, size);
  }

  /// True when any block column overlaps the circle at (x, y).
  bool overlapsCircle(double x, double y, double r) {
    final x0 = gx(x - r), x1 = gx(x + r), y0 = gy(y - r), y1 = gy(y + r);
    for (var by = y0; by <= y1; by++) {
      for (var bx = x0; bx <= x1; bx++) {
        if (height(bx, by) == 0) continue;
        final l = bx * size, t = by * size;
        final dx = x - x.clamp(l, l + size), dy = y - y.clamp(t, t + size);
        if (dx * dx + dy * dy < r * r) return true;
      }
    }
    return false;
  }

  /// Nothing may be built on a wall, an obstacle or outside the island.
  bool canBuildAt(int bx, int by, MapLayout map) {
    if (!inBounds(bx, by)) return false;
    if (height(bx, by) >= cfg.maxHeight) return false;
    final x = wx(bx), y = wy(by);
    if (x < size || y < size || x > map.width - size || y > map.height - size) return false;
    if (height(bx, by) > 0) return true; // already a legal column
    return map.isFree(x, y, size * 0.45);
  }

  // ---------------------------------------------------------------- writes

  /// Low-level write used by generation and by [place].
  void set(int bx, int by, int bz, int type) {
    if (!inBounds(bx, by) || bz < 0 || bz >= cfg.maxHeight) return;
    cells[cellKey(bx, by, bz)] = type + 1;
    final col = columnKey(bx, by);
    final h = heights[col] ?? 0;
    if (bz + 1 > h) heights[col] = bz + 1;
    if (cfg.types[type].bubble > 0) filters.add(col);
    revision++;
  }

  /// Puts a block on top of the column; returns false if it does not fit.
  bool place(int bx, int by, int type, MapLayout map) {
    if (!canBuildAt(bx, by, map)) return false;
    set(bx, by, height(bx, by), type);
    return true;
  }

  /// Removes the top block and returns the type index it drops, or -1.
  int mineTop(int bx, int by) {
    final h = height(bx, by);
    if (h == 0) return -1;
    final col = columnKey(bx, by);
    final t = typeAt(bx, by, h - 1);
    cells.remove(cellKey(bx, by, h - 1));
    if (h == 1) {
      heights.remove(col);
      filters.remove(col);
    } else {
      heights[col] = h - 1;
      if (!_columnHasFilter(bx, by)) filters.remove(col);
    }
    _damage.remove(col);
    revision++;
    if (t < 0) return -1;
    final drop = cfg.types[t].drop;
    return cfg.indexOf[drop] ?? t;
  }

  bool _columnHasFilter(int bx, int by) {
    final h = height(bx, by);
    for (var z = 0; z < h; z++) {
      final t = typeAt(bx, by, z);
      if (t >= 0 && cfg.types[t].bubble > 0) return true;
    }
    return false;
  }

  /// Blaster hit on a column: enough damage breaks the top block off.
  /// Returns the type index of the block that broke, or -1.
  int damageColumn(int bx, int by, double amount) {
    final t = top(bx, by);
    if (t == null) return -1;
    final col = columnKey(bx, by);
    final taken = (_damage[col] ?? 0) + amount;
    // Harder blocks soak more; leaves pop off almost at once.
    if (taken < 24 + t.hardness * 55) {
      _damage[col] = taken;
      return -1;
    }
    mineTop(bx, by);
    return t.index;
  }

  /// How battered the top block of a column looks, 0..1 (crack overlay).
  double crackAt(int bx, int by) {
    final t = top(bx, by);
    if (t == null) return 0;
    final taken = _damage[columnKey(bx, by)] ?? 0;
    return (taken / (24 + t.hardness * 55)).clamp(0.0, 1.0);
  }

  /// Seconds of mining for the top block of a column.
  double mineTime(int bx, int by) {
    final t = top(bx, by);
    return t == null ? 0 : math.max(0.12, t.hardness / cfg.mineSpeed);
  }

  /// Pushes a circle out of every block column it overlaps, like a wall.
  /// Writes the corrected position into [out] as (x, y).
  void resolveCircle(double x, double y, double r, List<double> out) {
    final x0 = gx(x - r), x1 = gx(x + r), y0 = gy(y - r), y1 = gy(y + r);
    for (var by = y0; by <= y1; by++) {
      for (var bx = x0; bx <= x1; bx++) {
        if (height(bx, by) == 0) continue;
        final l = bx * size, t = by * size, rr = l + size, b = t + size;
        final nx = x.clamp(l, rr), ny = y.clamp(t, b);
        var dx = x - nx, dy = y - ny;
        final d2 = dx * dx + dy * dy;
        if (d2 >= r * r) continue;
        if (d2 < 0.0001) {
          // Centre inside the cube: leave along the shortest axis.
          final pl = x - l, pr = rr - x, pt = y - t, pb = b - y;
          final m = math.min(math.min(pl, pr), math.min(pt, pb));
          if (m == pl) {
            x = l - r;
          } else if (m == pr) {
            x = rr + r;
          } else if (m == pt) {
            y = t - r;
          } else {
            y = b + r;
          }
          continue;
        }
        final d = math.sqrt(d2);
        x += dx / d * (r - d);
        y += dy / d * (r - d);
      }
    }
    out[0] = x;
    out[1] = y;
  }

  /// True when a solid column blocks the segment (line of sight / splash).
  bool blocksLine(double x0, double y0, double x1, double y1) {
    final dx = x1 - x0, dy = y1 - y0;
    final steps = (math.sqrt(dx * dx + dy * dy) / (size * 0.5)).ceil();
    for (var i = 1; i < steps; i++) {
      final t = i / steps;
      if (solidAt(x0 + dx * t, y0 + dy * t)) return true;
    }
    return false;
  }
}
