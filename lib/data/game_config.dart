import 'dart:convert';
import 'dart:ui' show Color, Rect;

import 'package:flutter/services.dart' show rootBundle;

double _d(dynamic v) => (v as num).toDouble();
List<double> _dl(dynamic v) => (v as List).map(_d).toList();
Rect _rect(List<double> r) => Rect.fromLTWH(r[0], r[1], r[2], r[3]);
Color _hex(String s) => Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));

/// Something with an English and a Bahasa Malaysia name.
mixin Named {
  String get nameEn;
  String get nameMs;
  String name(String lang) => lang == 'ms' ? nameMs : nameEn;
}

class WeaponStats with Named {
  WeaponStats.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      nameEn = j['name_en'] as String,
      nameMs = j['name_ms'] as String,
      damage = _d(j['damage']),
      fireRate = _d(j['fire_rate']),
      range = _d(j['range']),
      projectileSpeed = _d(j['projectile_speed']),
      projectileRadius = _d(j['projectile_radius']),
      spreadDeg = _d(j['spread_deg']),
      magazine = j['magazine'] as int,
      reloadTime = _d(j['reload_time']),
      splashRadius = _d(j['splash_radius']),
      pellets = j['pellets'] as int,
      color = _hex(j['color'] as String),
      rank = j['rank'] as int;

  final String id;
  @override
  final String nameEn;
  @override
  final String nameMs;
  final double damage, fireRate, range, projectileSpeed, projectileRadius;
  final double spreadDeg, reloadTime, splashRadius;
  final int magazine, pellets, rank;
  final Color color;
}

class ArmourStats with Named {
  ArmourStats.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      tier = j['tier'] as int,
      armour = _d(j['armour']),
      absorb = _d(j['absorb']),
      nameEn = j['name_en'] as String,
      nameMs = j['name_ms'] as String;

  final String id;
  final int tier;
  final double armour, absorb;
  @override
  final String nameEn;
  @override
  final String nameMs;
}

class ConsumableStats with Named {
  ConsumableStats.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      heal = _d(j['heal']),
      useTime = _d(j['use_time']),
      hazeShield = _d(j['haze_shield']),
      maxCarry = j['max_carry'] as int,
      perPickup = j['per_pickup'] as int,
      nameEn = j['name_en'] as String,
      nameMs = j['name_ms'] as String;

  final String id;
  final double heal, useTime, hazeShield;
  final int maxCarry, perPickup;
  @override
  final String nameEn;
  @override
  final String nameMs;
}

class SeedStats with Named {
  SeedStats.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      perPickup = j['per_pickup'] as int,
      maxCarry = j['max_carry'] as int,
      nameEn = j['name_en'] as String,
      nameMs = j['name_ms'] as String;

  final String id;
  final int perPickup, maxCarry;
  @override
  final String nameEn;
  @override
  final String nameMs;
}

class LootConfig {
  LootConfig.fromJson(Map<String, dynamic> j)
    : startingWeapon = j['starting_weapon'] as String,
      pickupRadius = _d(j['pickup_radius']),
      perBuilding = (j['per_building'] as List).cast<int>(),
      outdoorSpawns = j['outdoor_spawns'] as int,
      armour = [for (final a in j['armour'] as List) ArmourStats.fromJson(a as Map<String, dynamic>)],
      consumables = {
        for (final c in j['consumables'] as List)
          (c as Map<String, dynamic>)['id'] as String: ConsumableStats.fromJson(c),
      },
      seed = SeedStats.fromJson(j['seed_pack'] as Map<String, dynamic>),
      spawnWeights = (j['spawn_weights'] as Map<String, dynamic>).map((k, v) => MapEntry(k, _d(v)));

  final String startingWeapon;
  final double pickupRadius;
  final List<int> perBuilding;
  final int outdoorSpawns;
  final List<ArmourStats> armour;
  final Map<String, ConsumableStats> consumables;
  final SeedStats seed;
  final Map<String, double> spawnWeights;

  ConsumableStats get water => consumables['water_bottle']!;
  ConsumableStats get mask => consumables['air_mask']!;
  ArmourStats? armourById(String id) {
    for (final a in armour) {
      if (a.id == id) return a;
    }
    return null;
  }
}

class ZonePhase {
  ZonePhase.fromJson(Map<String, dynamic> j)
    : warning = _d(j['warning']),
      shrink = _d(j['shrink']),
      radiusFraction = _d(j['radius_fraction']),
      dps = _d(j['dps']);

  final double warning, shrink, radiusFraction, dps;
}

class ZoneConfig {
  ZoneConfig.fromJson(Map<String, dynamic> j)
    : dropTime = _d(j['drop_time']),
      initialRadius = _d(j['initial_radius']),
      maskDamageFactor = _d(j['mask_damage_factor']),
      finalBubbleWitherRate = _d(j['final_bubble_wither_rate']),
      maxMatchTime = _d(j['max_match_time']),
      phases = [for (final p in j['phases'] as List) ZonePhase.fromJson(p as Map<String, dynamic>)];

  final double dropTime, initialRadius, maskDamageFactor;
  final double finalBubbleWitherRate, maxMatchTime;
  final List<ZonePhase> phases;
}

class TreeConfig {
  TreeConfig.fromJson(Map<String, dynamic> j)
    : plantTime = _d(j['plant_time']),
      stageTimes = _dl(j['stage_times']),
      bubbleRadius = _dl(j['bubble_radius']),
      health = _dl(j['health']),
      trunkRadius = _dl(j['trunk_radius']),
      bubbleGrowRate = _d(j['bubble_grow_rate']),
      maxTrees = j['max_trees'] as int;

  final double plantTime, bubbleGrowRate;
  final List<double> stageTimes, bubbleRadius, health, trunkRadius;
  final int maxTrees;
}

class BotConfig {
  BotConfig.fromJson(Map<String, dynamic> j)
    : count = j['count'] as int,
      speed = _d(j['speed']),
      playerSpeed = _d(j['player_speed']),
      aimErrorDeg = _dl(j['aim_error_deg']),
      reactionTime = _dl(j['reaction_time']),
      aggression = _dl(j['aggression']),
      sightRange = _d(j['sight_range']),
      thinkIntervalNear = _d(j['think_interval_near']),
      thinkIntervalFar = _d(j['think_interval_far']),
      nearDistance = _d(j['near_distance']),
      plantChance = _d(j['plant_chance']),
      retreatHealth = _d(j['retreat_health']),
      names = (j['names'] as List).cast<String>();

  final int count;
  final double speed, playerSpeed, sightRange, thinkIntervalNear;
  final double thinkIntervalFar, nearDistance, plantChance, retreatHealth;
  final List<double> aimErrorDeg, reactionTime, aggression;
  final List<String> names;
}

class ScoreConfig {
  ScoreConfig.fromJson(Map<String, dynamic> j)
    : placementPoints = _d(j['placement_points']),
      tagOut = _d(j['tag_out']),
      treePlanted = _d(j['tree_planted']),
      perSecond = _d(j['per_second']),
      winBonus = _d(j['win_bonus']);

  final double placementPoints, tagOut, treePlanted, perSecond, winBonus;
}

class AreaConfig {
  AreaConfig.fromJson(Map<String, dynamic> j)
    : type = j['type'] as String,
      rect = _rect(_dl(j['rect'])),
      buildings = j['buildings'] as int,
      buildingW = _dl(j['building_w']),
      buildingH = _dl(j['building_h']),
      obstacles = j['obstacles'] as int,
      obstacle = j['obstacle'] as String,
      obstacleRadius = _dl(j['obstacle_radius']),
      gridSpacing = j['grid_spacing'] == null ? 150 : _d(j['grid_spacing']);

  final String type;
  final Rect rect;
  final int buildings, obstacles;
  final List<double> buildingW, buildingH, obstacleRadius;
  final String obstacle;
  final double gridSpacing;
}

class MapConfig {
  MapConfig.fromJson(Map<String, dynamic> j)
    : width = _d(j['width']),
      height = _d(j['height']),
      seed = j['seed'] as int,
      wallThickness = _d(j['wall_thickness']),
      doorWidth = _d(j['door_width']),
      areas = [for (final a in j['areas'] as List) AreaConfig.fromJson(a as Map<String, dynamic>)];

  final double width, height, wallThickness, doorWidth;
  final int seed;
  final List<AreaConfig> areas;
}

class HazeFact {
  HazeFact(this.en, this.ms);
  final String en, ms;
  String text(String lang) => lang == 'ms' ? ms : en;
}

/// Every tunable number in the game, loaded from `assets/data/*.json`.
class GameConfig {
  GameConfig._(Map<String, Map<String, dynamic>> f)
    : weapons = {
        for (final w in f['weapons']!['weapons'] as List)
          (w as Map<String, dynamic>)['id'] as String: WeaponStats.fromJson(w),
      },
      loot = LootConfig.fromJson(f['loot']!),
      zone = ZoneConfig.fromJson(f['zone']!),
      trees = TreeConfig.fromJson(f['trees']!),
      bots = BotConfig.fromJson(f['bots']!),
      score = ScoreConfig.fromJson(f['score']!),
      map = MapConfig.fromJson(f['map']!),
      facts = [
        for (final x in f['facts']!['facts'] as List)
          HazeFact((x as Map<String, dynamic>)['en'] as String, x['ms'] as String),
      ];

  static const files = ['weapons', 'loot', 'zone', 'trees', 'bots', 'score', 'map', 'facts'];

  /// Builds a config from raw JSON strings keyed by file name (without `.json`).
  factory GameConfig.fromSources(Map<String, String> sources) =>
      GameConfig._({for (final e in sources.entries) e.key: jsonDecode(e.value) as Map<String, dynamic>});

  static Future<GameConfig> load() async {
    final sources = <String, String>{};
    for (final f in files) {
      sources[f] = await rootBundle.loadString('assets/data/$f.json');
    }
    return GameConfig.fromSources(sources);
  }

  final Map<String, WeaponStats> weapons;
  final LootConfig loot;
  final ZoneConfig zone;
  final TreeConfig trees;
  final BotConfig bots;
  final ScoreConfig score;
  final MapConfig map;
  final List<HazeFact> facts;
}
