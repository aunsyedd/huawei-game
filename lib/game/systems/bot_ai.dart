import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../components/actor.dart';
import '../components/bot.dart';
import 'match_manager.dart';

/// State machine: wander, loot, fight, flee (haze), retreat (low health),
/// plus healing / mask / planting actions when it feels safe.
/// Bots far from the camera think less often; movement still runs every frame.
class BotAi {
  BotAi(this.sim);
  final MatchSimulation sim;

  void update(Actor a, double dt) {
    final b = a.brain!;
    b.thinkTimer -= dt;
    if (b.thinkTimer <= 0) {
      final cfg = sim.config.bots;
      final f = sim.focus;
      final dx = f.pos.x - a.pos.x, dy = f.pos.y - a.pos.y;
      final near = dx * dx + dy * dy < cfg.nearDistance * cfg.nearDistance;
      final interval = near ? cfg.thinkIntervalNear : cfg.thinkIntervalFar;
      b.thinkTimer = interval * (0.8 + sim.rng.nextDouble() * 0.4);
      _think(a, b, interval);
    }
    _act(a, b, dt);
  }

  double _dist(Actor a, Actor o) => a.pos.distanceTo(o.pos);

  void _think(Actor a, BotBrain b, double interval) {
    final cfg = sim.config.bots;
    final sight = cfg.sightRange;

    // Find the nearest visible enemy; prefer whoever just hit us.
    Actor? enemy;
    var best = sight * sight;
    for (final o in sim.actors) {
      if (identical(o, a) || !o.alive) continue;
      final d2 = a.pos.distanceToSquared(o.pos);
      if (d2 >= best) continue;
      if (!sim.map.lineOfSight(a.pos.x, a.pos.y, o.pos.x, o.pos.y)) continue;
      if (_hiddenByRoof(a, o)) continue;
      best = d2;
      enemy = o;
    }
    final attacker = a.lastAttacker;
    final hitRecently = sim.time - a.lastDamageTime < 3;
    if (attacker != null && attacker.alive && hitRecently && enemy == null) {
      if (_dist(a, attacker) < sight * 1.3) enemy = attacker;
    }
    if (enemy != null) {
      if (!identical(b.target, enemy)) {
        b.target = enemy;
        b.acquiredAt = sim.time;
      }
      b.targetVisible = sim.map.lineOfSight(a.pos.x, a.pos.y, enemy.pos.x, enemy.pos.y);
      b.lastEnemySeen = sim.time;
    } else {
      b.targetVisible = false;
      if (sim.time - b.lastEnemySeen > 3) b.target = null;
    }

    final enemyDist = enemy == null ? double.infinity : _dist(a, enemy);
    final inHaze = !sim.isSafeAt(a.pos.x, a.pos.y);
    final z = sim.zone;
    final zoneThreat =
        inHaze ||
        (!z.finished && !z.isSafeNext(a.pos.x, a.pos.y, margin: 80) && (z.shrinking || z.timer < 16 + b.caution));
    final lowHp = a.health < cfg.retreatHealth;

    if (a.busy) {
      if (enemy != null && enemyDist < 320) a.cancelAction();
      return;
    }

    // Quick actions.
    if (lowHp && a.water > 0 && enemyDist > 380) {
      sim.startAction(a, ActorAction.healing);
      return;
    }
    if (inHaze && a.masks > 0 && a.hazeShield <= 0 && enemyDist > 380) {
      sim.startAction(a, ActorAction.masking);
      return;
    }

    if (enemy != null && lowHp && a.water > 0) {
      b.state = BotState.retreat;
    } else if (zoneThreat) {
      if (b.state != BotState.flee || !_destSafe(b)) _pickSafeDest(a, b);
      b.state = BotState.flee;
    } else if (enemy != null && (enemyDist < sight * _aggression(b) || hitRecently)) {
      b.state = BotState.fight;
    } else if (a.seeds > 0 &&
        sim.time - b.lastEnemySeen > 6 &&
        sim.trees.length < sim.config.trees.maxTrees &&
        sim.rng.nextDouble() < cfg.plantChance * interval * 2 &&
        sim.canPlantAt(a)) {
      sim.startAction(a, ActorAction.planting);
      return;
    } else {
      final lt = b.lootTarget;
      if (lt == null || lt.taken || !sim.lootSpawner.wants(a, lt)) {
        b.lootTarget = sim.lootSpawner.nearest(
          a.pos.x,
          a.pos.y,
          480,
          (l) => sim.lootSpawner.wants(a, l) && sim.isSafeAt(l.x, l.y),
        );
      }
      if (b.lootTarget != null) {
        b.state = BotState.loot;
        b.dest.setValues(b.lootTarget!.x, b.lootTarget!.y);
        b.hasDest = true;
      } else {
        if (b.state != BotState.wander || !b.hasDest || a.pos.distanceTo(b.dest) < 60) {
          _pickWanderDest(a, b);
        }
        b.state = BotState.wander;
      }
    }
  }

  /// Bots focus on looting early and get bolder as the match goes on.
  double _aggression(BotBrain b) => b.aggression * (0.35 + 0.65 * math.min(1.0, sim.time / 75));

  bool _hiddenByRoof(Actor a, Actor o) {
    final bo = sim.map.buildingAt(o.pos.x, o.pos.y);
    if (bo == null) return false;
    return !identical(bo, sim.map.buildingAt(a.pos.x, a.pos.y)) && a.pos.distanceTo(o.pos) > 160;
  }

  bool _destSafe(BotBrain b) {
    final z = sim.zone;
    return z.finished ? z.isSafe(b.dest.x, b.dest.y) : z.isSafeNext(b.dest.x, b.dest.y, margin: 60);
  }

  /// Picks a spot inside the coming safe circle on the bot's side of it, so
  /// fleeing bots spread around the ring instead of piling into the centre.
  void _pickSafeDest(Actor a, BotBrain b) {
    final z = sim.zone;
    final cx = z.finished ? z.cx : z.nextX, cy = z.finished ? z.cy : z.nextY;
    final r = z.finished ? z.r : z.nextR;
    // Prefer a clean-air bubble once the haze has nearly closed.
    if (r < 80) {
      for (final t in sim.trees) {
        if (t.alive && t.bubble > 50) {
          b.dest.setValues(t.x, t.y);
          b.hasDest = true;
          return;
        }
      }
    }
    final base = math.atan2(a.pos.y - cy, a.pos.x - cx);
    for (var i = 0; i < 12; i++) {
      final ang = base + (sim.rng.nextDouble() - 0.5) * 1.2;
      final d = r * (0.35 + sim.rng.nextDouble() * 0.45);
      final x = cx + math.cos(ang) * d, y = cy + math.sin(ang) * d;
      if (sim.map.isFree(x, y, Actor.radius)) {
        b.dest.setValues(x, y);
        b.hasDest = true;
        return;
      }
    }
    b.dest.setValues(cx, cy);
    b.hasDest = true;
  }

  void _pickWanderDest(Actor a, BotBrain b) {
    final z = sim.zone;
    for (var i = 0; i < 12; i++) {
      final ang = sim.rng.nextDouble() * math.pi * 2;
      final d = 250 + sim.rng.nextDouble() * 550;
      final x = a.pos.x + math.cos(ang) * d, y = a.pos.y + math.sin(ang) * d;
      final ok = z.finished ? z.isSafe(x, y) : z.isSafeNext(x, y, margin: 100);
      if (ok && sim.map.isFree(x, y, Actor.radius)) {
        b.dest.setValues(x, y);
        b.hasDest = true;
        return;
      }
    }
    _pickSafeDest(a, b);
  }

  void _act(Actor a, BotBrain b, double dt) {
    a.moveInput.setZero();
    a.wantFire = false;
    if (a.busy) return;
    final t = b.target;
    final w = a.weapon;

    var mx = 0.0, my = 0.0;
    switch (b.state) {
      case BotState.fight when t != null && t.alive:
        final dx = t.pos.x - a.pos.x, dy = t.pos.y - a.pos.y;
        final d = math.sqrt(dx * dx + dy * dy) + 0.001;
        final desired = (w?.stats.range ?? 400) * 0.55;
        var radial = 0.0;
        if (d > desired + 60 || !b.targetVisible) radial = 1;
        if (d < desired - 80) radial = -0.8;
        b.strafeTimer -= dt;
        if (b.strafeTimer <= 0) {
          b.strafeTimer = 0.7 + sim.rng.nextDouble() * 1.4;
          b.strafeDir = sim.rng.nextBool() ? 1 : -1;
        }
        mx = dx / d * radial + -dy / d * b.strafeDir * 0.8;
        my = dy / d * radial + dx / d * b.strafeDir * 0.8;
      case BotState.retreat when t != null:
        final dx = a.pos.x - t.pos.x, dy = a.pos.y - t.pos.y;
        final d = math.sqrt(dx * dx + dy * dy) + 0.001;
        final zx = sim.zone.cx - a.pos.x, zy = sim.zone.cy - a.pos.y;
        final zd = math.sqrt(zx * zx + zy * zy) + 0.001;
        mx = dx / d + zx / zd * 0.5;
        my = dy / d + zy / zd * 0.5;
      default:
        if (b.hasDest) {
          final (tx, ty) = _navTarget(a, b.dest.x, b.dest.y);
          final dx = tx - a.pos.x, dy = ty - a.pos.y;
          final d = math.sqrt(dx * dx + dy * dy);
          if (d > 8) {
            mx = dx / d;
            my = dy / d;
          } else if (b.state == BotState.wander) {
            b.hasDest = false;
          }
        }
    }

    // Unstuck manoeuvre overrides steering for a moment.
    if (b.unstuckTimer > 0) {
      b.unstuckTimer -= dt;
      mx = math.cos(b.unstuckAngle);
      my = math.sin(b.unstuckAngle);
    } else if (mx != 0 || my != 0) {
      final len = math.sqrt(mx * mx + my * my);
      mx /= len;
      my /= len;
      final (ax, ay) = _avoid(a, b, mx, my);
      mx = ax;
      my = ay;
    }
    a.moveInput.setValues(mx, my);

    // Shoot when fighting, or back when shot at (e.g. while fleeing the haze).
    final engage = b.state == BotState.fight || sim.time - a.lastDamageTime < 3;
    if (engage && t != null && t.alive && b.targetVisible && w != null) {
      final d = a.pos.distanceTo(t.pos);
      final lead = d / w.stats.projectileSpeed * 0.6;
      final px = t.pos.x + t.vel.x * lead, py = t.pos.y + t.vel.y * lead;
      final wobble = math.sin(sim.time * 2.3 + b.phase) * b.aimError + (sim.rng.nextDouble() - 0.5) * b.aimError * 0.6;
      a.aimAngle = math.atan2(py - a.pos.y, px - a.pos.x) + wobble;
      a.wantFire = sim.time - b.acquiredAt > b.reaction && d < w.stats.range * 1.02;
      if (!a.wantFire && w.ammo < w.stats.magazine * 0.5 && d > w.stats.range) {
        sim.combat.startReload(a);
      }
    } else {
      if (mx != 0 || my != 0) a.aimAngle = math.atan2(my, mx);
      if (w != null && w.ammo < w.stats.magazine) sim.combat.startReload(a);
    }

    // Stuck detection.
    b.stuckCheck -= dt;
    if (b.stuckCheck <= 0) {
      final moved = a.pos.distanceTo(b.lastCheckPos);
      final trying = mx != 0 || my != 0;
      if (trying && moved < 18) {
        b.stuckSeconds += 1;
        b.unstuckTimer = 0.5 + sim.rng.nextDouble() * 0.6;
        b.unstuckAngle = sim.rng.nextDouble() * math.pi * 2;
        b.avoidSide = -b.avoidSide;
        if (b.stuckSeconds > 2) {
          b.hasDest = false;
          b.lootTarget = null;
        }
      } else {
        b.stuckSeconds = 0;
      }
      b.lastCheckPos.setFrom(a.pos);
      b.stuckCheck = 1;
    }
  }

  /// Routes through doors when entering or leaving a building.
  (double, double) _navTarget(Actor a, double dx, double dy) {
    final map = sim.map;
    final me = map.buildingAt(a.pos.x, a.pos.y);
    final there = map.buildingAt(dx, dy);
    if (identical(me, there)) return (dx, dy);
    if (me != null) {
      final nearDoor =
          a.pos.distanceTo2(me.doorInside.dx, me.doorInside.dy) < 30 ||
          a.pos.distanceTo2(me.doorOutside.dx, me.doorOutside.dy) < 45;
      return nearDoor ? (me.doorOutside.dx, me.doorOutside.dy) : (me.doorInside.dx, me.doorInside.dy);
    }
    if (there != null) {
      final atDoor = a.pos.distanceTo2(there.doorOutside.dx, there.doorOutside.dy) < 36;
      return atDoor ? (there.doorInside.dx, there.doorInside.dy) : (there.doorOutside.dx, there.doorOutside.dy);
    }
    return (dx, dy);
  }

  /// Rotates the steering direction away from walls/obstacles just ahead.
  (double, double) _avoid(Actor a, BotBrain b, double mx, double my) {
    const probe = 40.0;
    if (sim.map.isFree(a.pos.x + mx * probe, a.pos.y + my * probe, Actor.radius - 2)) {
      return (mx, my);
    }
    for (final deg in const [35, 70, 105]) {
      for (final side in [b.avoidSide, -b.avoidSide]) {
        final ang = deg * math.pi / 180 * side;
        final c = math.cos(ang), s = math.sin(ang);
        final rx = mx * c - my * s, ry = mx * s + my * c;
        if (sim.map.isFree(a.pos.x + rx * probe, a.pos.y + ry * probe, Actor.radius - 2)) {
          b.avoidSide = side;
          return (rx, ry);
        }
      }
    }
    return (mx, my);
  }
}

extension _VecXY on Vector2 {
  double distanceTo2(double x, double y) {
    final dx = this.x - x, dy = this.y - y;
    return math.sqrt(dx * dx + dy * dy);
  }
}
