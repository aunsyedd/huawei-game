import 'dart:ui';

/// A walled building with one door. Walls block movement and projectiles;
/// the roof hides whoever is inside until the player walks in.
class Building {
  Building({
    required this.rect,
    required this.style,
    required this.doorSide,
    required this.walls,
    required this.doorOutside,
    required this.doorInside,
    required this.lootPoints,
    required this.roofColor,
    required this.floorColor,
  });

  final Rect rect;
  final String style;

  /// 0 top, 1 right, 2 bottom, 3 left.
  final int doorSide;
  final List<Rect> walls;
  final Offset doorOutside, doorInside;
  final List<Offset> lootPoints;
  final Color roofColor, floorColor;

  bool contains(double x, double y) => x > rect.left && x < rect.right && y > rect.top && y < rect.bottom;
}
