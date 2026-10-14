import 'dart:math' as math;

import '../components/actor.dart';
import '../components/projectile.dart';
import '../components/tree.dart';
import 'match_manager.dart';

/// Firing, projectile flight, hits, splash damage, armour.
class CombatSystem {
  CombatSystem(this.sim);
  final MatchSimulation sim;

  static const double _step = 10;

  void updateWeapon(Actor a, double dt) {
    if (a.fireCooldown > 0) a.fireCooldown -= dt;
    final w = a.weapon;
    if (w == null) return;
    if (w.reloadTimer > 0) {
      w.reloadTimer -= dt;
      if (w.reloadTimer <= 0) {
        w.reloadTimer = 0;
        w.ammo = w.stats.magazine;
      }
      return;
    }
    if (!a.wantFire || a.busy || a.fireCooldown > 0) return;
    if (w.ammo <= 0) {
      startReload(a);
      return;
    }
    _fire(a, w);
  }

  void startReload(Actor a) {
    final w = a.weapon;
    if (w == null || w.reloading || w.ammo >= w.stats.magazine) return;
    w.reloadTimer = w.stats.reloadTime;
  }

  void _fire(Actor a, WeaponInstance w) {
    final s = w.stats;
    for (var i = 0; i < s.pellets; i++) {
      final p = sim.projectiles.obtain();
      if (p == null) return;
      final spread = (sim.rng.nextDouble() - 0.5) * s.spreadDeg * math.pi / 180;
      final ang = a.aimAngle + spread;
      final dx = math.cos(ang), dy = math.sin(ang);
      p
        ..x = a.pos.x + dx * (Actor.radius + 8)
        ..y = a.pos.y + dy * (Actor.radius + 8)
        ..vx = dx * s.projectileSpeed
        ..vy = dy * s.projectileSpeed
        ..remaining = s.range
        ..owner = a
        ..weapon = s;
    }
    w.ammo--;
    a.fireCooldown = 1 / s.fireRate;
    sim.listener?.onShot(a);
    if (w.ammo <= 0) startReload(a);
  }

  void updateProjectiles(double dt) {
    for (final p in sim.projectiles.items) {
      if (!p.active) continue;
      final speed = p.weapon.projectileSpeed;
      var dist = speed * dt;
      final steps = (dist / _step).ceil();
      final sx = p.vx * dt / steps, sy = p.vy * dt / steps;
      final stepLen = dist / steps;
      for (var s = 0; s < steps; s++) {
        p.x += sx;
        p.y += sy;
        p.remaining -= stepLen;
        if (p.remaining <= 0) {
          _impact(p, hitWall: false);
          break;
        }
        if (sim.map.pointBlocked(p.x, p.y, 0)) {
          _impact(p, hitWall: true);
          break;
        }
        if (_hitActor(p) || _hitTree(p)) break;
      }
    }
  }

  bool _hitActor(Projectile p) {
    Actor? hit;
    final pr = p.weapon.projectileRadius;
    sim.actorGrid.query(p.x, p.y, Actor.radius + pr, (a) {
      if (!a.alive || identical(a, p.owner)) return false;
      final dx = a.pos.x - p.x, dy = a.pos.y - p.y, m = Actor.radius + pr;
      if (dx * dx + dy * dy < m * m) {
        hit = a;
        return true;
      }
      return false;
    });
    final target = hit;
    if (target == null) return false;
    if (p.weapon.splashRadius <= 0) {
      damage(target, p.weapon.damage, source: p.owner, cause: p.weapon.id);
      sim.effects.spawn(p.x, p.y, 14, 0.25, p.weapon.color.toARGB32(), kind: 1);
    }
    _impact(p, hitWall: false);
    return true;
  }

  bool _hitTree(Projectile p) {
    Tree? hit;
    sim.treeGrid.query(p.x, p.y, 30, (t) {
      if (!t.alive) return false;
      final tr = sim.config.trees.trunkRadius[t.stage];
      final dx = t.x - p.x, dy = t.y - p.y;
      if (dx * dx + dy * dy < tr * tr) {
        hit = t;
        return true;
      }
      return false;
    });
    final tree = hit;
    if (tree == null) return false;
    if (p.weapon.splashRadius <= 0) damageTree(tree, p.weapon.damage);
    _impact(p, hitWall: true);
    return true;
  }

  void _impact(Projectile p, {required bool hitWall}) {
    final w = p.weapon;
    if (w.splashRadius > 0) {
      _splash(p.x, p.y, w.splashRadius, w.damage, p.owner, w.id);
      sim.effects.spawn(p.x, p.y, w.splashRadius, 0.45, w.color.toARGB32());
      sim.listener?.onSplash(p.x, p.y);
    } else if (hitWall) {
      sim.effects.spawn(p.x, p.y, 10, 0.2, w.color.toARGB32(), kind: 1);
    }
    sim.projectiles.release(p);
  }

  void _splash(double x, double y, double radius, double dmg, Actor? owner, String cause) {
    for (final a in sim.actors) {
      if (!a.alive || identical(a, owner)) continue;
      final dx = a.pos.x - x, dy = a.pos.y - y;
      final d = math.sqrt(dx * dx + dy * dy) - Actor.radius;
      if (d > radius) continue;
      final falloff = 1 - 0.5 * (d.clamp(0, radius) / radius);
      if (!sim.map.lineOfSight(x, y, a.pos.x, a.pos.y)) continue;
      damage(a, dmg * falloff, source: owner, cause: cause);
    }
    for (final t in sim.trees) {
      if (!t.alive) continue;
      final dx = t.x - x, dy = t.y - y;
      if (dx * dx + dy * dy < radius * radius) damageTree(t, dmg * 0.6);
    }
  }

  void damageTree(Tree t, double amount) {
    t.health -= amount;
    t.hitFlash = 0.12;
    if (t.health <= 0) {
      t.alive = false;
      sim.effects.spawn(t.x, t.y, 40, 0.6, 0xFF6D4C41, kind: 1);
    }
  }

  /// Blaster damage: armour soaks part of it. Interrupts healing/planting.
  void damage(Actor target, double amount, {Actor? source, required String cause}) {
    if (!target.alive || amount <= 0) return;
    final vest = target.vest;
    if (vest != null && target.armour > 0) {
      final absorbed = math.min(target.armour, amount * vest.absorb);
      target.armour -= absorbed;
      amount -= absorbed;
      if (target.armour <= 0) {
        target.armour = 0;
        target.vest = null;
      }
    }
    target.health -= amount;
    target.hitFlash = 0.12;
    target.lastDamageTime = sim.time;
    if (source != null) {
      target.lastAttacker = source;
      source.damageDealt += amount;
    }
    if (target.busy) target.cancelAction();
    sim.listener?.onDamaged(target, amount, source);
    if (target.health <= 0) sim.tagOut(target, source, cause);
  }
}
