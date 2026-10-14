import '../../data/game_config.dart';
import 'actor.dart';

class Projectile {
  bool active = false;
  double x = 0, y = 0, vx = 0, vy = 0, remaining = 0;
  Actor? owner;
  late WeaponStats weapon;
}

/// Fixed-size pool so firing never allocates.
class ProjectilePool {
  ProjectilePool(int capacity) : items = List.generate(capacity, (_) => Projectile());

  final List<Projectile> items;
  int _cursor = 0;
  int activeCount = 0;

  /// Returns a free projectile, or null when the pool is exhausted.
  Projectile? obtain() {
    for (var i = 0; i < items.length; i++) {
      final p = items[(_cursor + i) % items.length];
      if (!p.active) {
        _cursor = (_cursor + i + 1) % items.length;
        p.active = true;
        activeCount++;
        return p;
      }
    }
    return null;
  }

  void release(Projectile p) {
    if (!p.active) return;
    p.active = false;
    p.owner = null;
    activeCount--;
  }
}

/// Short-lived visual effects (splash rings, hit puffs, planting sparkles).
class Effect {
  bool active = false;
  double x = 0, y = 0, radius = 0, life = 0, maxLife = 1;
  int color = 0xFFFFFFFF;
  int kind = 0; // 0 ring, 1 puff
}

class EffectPool {
  EffectPool(int capacity) : items = List.generate(capacity, (_) => Effect());
  final List<Effect> items;
  int _cursor = 0;

  void spawn(double x, double y, double radius, double life, int color, {int kind = 0}) {
    final e = items[_cursor];
    _cursor = (_cursor + 1) % items.length;
    e
      ..active = true
      ..x = x
      ..y = y
      ..radius = radius
      ..life = life
      ..maxLife = life
      ..color = color
      ..kind = kind;
  }

  void update(double dt) {
    for (final e in items) {
      if (!e.active) continue;
      e.life -= dt;
      if (e.life <= 0) e.active = false;
    }
  }
}
