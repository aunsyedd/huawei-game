import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A real 3D orbit camera: it looks at a point on the ground from [distance]
/// away, turned by [yaw] and tilted by [tilt] (the angle from straight down).
/// Everything in the world is projected through it, and the flat ground is
/// drawn through [matrix], the same transform expressed as a 4x4 the canvas
/// can apply to a plane.
///
/// World axes: x east, y south, z up. At `yaw == 0` the camera looks north
/// (towards -y) and the projection matches the classic Haze Royale view.
class Camera3D {
  /// Point on the ground the camera looks at.
  double targetX = 0, targetY = 0;

  /// Heading in radians (0 = looking north), tilt from straight down.
  double yaw = 0, tilt = defaultTilt;

  /// Eye distance to the target and the zoom (field of view) factor.
  double distance = 1200, zoom = 1;

  double viewW = 0, viewH = 0;

  /// Where the look-at point sits vertically on screen (0 = top, 1 = bottom).
  double horizonBias = 0.6;

  static const double defaultTilt = 0.82; // ~47 degrees off vertical
  static const double minTilt = 0.42, maxTilt = 1.30;

  // ---- Derived basis, refreshed by [update] ----
  /// Horizontal look direction.
  double fx = 0, fy = -1;

  /// Screen-right axis (on the ground).
  double rx = 1, ry = 0;

  /// Screen-up axis.
  double ux = 0, uy = 0, uz = 0;

  /// Depth axis: `w = distance - (d . n)`.
  double nx = 0, ny = 0, nz = 0;

  double sinT = 0, cosT = 1;
  double f = 1, w2 = 0, h0 = 0;

  /// Eye position in world units (used for back-face culling and specular).
  double eyeX = 0, eyeY = 0, eyeZ = 0;

  /// Screen y where the ground plane vanishes. Usually far above the view.
  double horizonY = double.negativeInfinity;

  /// Ground-plane transform for `canvas.transform` (column-major).
  final Float64List matrix = Float64List(16);

  // ---- Last [project] result ----
  double px = 0, py = 0, ps = 1;

  Offset get projected => Offset(px, py);

  void update() {
    sinT = math.sin(tilt);
    cosT = math.cos(tilt);
    final cy = math.cos(yaw), sy = math.sin(yaw);
    fx = sy;
    fy = -cy;
    rx = cy;
    ry = sy;
    ux = fx * cosT;
    uy = fy * cosT;
    uz = sinT;
    nx = -fx * sinT;
    ny = -fy * sinT;
    nz = cosT;
    f = zoom * distance;
    w2 = viewW / 2;
    h0 = viewH * horizonBias;
    eyeX = targetX - fx * distance * sinT;
    eyeY = targetY - fy * distance * sinT;
    eyeZ = distance * cosT;
    horizonY = sinT < 1e-6 ? double.negativeInfinity : h0 - f * cosT / sinT;

    final m33 = distance + targetX * nx + targetY * ny;
    void set(int row, int col, double v) => matrix[col * 4 + row] = v;
    matrix.fillRange(0, 16, 0);
    set(0, 0, w2 * -nx + f * rx);
    set(0, 1, w2 * -ny + f * ry);
    set(0, 2, w2 * -nz);
    set(0, 3, w2 * m33 - f * (targetX * rx + targetY * ry));
    set(1, 0, h0 * -nx - f * ux);
    set(1, 1, h0 * -ny - f * uy);
    set(1, 2, h0 * -nz - f * uz);
    set(1, 3, h0 * m33 + f * (targetX * ux + targetY * uy));
    set(2, 2, 1);
    set(3, 0, -nx);
    set(3, 1, -ny);
    set(3, 2, -nz);
    set(3, 3, m33);
  }

  /// Projects a world point into [px], [py] with pixel scale [ps].
  /// Returns false when the point is behind (or too close to) the eye.
  bool project(double x, double y, double z) {
    final dx = x - targetX, dy = y - targetY;
    final w = distance - (dx * nx + dy * ny + z * nz);
    if (w < 20) return false;
    px = w2 + f * (dx * rx + dy * ry) / w;
    py = h0 - f * (dx * ux + dy * uy + z * uz) / w;
    ps = f / w;
    return true;
  }

  /// Depth (eye distance along the view direction) of a world point.
  double depthOf(double x, double y, double z) =>
      distance - ((x - targetX) * nx + (y - targetY) * ny + z * nz);

  /// Screen point back to the ground plane (z = 0).
  (double, double) unproject(double sx, double sy) {
    final a = sx - w2, b = h0 - sy;
    final a1 = f * rx + a * nx, b1 = f * ry + a * ny, c1 = a * distance;
    final a2 = f * ux + b * nx, b2 = f * uy + b * ny, c2 = b * distance;
    var det = a1 * b2 - a2 * b1;
    if (det.abs() < 1e-9) det = det.isNegative ? -1e-9 : 1e-9;
    final dx = (c1 * b2 - c2 * b1) / det;
    final dy = (a1 * c2 - a2 * c1) / det;
    return (targetX + dx, targetY + dy);
  }

  /// World-space bounds of the ground the camera can see. Sampling stops a
  /// little below [horizonY] so the far plane stays finite at low tilts.
  Rect visibleGround() {
    final top = math.max(0.0, horizonY + viewH * 0.02);
    final (x0, y0) = unproject(0, top);
    final (x1, y1) = unproject(viewW, top);
    final (x2, y2) = unproject(0, viewH);
    final (x3, y3) = unproject(viewW, viewH);
    // Include the look-at point: at steep tilts the corners can all sit to
    // one side of it.
    return Rect.fromLTRB(
      math.min(math.min(x0, x1), math.min(x2, math.min(x3, targetX))),
      math.min(math.min(y0, y1), math.min(y2, math.min(y3, targetY))),
      math.max(math.max(x0, x1), math.max(x2, math.max(x3, targetX))),
      math.max(math.max(y0, y1), math.max(y2, math.max(y3, targetY))),
    );
  }
}
