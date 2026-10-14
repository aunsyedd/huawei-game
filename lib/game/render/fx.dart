import 'dart:math' as math;

/// A paint splat left on the ground. Fades out after a while.
class Decal {
  double x = 0, y = 0, size = 0, rot = 0, age = 0;
  int color = 0, variant = 0;
  bool active = false;
}

enum FxKind { droplet, dust, leaf, sparkle, muzzle }

class FxParticle {
  bool active = false;
  FxKind kind = FxKind.droplet;
  double x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0;
  double life = 0, maxLife = 1, size = 1, spin = 0;
  int color = 0xFFFFFFFF;
}

/// Purely visual effects (not part of the simulation): paint splats on the
/// ground, water droplets, footstep dust, planting leaves, pickup sparkles.
/// Everything lives in fixed pools, so nothing is allocated during play.
class FxSystem {
  FxSystem() {
    for (var i = 0; i < decals.length; i++) {
      decals[i] = Decal();
    }
    for (var i = 0; i < particles.length; i++) {
      particles[i] = FxParticle();
    }
  }

  static const double decalLife = 30;

  final List<Decal?> decals = List.filled(160, null);
  final List<FxParticle?> particles = List.filled(320, null);
  int _d = 0, _p = 0;
  final _rng = math.Random(11);

  void splat(double x, double y, double size, int color) {
    final d = decals[_d]!;
    _d = (_d + 1) % decals.length;
    d
      ..active = true
      ..x = x
      ..y = y
      ..size = size * (0.8 + _rng.nextDouble() * 0.4)
      ..rot = _rng.nextDouble() * math.pi * 2
      ..age = 0
      ..color = color
      ..variant = _rng.nextInt(4);
  }

  FxParticle _next(FxKind kind, double x, double y, double z, double life, double size, int color) {
    final p = particles[_p]!;
    _p = (_p + 1) % particles.length;
    return p
      ..active = true
      ..kind = kind
      ..x = x
      ..y = y
      ..z = z
      ..vx = 0
      ..vy = 0
      ..vz = 0
      ..life = life
      ..maxLife = life
      ..size = size
      ..spin = _rng.nextDouble() * math.pi * 2
      ..color = color;
  }

  /// Water/paint droplets flying out from a hit.
  void burst(double x, double y, double z, int color, int count, double speed) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final s = speed * (0.4 + _rng.nextDouble() * 0.8);
      _next(FxKind.droplet, x, y, z, 0.5 + _rng.nextDouble() * 0.4, 2.5 + _rng.nextDouble() * 3, color)
        ..vx = math.cos(a) * s
        ..vy = math.sin(a) * s
        ..vz = 60 + _rng.nextDouble() * 140;
    }
  }

  void muzzle(double x, double y, double angle, int color) {
    _next(FxKind.muzzle, x, y, 16, 0.09, 16, color);
    for (var i = 0; i < 3; i++) {
      final a = angle + (_rng.nextDouble() - 0.5) * 0.7;
      final s = 120 + _rng.nextDouble() * 160;
      _next(FxKind.droplet, x, y, 16, 0.25 + _rng.nextDouble() * 0.2, 1.8 + _rng.nextDouble() * 1.5, color)
        ..vx = math.cos(a) * s
        ..vy = math.sin(a) * s
        ..vz = 30 + _rng.nextDouble() * 60;
    }
  }

  void dust(double x, double y) {
    _next(FxKind.dust, x + (_rng.nextDouble() - 0.5) * 10, y + 6, 2, 0.6, 9 + _rng.nextDouble() * 6, 0xFFD7C9A8)
      ..vx = (_rng.nextDouble() - 0.5) * 20
      ..vy = (_rng.nextDouble() - 0.5) * 20
      ..vz = 12;
  }

  void leaves(double x, double y) {
    for (var i = 0; i < 14; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final s = 40 + _rng.nextDouble() * 90;
      _next(
          FxKind.leaf,
          x,
          y,
          10,
          0.9 + _rng.nextDouble() * 0.6,
          5 + _rng.nextDouble() * 3,
          i.isEven ? 0xFF66BB6A : 0xFF9CCC65,
        )
        ..vx = math.cos(a) * s
        ..vy = math.sin(a) * s
        ..vz = 90 + _rng.nextDouble() * 90;
    }
  }

  void sparkle(double x, double y, int color) {
    for (var i = 0; i < 8; i++) {
      final a = i / 8 * math.pi * 2;
      _next(FxKind.sparkle, x, y, 14, 0.45, 5, color)
        ..vx = math.cos(a) * 70
        ..vy = math.sin(a) * 70
        ..vz = 50;
    }
  }

  void update(double dt) {
    for (final d in decals) {
      if (d!.active) {
        d.age += dt;
        if (d.age > decalLife) d.active = false;
      }
    }
    for (final p in particles) {
      if (!p!.active) continue;
      p.life -= dt;
      if (p.life <= 0) {
        p.active = false;
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      p.spin += dt * 6;
      switch (p.kind) {
        case FxKind.droplet:
          p.vz -= 520 * dt;
          if (p.z <= 0) {
            p.z = 0;
            p.vz = 0;
            p.vx *= 0.2;
            p.vy *= 0.2;
          }
        case FxKind.leaf:
          p.vz -= 260 * dt;
          if (p.z <= 0) {
            p.z = 0;
            p.vz = 0;
            p.vx = 0;
            p.vy = 0;
          }
        case FxKind.dust:
          p.size += dt * 14;
        default:
          break;
      }
    }
  }
}
