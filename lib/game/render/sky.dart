import 'dart:math' as math;
import 'dart:ui';

import 'camera3d.dart';
import 'sprites.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Sun direction, light colours and fog for one moment of the day.
///
/// The shading sun sits in front of the camera so faces turned towards the
/// player stay lit, while shadows are cast from behind it: that keeps
/// characters readable and still drops their shadow into view. Games have
/// done this since forever and it reads much better than a physical sun.
class Lighting {
  Lighting({
    required this.lx,
    required this.ly,
    required this.lz,
    required this.ar,
    required this.ag,
    required this.ab,
    required this.dr,
    required this.dg,
    required this.db,
    required this.fog,
    required this.night,
    required this.sunUp,
  });

  /// Direction towards the light (unit length).
  final double lx, ly, lz;

  /// Where the sun is *drawn*. The shading sun sits behind the camera so
  /// faces turned towards the player stay lit; the disc in the sky is its
  /// mirror image, in front, where the player can actually see it.
  double get vx => lx;
  double get vy => -ly;
  double get vz => lz;

  /// Ambient and diffuse light, per channel, roughly 0..1.4.
  final double ar, ag, ab, dr, dg, db;

  /// Colour distant geometry fades into (the horizon colour).
  final Color fog;

  /// 0 in daylight, 1 at night: drives lamp glow and stars.
  final double night;

  /// Sun elevation, -1 (midnight) .. 1 (noon).
  final double sunUp;

  /// Shadows are flattened along this offset per unit of height.
  static const double shadowX = 0.52, shadowY = 0.46;

  /// [timeOfDay] runs 0..1 over a day (0.5 is noon). [haze] 0..1 thickens the
  /// air and pushes everything towards a brown-orange smoke tint.
  factory Lighting.forTime(double timeOfDay, double haze) {
    final up = math.sin((timeOfDay - 0.25) * math.pi * 2);
    final day = ((up + 0.18) / 0.5).clamp(0.0, 1.0); // 0 night .. 1 full day
    final dusk = (1 - (up.abs() / 0.35)).clamp(0.0, 1.0) * (1 - 0.4 * haze);
    final night = 1 - day;

    // Sun swings from the east (sunrise) to the west (sunset) but is always
    // kept slightly in front of the camera's default heading.
    final az = _lerp(-1.1, 1.1, timeOfDay.clamp(0.0, 1.0));
    final horiz = math.max(0.18, math.sqrt(math.max(0.0, 1 - up * up)) * 0.75);
    var lx = math.sin(az) * horiz, ly = 0.34 * horiz, lz = math.max(0.18, up.abs() * 0.95);
    final len = math.sqrt(lx * lx + ly * ly + lz * lz);
    lx /= len;
    ly /= len;
    lz /= len;

    // Warm sun, cool blue night, orange dusk, dirty beige haze.
    final dr = _lerp(0.18, 0.72, day) + dusk * 0.30 + haze * 0.05;
    final dg = _lerp(0.20, 0.70, day) + dusk * 0.14 - haze * 0.02;
    final db = _lerp(0.30, 0.64, day) - dusk * 0.06 - haze * 0.10;
    final ar = _lerp(0.26, 0.54, day) + haze * 0.10 + dusk * 0.06;
    final ag = _lerp(0.28, 0.55, day) + haze * 0.04;
    final ab = _lerp(0.42, 0.58, day) - haze * 0.08;

    return Lighting(
      lx: lx,
      ly: ly,
      lz: lz,
      ar: ar,
      ag: ag,
      ab: ab,
      dr: dr,
      dg: dg,
      db: db,
      fog: horizonColor(up, haze),
      night: night,
      sunUp: up,
    );
  }

  static Color zenithColor(double up, double haze) {
    final day = ((up + 0.18) / 0.5).clamp(0.0, 1.0);
    final base = Color.lerp(const Color(0xFF0A1226), const Color(0xFF2F6FA8), day)!;
    return Color.lerp(base, const Color(0xFF8A6B44), haze * 0.62)!;
  }

  static Color horizonColor(double up, double haze) {
    final day = ((up + 0.18) / 0.5).clamp(0.0, 1.0);
    final dusk = (1 - (up.abs() / 0.35)).clamp(0.0, 1.0);
    var c = Color.lerp(const Color(0xFF1C2A44), const Color(0xFFBBD7E6), day)!;
    c = Color.lerp(c, const Color(0xFFE88B47), dusk * 0.7)!;
    return Color.lerp(c, const Color(0xFFD7B183), haze * 0.9)!;
  }
}

/// Draws everything behind the island: sky gradient, sun, clouds, stars and
/// the open sea, all in screen space so it stays correct at any camera angle.
class SkyBox {
  SkyBox();

  final Paint _p = Paint();
  final AtlasBatch _clouds = AtlasBatch(90);
  final AtlasBatch _sparkle = AtlasBatch(20);
  final Paint _cloudPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _glowPaint = Paint()
    ..filterQuality = FilterQuality.low
    ..blendMode = BlendMode.plus;

  /// Fixed cloud and star directions, so they do not swim when the camera turns.
  late final List<_SkyPoint> _cloudDirs = _ring(26, 7, 0.08, 0.42);
  late final List<_SkyPoint> _starDirs = _ring(64, 23, 0.05, 0.95);

  static List<_SkyPoint> _ring(int n, int seed, double loElev, double hiElev) {
    final rng = math.Random(seed);
    return [
      for (var i = 0; i < n; i++)
        _SkyPoint(
          (i / n + rng.nextDouble() * 0.6 / n) * math.pi * 2,
          loElev + rng.nextDouble() * (hiElev - loElev),
          0.6 + rng.nextDouble() * 0.9,
        ),
    ];
  }

  /// Screen position of a direction (not a point), i.e. its vanishing point.
  /// Returns null when the direction is behind the camera.
  Offset? _direction(Camera3D cam, double dx, double dy, double dz) {
    final denom = -(dx * cam.nx + dy * cam.ny + dz * cam.nz);
    if (denom <= 0.02) return null;
    return Offset(
      cam.w2 + cam.f * (dx * cam.rx + dy * cam.ry) / denom,
      cam.h0 - cam.f * (dx * cam.ux + dy * cam.uy + dz * cam.uz) / denom,
    );
  }

  void draw(Canvas canvas, Camera3D cam, Lighting light, double haze, double clock, int quality) {
    final w = cam.viewW, h = cam.viewH;
    final screen = Rect.fromLTWH(0, 0, w, h);
    final horizon = cam.horizonY.clamp(-h * 4, h);
    final zenith = Lighting.zenithColor(light.sunUp, haze);
    final hz = light.fog;

    // Sky: zenith at the top of the (possibly off-screen) dome down to the
    // horizon line.
    _p
      ..shader = Gradient.linear(Offset(0, horizon - h * 0.9), Offset(0, horizon), [zenith, hz])
      ..blendMode = BlendMode.src;
    canvas.drawRect(screen, _p);
    _p
      ..shader = null
      ..blendMode = BlendMode.srcOver;

    if (light.night > 0.35 && quality >= 1) _stars(canvas, cam, light, horizon);
    _sun(canvas, cam, light, horizon, quality);
    if (quality >= 1) _cloudLayer(canvas, cam, light, clock, horizon);

    // Open sea below the horizon: a flat plane fills exactly that half.
    if (horizon < h) {
      final top = math.max(0.0, horizon);
      final deep = Color.lerp(const Color(0xFF14557F), hz, 0.12)!;
      final near = Color.lerp(const Color(0xFF2D86B8), Color.lerp(deep, hz, 0.1)!, 0.25)!;
      _p.shader = Gradient.linear(Offset(0, top), Offset(0, h), [Color.lerp(hz, deep, 0.75)!, near]);
      canvas.drawRect(Rect.fromLTRB(0, top, w, h), _p);
      _p.shader = null;
      if (quality >= 2 && light.sunUp > 0) _glitter(canvas, cam, light, top, clock);
    }
  }

  void _sun(Canvas canvas, Camera3D cam, Lighting light, double horizon, int quality) {
    final at = _direction(cam, light.vx, light.vy, light.vz);
    if (at == null) return;
    final warm = Color.lerp(const Color(0xFFFFF2C4), const Color(0xFFFF9A3C), (1 - light.sunUp).clamp(0.0, 1.0) * 0.8)!;
    final r = cam.viewH * 0.055;
    final disc = light.night > 0.55 ? const Color(0xFFE8EEF6) : warm;
    if (quality >= 1) {
      canvas.drawCircle(
        at,
        r * 7,
        Paint()
          ..shader = Gradient.radial(at, r * 7, [disc.withValues(alpha: 0.34), disc.withValues(alpha: 0)]),
      );
    }
    canvas.drawCircle(at, r * (light.night > 0.55 ? 0.65 : 1), Paint()..color = disc.withValues(alpha: 0.95));
  }

  void _stars(Canvas canvas, Camera3D cam, Lighting light, double horizon) {
    final a = ((light.night - 0.35) / 0.4).clamp(0.0, 1.0);
    final p = Paint();
    for (final s in _starDirs) {
      final ce = math.cos(s.elev), se = math.sin(s.elev);
      final at = _direction(cam, math.cos(s.az) * ce, math.sin(s.az) * ce, se);
      if (at == null || at.dy > horizon) continue;
      p.color = Color.fromRGBO(255, 255, 255, a * (0.35 + 0.65 * s.size * 0.6));
      canvas.drawCircle(at, 0.7 + s.size * 0.8, p);
    }
  }

  void _cloudLayer(Canvas canvas, Camera3D cam, Lighting light, double clock, double horizon) {
    final tint = Color.lerp(light.fog, const Color(0xFFFFFFFF), 0.35 * (1 - light.night))!;
    final alpha = 0.55 - light.night * 0.25;
    for (final c in _cloudDirs) {
      final az = c.az + clock * 0.004;
      final ce = math.cos(c.elev), se = math.sin(c.elev);
      final at = _direction(cam, math.cos(az) * ce, math.sin(az) * ce, se);
      if (at == null || at.dy > horizon + 4) continue;
      final size = cam.viewH * (0.22 + c.size * 0.3);
      _clouds.add(
        Sprites.puff,
        at.dx,
        at.dy,
        size,
        (((alpha * 255).round().clamp(0, 255)) << 24) | (tint.toARGB32() & 0xFFFFFF),
      );
      if (_clouds.isFull) break;
    }
    _clouds.draw(canvas, Sprites.instance.atlas, _cloudPaint);
  }

  /// Sun glitter on the water, right under the sun's screen position.
  void _glitter(Canvas canvas, Camera3D cam, Lighting light, double seaTop, double clock) {
    final at = _direction(cam, light.vx, light.vy, 0);
    if (at == null) return;
    for (var i = 0; i < 16; i++) {
      final t = i / 16;
      final y = seaTop + (cam.viewH - seaTop) * (0.04 + t * t * 0.95);
      final spread = (y - seaTop) * 0.5 + 6;
      final x = at.dx + math.sin(clock * 1.7 + i * 2.3) * spread;
      _sparkle.add(Sprites.dot, x, y, 5 + t * 16, _argb(0.34 * (1 - t) * light.sunUp.clamp(0.0, 1.0), 0xFFF3C0));
    }
    _sparkle.draw(canvas, Sprites.instance.atlas, _glowPaint);
  }

  static int _argb(double a, int rgb) => ((a.clamp(0.0, 1.0) * 255).round() << 24) | (rgb & 0xFFFFFF);
}

class _SkyPoint {
  _SkyPoint(this.az, this.elev, this.size);
  final double az, elev, size;
}
