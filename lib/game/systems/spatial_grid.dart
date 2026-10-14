import 'dart:math' as math;

/// Uniform grid of buckets, rebuilt every frame for moving things
/// (actors, trees). Buckets keep their capacity, so clearing is cheap.
class SpatialHash<T> {
  SpatialHash(double width, double height, this.cellSize)
    : cols = (width / cellSize).ceil() + 1,
      rows = (height / cellSize).ceil() + 1 {
    _cells = List.generate(cols * rows, (_) => <T>[]);
  }

  final double cellSize;
  final int cols, rows;
  late final List<List<T>> _cells;

  void clear() {
    for (final c in _cells) {
      c.clear();
    }
  }

  int _cx(double x) => (x / cellSize).floor().clamp(0, cols - 1);
  int _cy(double y) => (y / cellSize).floor().clamp(0, rows - 1);

  void insert(T item, double x, double y) => _cells[_cy(y) * cols + _cx(x)].add(item);

  /// Calls [visit] for every item in cells touching the circle (x, y, r).
  /// Stops early when [visit] returns true.
  void query(double x, double y, double r, bool Function(T item) visit) {
    final x0 = _cx(x - r), x1 = _cx(x + r);
    final y0 = _cy(y - r), y1 = _cy(y + r);
    for (var cy = y0; cy <= y1; cy++) {
      for (var cx = x0; cx <= x1; cx++) {
        for (final item in _cells[cy * cols + cx]) {
          if (visit(item)) return;
        }
      }
    }
  }
}

/// Static grid of indices into wall / obstacle lists. Built once per map.
class StaticGrid {
  StaticGrid(double width, double height, this.cellSize)
    : cols = (width / cellSize).ceil() + 1,
      rows = (height / cellSize).ceil() + 1 {
    cells = List.generate(cols * rows, (_) => <int>[]);
  }

  final double cellSize;
  final int cols, rows;
  late final List<List<int>> cells;

  int cx(double x) => (x / cellSize).floor().clamp(0, cols - 1);
  int cy(double y) => (y / cellSize).floor().clamp(0, rows - 1);

  void insertBox(int index, double l, double t, double r, double b) {
    for (var y = cy(t); y <= cy(b); y++) {
      for (var x = cx(l); x <= cx(r); x++) {
        cells[y * cols + x].add(index);
      }
    }
  }

  /// Collects indices in cells overlapping the box into [out] (cleared
  /// first; indices may repeat). Reusing [out] keeps this allocation-free.
  List<int> gather(double l, double t, double r, double b, List<int> out) {
    out.clear();
    final x0 = cx(math.min(l, r)), x1 = cx(math.max(l, r));
    final y0 = cy(math.min(t, b)), y1 = cy(math.max(t, b));
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        out.addAll(cells[y * cols + x]);
      }
    }
    return out;
  }
}
