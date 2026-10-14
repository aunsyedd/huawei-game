import 'dart:math' as math;
import 'dart:ui' show Color;

import '../../data/game_config.dart';
import '../components/actor.dart';
import '../components/bot.dart';
import '../components/loot.dart';
import '../components/projectile.dart';
import '../components/tree.dart';
import '../world/map_layout.dart';
import 'bot_ai.dart';
import 'combat_system.dart';
import 'loot_spawner.dart';
import 'spatial_grid.dart';
import 'zone_system.dart';

enum MatchPhase { dropping, running, ended }

/// Hooks for sound, haptics, screen shake and HUD. All optional.
abstract mixin class MatchListener {
  void onShot(Actor a) {}
  void onDamaged(Actor a, double amount, Actor? source) {}
  void onSplash(double x, double y) {}
  void onTagOut(Actor victim, Actor? by, String cause) {}
  void onPickup(Actor a, LootItem item) {}
  void onTreePlanted(Actor a, Tree t) {}
  void onPlayerFinished(PlayerResult r) {}
  void onMatchEnd(Actor? winner) {}
}

class FeedEntry {
  FeedEntry(this.by, this.victim, this.cause, this.time, {required this.involvesPlayer});
  final String? by;
  final String victim;

  /// Weapon id or 'haze'.
  final String cause;
  final double time;
  final bool involvesPlayer;
}

/// Snapshot of the player's match for the results screen.
class PlayerResult {
  PlayerResult({
    required this.placement,
    required this.totalPlayers,
    required this.tagOuts,
    required this.treesPlanted,
    required this.treesAlive,
    required this.timeSurvived,
    required this.hazeTime,
    required this.damageDealt,
    required this.won,
  });

  final int placement, totalPlayers, tagOuts, treesPlanted, treesAlive;
  final double timeSurvived, hazeTime, damageDealt;
  final bool won;

  int score(ScoreConfig s) =>
      ((totalPlayers - placement) * s.placementPoints +
              tagOuts * s.tagOut +
              treesPlanted * s.treePlanted +
              timeSurvived * s.perSecond +
              (won ? s.winBonus : 0))
          .round();
}

/// The whole match, as plain Dart: no widgets, no rendering.
/// The Flame game drives it every frame; tests drive it headless.
class MatchSimulation {
  MatchSimulation(this.config, {int? seed, this.playerName = 'You', this.autopilotPlayer = false})
    : rng = math.Random(seed),
      map = MapLayout.generate(config.map, outdoorLoot: config.loot.outdoorSpawns) {
    zone = ZoneSystem(config.zone, map.width, map.height, rng);
    combat = CombatSystem(this);
    lootSpawner = LootSpawner(this);
    botAi = BotAi(this);
    actorGrid = SpatialHash(map.width, map.height, 160);
    treeGrid = SpatialHash(map.width, map.height, 200);
    _createActors();
    lootSpawner.spawnInitial();
  }

  final GameConfig config;
  final math.Random rng;
  final MapLayout map;
  final String playerName;
  final bool autopilotPlayer;

  late final ZoneSystem zone;
  late final CombatSystem combat;
  late final LootSpawner lootSpawner;
  late final BotAi botAi;
  late final SpatialHash<Actor> actorGrid;
  late final SpatialHash<Tree> treeGrid;

  final List<Actor> actors = [];
  late final Actor player;
  late Actor focus;
  final ProjectilePool projectiles = ProjectilePool(400);
  final EffectPool effects = EffectPool(120);
  final List<Tree> trees = [];
  final List<LootItem> loot = [];
  final List<FeedEntry> feed = [];

  MatchListener? listener;
  MatchPhase phase = MatchPhase.dropping;
  double time = 0;
  int aliveCount = 0;
  Actor? winner;
  PlayerResult? playerResult;

  static const _botColors = [
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFFFA726),
    Color(0xFF8D6E63),
    Color(0xFFEC407A),
    Color(0xFF78909C),
  ];

  int get totalPlayers => actors.length;

  void _createActors() {
    final bots = config.bots;
    player = Actor(id: 0, name: playerName, isPlayer: true, color: const Color(0xFF29B6F6), speed: bots.playerSpeed);
    if (autopilotPlayer) {
      player.brain = BotBrain.random(rng, bots.aimErrorDeg, bots.reactionTime, bots.aggression);
    }
    actors.add(player);
    for (var i = 0; i < bots.count; i++) {
      final a = Actor(
        id: i + 1,
        name: bots.names[i % bots.names.length],
        isPlayer: false,
        color: _botColors[i % _botColors.length],
        speed: bots.speed,
      )..brain = BotBrain.random(rng, bots.aimErrorDeg, bots.reactionTime, bots.aggression);
      actors.add(a);
    }
    focus = player;
    aliveCount = actors.length;
  }

  /// Ends the drop phase. (x, y) is the player's chosen landing spot.
  void start(double x, double y) {
    final start = config.weapons[config.loot.startingWeapon]!;
    for (final a in actors) {
      double px, py;
      if (identical(a, player)) {
        (px, py) = _nearestFree(x, y);
      } else {
        // Spread bots out so nobody lands in a fight.
        var p = map.randomFreePoint(rng);
        for (var i = 0; i < 30; i++) {
          final crowded = actors.any(
            (o) => !identical(o, a) && o.pos.x != 0 && (o.pos.x - p.dx).abs() + (o.pos.y - p.dy).abs() < 500,
          );
          if (!crowded) break;
          p = map.randomFreePoint(rng);
        }
        px = p.dx;
        py = p.dy;
      }
      a.pos.setValues(px, py);
      a.slots[0] = WeaponInstance(start);
      a.activeSlot = 0;
      a.brain?.lastCheckPos.setFrom(a.pos);
    }
    phase = MatchPhase.running;
  }

  (double, double) _nearestFree(double x, double y) {
    x = x.clamp(40, map.width - 40);
    y = y.clamp(40, map.height - 40);
    if (map.isFree(x, y, Actor.radius + 2)) return (x, y);
    for (var r = 20.0; r < 400; r += 20) {
      for (var a = 0.0; a < math.pi * 2; a += 0.4) {
        final px = x + math.cos(a) * r, py = y + math.sin(a) * r;
        if (map.isFree(px, py, Actor.radius + 2)) return (px, py);
      }
    }
    final p = map.randomFreePoint(rng);
    return (p.dx, p.dy);
  }

  bool inTreeBubble(double x, double y) {
    var inside = false;
    treeGrid.query(x, y, 200, (t) {
      if (!t.alive) return false;
      final dx = t.x - x, dy = t.y - y;
      if (dx * dx + dy * dy < t.bubble * t.bubble) {
        inside = true;
        return true;
      }
      return false;
    });
    return inside;
  }

  bool isSafeAt(double x, double y) => zone.isSafe(x, y) || inTreeBubble(x, y);

  bool canPlantAt(Actor a) {
    if (map.buildingAt(a.pos.x, a.pos.y) != null) return false;
    for (final t in trees) {
      if (!t.alive) continue;
      final dx = t.x - a.pos.x, dy = t.y - a.pos.y;
      if (dx * dx + dy * dy < 70 * 70) return false;
    }
    return trees.where((t) => t.alive).length < config.trees.maxTrees;
  }

  /// Starts healing / mask / planting if the actor has what it needs.
  bool startAction(Actor a, ActorAction action) {
    if (!a.alive || a.busy) return false;
    final loot = config.loot;
    double duration;
    switch (action) {
      case ActorAction.healing:
        if (a.water <= 0 || a.health >= a.maxHealth) return false;
        duration = loot.water.useTime;
      case ActorAction.masking:
        if (a.masks <= 0) return false;
        duration = loot.mask.useTime;
      case ActorAction.planting:
        if (a.seeds <= 0 || !canPlantAt(a)) return false;
        duration = config.trees.plantTime;
      case ActorAction.none:
        return false;
    }
    a.action = action;
    a.actionTime = 0;
    a.actionDuration = duration;
    a.wantFire = false;
    return true;
  }

  void _finishAction(Actor a) {
    final loot = config.loot;
    switch (a.action) {
      case ActorAction.healing:
        a.water--;
        a.health = math.min(a.maxHealth, a.health + loot.water.heal);
      case ActorAction.masking:
        a.masks--;
        a.health = math.min(a.maxHealth, a.health + loot.mask.heal);
        a.hazeShield = loot.mask.hazeShield;
      case ActorAction.planting:
        a.seeds--;
        final t = Tree(a.pos.x, a.pos.y, a, config.trees);
        trees.add(t);
        a.treesPlanted++;
        effects.spawn(t.x, t.y, 50, 0.6, 0xFF66BB6A);
        listener?.onTreePlanted(a, t);
      case ActorAction.none:
        break;
    }
    a.cancelAction();
  }

  // ----- Player commands -----

  void swapWeapon() {
    if (player.slots[1 - player.activeSlot] != null) {
      player.activeSlot = 1 - player.activeSlot;
      player.fireCooldown = math.max(player.fireCooldown, 0.25);
    }
  }

  void reload() => combat.startReload(player);

  /// Nearby weapon the player could swap for (shown as a button).
  LootItem? nearbyWeaponFor(Actor a) => lootSpawner.nearest(
    a.pos.x,
    a.pos.y,
    config.loot.pickupRadius + 10,
    (l) => l.kind == LootKind.weapon && !a.slots.any((w) => w?.stats.id == l.refId),
  );

  void pickupNearbyWeapon() {
    final l = nearbyWeaponFor(player);
    if (l != null) lootSpawner.pickup(player, l);
  }

  // ----- Match flow -----

  void tagOut(Actor victim, Actor? by, String cause) {
    if (!victim.alive) return;
    victim.alive = false;
    victim.health = 0;
    victim.placement = aliveCount;
    victim.cancelAction();
    aliveCount--;
    if (by != null && !identical(by, victim)) by.tagOuts++;
    lootSpawner.dropAll(victim);
    effects.spawn(victim.pos.x, victim.pos.y, 60, 0.8, victim.color.toARGB32());
    feed.add(
      FeedEntry(by?.name, victim.name, cause, time, involvesPlayer: identical(victim, player) || identical(by, player)),
    );
    if (feed.length > 30) feed.removeAt(0);
    listener?.onTagOut(victim, by, cause);
    if (identical(victim, player)) _snapshotPlayer(won: false);
    if (aliveCount <= 1) _end();
  }

  void _snapshotPlayer({required bool won}) {
    if (playerResult != null) return;
    playerResult = PlayerResult(
      placement: won ? 1 : player.placement,
      totalPlayers: totalPlayers,
      tagOuts: player.tagOuts,
      treesPlanted: player.treesPlanted,
      treesAlive: trees.where((t) => t.alive && identical(t.planter, player)).length,
      timeSurvived: player.timeAlive,
      hazeTime: player.hazeTime,
      damageDealt: player.damageDealt,
      won: won,
    );
    listener?.onPlayerFinished(playerResult!);
  }

  void _end() {
    if (phase == MatchPhase.ended) return;
    phase = MatchPhase.ended;
    for (final a in actors) {
      if (a.alive) {
        a.placement = 1;
        winner = a;
      }
    }
    if (player.alive) _snapshotPlayer(won: true);
    listener?.onMatchEnd(winner);
  }

  /// Sudden death safety net: rank survivors by health.
  void _forceEnd() {
    final alive = actors.where((a) => a.alive).toList()..sort((a, b) => a.health.compareTo(b.health));
    for (var i = 0; i < alive.length - 1; i++) {
      tagOut(alive[i], null, 'haze');
    }
    _end();
  }

  final List<double> _tmp = [0, 0];

  void update(double dt) {
    if (phase != MatchPhase.running) return;
    time += dt;
    zone.update(dt);

    actorGrid.clear();
    for (final a in actors) {
      if (a.alive) actorGrid.insert(a, a.pos.x, a.pos.y);
    }
    treeGrid.clear();
    for (final t in trees) {
      if (t.alive) treeGrid.insert(t, t.x, t.y);
    }

    if (!focus.alive || !identical(focus, player) && player.alive) {
      focus = player.alive
          ? player
          : (player.lastAttacker?.alive ?? false)
          ? player.lastAttacker!
          : actors.firstWhere((a) => a.alive, orElse: () => player);
    }

    final hazeDps = zone.dps;
    final maskFactor = config.zone.maskDamageFactor;
    for (final a in actors) {
      if (!a.alive) continue;
      a.timeAlive += dt;
      a.hitFlash = math.max(0, a.hitFlash - dt);
      if (a.hazeShield > 0) a.hazeShield -= dt;

      if (a.brain != null) {
        botAi.update(a, dt);
      } else if (a.busy && a.moveInput.length2 > 0.04) {
        a.cancelAction(); // Moving interrupts healing / planting.
      }

      if (a.busy) {
        a.actionTime += dt;
        if (a.actionTime >= a.actionDuration) _finishAction(a);
      }

      // Movement.
      if (a.moveInput.length2 > 1) a.moveInput.normalize();
      if (a.busy) {
        a.vel.setZero();
      } else {
        a.vel.setValues(a.moveInput.x * a.speed, a.moveInput.y * a.speed);
      }
      if (a.vel.x != 0 || a.vel.y != 0) {
        map.resolveCircle(a.pos.x + a.vel.x * dt, a.pos.y + a.vel.y * dt, Actor.radius, _tmp);
        a.pos.setValues(_tmp[0], _tmp[1]);
      }

      combat.updateWeapon(a, dt);

      // Haze.
      if (!isSafeAt(a.pos.x, a.pos.y)) {
        a.hazeTime += dt;
        final dmg = hazeDps * dt * (a.hazeShield > 0 ? maskFactor : 1);
        a.health -= dmg;
        a.lastDamageTime = time;
        if (a.health <= 0) {
          tagOut(a, null, 'haze');
          if (phase == MatchPhase.ended) return;
          continue;
        }
      }

      // Auto pickups.
      final r = config.loot.pickupRadius;
      // Index loop: swapping a weapon drops the old one into [loot].
      for (var i = 0; i < loot.length; i++) {
        final l = loot[i];
        if (l.taken) continue;
        final dx = l.x - a.pos.x, dy = l.y - a.pos.y;
        if (dx * dx + dy * dy > r * r) continue;
        final auto = a.brain != null ? lootSpawner.wants(a, l) : lootSpawner.canAutoPickup(a, l);
        if (auto) lootSpawner.pickup(a, l);
      }
    }
    if (loot.length > 400) loot.removeWhere((l) => l.taken);

    _separateActors();
    combat.updateProjectiles(dt);

    final wither = zone.finished ? config.zone.finalBubbleWitherRate : 0.0;
    for (final t in trees) {
      if (t.alive) t.update(dt, config.trees, witherRate: wither);
    }
    effects.update(dt);

    if (time > config.zone.maxMatchTime && phase == MatchPhase.running) _forceEnd();
  }

  void _separateActors() {
    const minD = Actor.radius * 2;
    for (final a in actors) {
      if (!a.alive) continue;
      actorGrid.query(a.pos.x, a.pos.y, minD, (o) {
        if (identical(o, a) || !o.alive || o.id < a.id) return false;
        final dx = o.pos.x - a.pos.x, dy = o.pos.y - a.pos.y;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minD * minD || d2 < 0.01) return false;
        final d = math.sqrt(d2), push = (minD - d) / 2;
        map.resolveCircle(a.pos.x - dx / d * push, a.pos.y - dy / d * push, Actor.radius, _tmp);
        a.pos.setValues(_tmp[0], _tmp[1]);
        map.resolveCircle(o.pos.x + dx / d * push, o.pos.y + dy / d * push, Actor.radius, _tmp);
        o.pos.setValues(_tmp[0], _tmp[1]);
        return false;
      });
    }
  }
}
