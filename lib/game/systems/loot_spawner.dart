import 'dart:math' as math;

import '../components/actor.dart';
import '../components/loot.dart';
import 'match_manager.dart';

/// Initial loot placement, pickups and dropping an actor's items.
class LootSpawner {
  LootSpawner(this.sim);
  final MatchSimulation sim;

  String _weightedPick() {
    final w = sim.config.loot.spawnWeights;
    final total = w.values.fold(0.0, (a, b) => a + b);
    var roll = sim.rng.nextDouble() * total;
    for (final e in w.entries) {
      roll -= e.value;
      if (roll <= 0) return e.key;
    }
    return w.keys.first;
  }

  LootItem _make(String id, double x, double y) {
    final kind = LootItem.kindFor(id);
    final amount = switch (kind) {
      LootKind.seed => sim.config.loot.seed.perPickup,
      LootKind.water => sim.config.loot.water.perPickup,
      LootKind.mask => sim.config.loot.mask.perPickup,
      _ => 1,
    };
    return LootItem(kind, id, x, y, amount: amount);
  }

  void spawnInitial() {
    final cfg = sim.config.loot;
    for (final b in sim.map.buildings) {
      final n = cfg.perBuilding[0] + sim.rng.nextInt(cfg.perBuilding[1] - cfg.perBuilding[0] + 1);
      for (var i = 0; i < n && i < b.lootPoints.length; i++) {
        final p = b.lootPoints[i];
        sim.loot.add(_make(_weightedPick(), p.dx, p.dy));
      }
    }
    for (final p in sim.map.outdoorLootPoints) {
      sim.loot.add(_make(_weightedPick(), p.dx, p.dy));
    }
  }

  /// Scatters everything a tagged-out actor carried.
  void dropAll(Actor a) {
    final items = <LootItem>[];
    for (final w in a.slots) {
      if (w != null) {
        items.add(LootItem(LootKind.weapon, w.stats.id, 0, 0, ammo: w.ammo));
      }
    }
    if (a.vest != null && a.armour > 0) {
      items.add(LootItem(LootKind.armour, a.vest!.id, 0, 0));
    }
    if (a.water > 0) items.add(LootItem(LootKind.water, 'water_bottle', 0, 0, amount: a.water));
    if (a.masks > 0) items.add(LootItem(LootKind.mask, 'air_mask', 0, 0, amount: a.masks));
    if (a.seeds > 0) items.add(LootItem(LootKind.seed, 'seed_pack', 0, 0, amount: a.seeds));
    for (var i = 0; i < items.length; i++) {
      final ang = i / items.length * math.pi * 2 + sim.rng.nextDouble() * 0.4;
      final it = items[i];
      it.x = (a.pos.x + math.cos(ang) * 34).clamp(20, sim.map.width - 20);
      it.y = (a.pos.y + math.sin(ang) * 34).clamp(20, sim.map.height - 20);
      sim.loot.add(it);
    }
  }

  /// Whether [a] would benefit from [item]. Weapons only count when a slot is
  /// free or the weapon outranks the worst one held.
  bool wants(Actor a, LootItem item) {
    final cfg = sim.config.loot;
    switch (item.kind) {
      case LootKind.water:
        return a.water < cfg.water.maxCarry;
      case LootKind.mask:
        return a.masks < cfg.mask.maxCarry;
      case LootKind.seed:
        return a.seeds < cfg.seed.maxCarry;
      case LootKind.armour:
        final v = cfg.armourById(item.refId);
        if (v == null) return false;
        return a.vest == null || v.tier > a.vest!.tier || a.armour < v.armour * 0.5;
      case LootKind.weapon:
        if (a.slots.any((w) => w?.stats.id == item.refId)) return false;
        if (a.slots.contains(null)) return true;
        final rank = sim.config.weapons[item.refId]!.rank;
        return a.slots.any((w) => w!.stats.rank < rank);
    }
  }

  /// Auto pickup of anything that is not a weapon swap.
  bool canAutoPickup(Actor a, LootItem item) {
    if (item.kind == LootKind.weapon) {
      return a.slots.contains(null) && wants(a, item);
    }
    return wants(a, item);
  }

  void pickup(Actor a, LootItem item) {
    if (item.taken) return;
    final cfg = sim.config.loot;
    switch (item.kind) {
      case LootKind.water:
        final take = math.min(item.amount, cfg.water.maxCarry - a.water);
        a.water += take;
        item.amount -= take;
      case LootKind.mask:
        final take = math.min(item.amount, cfg.mask.maxCarry - a.masks);
        a.masks += take;
        item.amount -= take;
      case LootKind.seed:
        final take = math.min(item.amount, cfg.seed.maxCarry - a.seeds);
        a.seeds += take;
        item.amount -= take;
      case LootKind.armour:
        final v = cfg.armourById(item.refId)!;
        a.vest = v;
        a.armour = v.armour;
        item.amount = 0;
      case LootKind.weapon:
        final inst = WeaponInstance(sim.config.weapons[item.refId]!);
        if (item.ammo != null) inst.ammo = item.ammo!;
        var slot = a.slots.indexOf(null);
        if (slot < 0) {
          // Replace the active weapon for the player, the weakest for bots.
          slot = a.brain == null ? a.activeSlot : (a.slots[0]!.stats.rank <= a.slots[1]!.stats.rank ? 0 : 1);
          final old = a.slots[slot]!;
          sim.loot.add(LootItem(LootKind.weapon, old.stats.id, a.pos.x, a.pos.y + 26, ammo: old.ammo));
        }
        a.slots[slot] = inst;
        if (a.brain != null) {
          _selectBest(a); // Bots always hold their best weapon.
        } else if (a.weapon == null) {
          a.activeSlot = slot;
        }
        item.amount = 0;
    }
    if (item.amount <= 0) item.taken = true;
    sim.listener?.onPickup(a, item);
  }

  void _selectBest(Actor a) {
    final s0 = a.slots[0], s1 = a.slots[1];
    if (s0 == null) {
      a.activeSlot = 1;
    } else if (s1 == null) {
      a.activeSlot = 0;
    } else {
      a.activeSlot = s0.stats.rank >= s1.stats.rank ? 0 : 1;
    }
  }

  /// Nearest untaken loot within [radius] of (x, y), optionally filtered.
  LootItem? nearest(double x, double y, double radius, [bool Function(LootItem)? test]) {
    LootItem? best;
    var bestD = radius * radius;
    for (final l in sim.loot) {
      if (l.taken) continue;
      final dx = l.x - x, dy = l.y - y;
      final d = dx * dx + dy * dy;
      if (d < bestD && (test == null || test(l))) {
        bestD = d;
        best = l;
      }
    }
    return best;
  }
}
