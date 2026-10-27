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
      blockPlaced = _d(j['block_placed']),
      perSecond = _d(j['per_second']),
      winBonus = _d(j['win_bonus']);

  final double placementPoints, tagOut, treePlanted, blockPlaced, perSecond, winBonus;
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

class MissionDef {
  MissionDef.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      type = j['type'] as String,
      target = j['target'] as int,
      xp = j['xp'] as int,
      en = j['en'] as String,
      ms = j['ms'] as String;

  final String id, type, en, ms;
  final int target, xp;
  String text(String lang) => lang == 'ms' ? ms : en;
}

class SkinDef {
  SkinDef.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      level = j['level'] as int,
      color = _hex(j['color'] as String),
      en = j['en'] as String,
      ms = j['ms'] as String;

  final String id, en, ms;
  final int level;
  final Color color;
  String name(String lang) => lang == 'ms' ? ms : en;
}

class ProgressionConfig {
  ProgressionConfig.fromJson(Map<String, dynamic> j)
    : xpPerLevelStep = j['xp_per_level_step'] as int,
      maxLevel = j['max_level'] as int,
      matchXpBase = j['match_xp_base'] as int,
      matchXpPerScore = _d(j['match_xp_per_score']),
      dailyLoginXp = j['daily_login_xp'] as int,
      streakBonusXp = j['streak_bonus_xp'] as int,
      streakCapDays = j['streak_cap_days'] as int,
      missionsPerDay = j['missions_per_day'] as int,
      missions = [for (final m in j['missions'] as List) MissionDef.fromJson(m as Map<String, dynamic>)],
      skins = [for (final s in j['skins'] as List) SkinDef.fromJson(s as Map<String, dynamic>)];

  final int xpPerLevelStep, maxLevel, matchXpBase, dailyLoginXp, streakBonusXp, streakCapDays, missionsPerDay;
  final double matchXpPerScore;
  final List<MissionDef> missions;
  final List<SkinDef> skins;
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
      blocks = BlockConfig.fromJson(f['blocks']!),
      progression = ProgressionConfig.fromJson(f['progression']!),
      facts = [
        for (final x in f['facts']!['facts'] as List)
          HazeFact((x as Map<String, dynamic>)['en'] as String, x['ms'] as String),
      ];

  static const files = [
    'weapons',
    'loot',
    'zone',
    'trees',
    'bots',
    'score',
    'map',
    'facts',
    'progression',
    'blocks',
  ];

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
  final BlockConfig blocks;
  final ProgressionConfig progression;
  final List<HazeFact> facts;
}

// ---------------------------------------------------------------- blocks

/// One kind of voxel block: how it looks, how long it takes to mine and what
/// it does when placed. Loaded from `blocks.json`.
class BlockType with Named {
  BlockType.fromJson(Map<String, dynamic> j, this.index)
    : id = j['id'] as String,
      nameEn = j['name_en'] as String,
      nameMs = j['name_ms'] as String,
      top = _hex(j['top'] as String),
      side = _hex(j['side'] as String),
      hardness = _d(j['hardness']),
      alpha = j['alpha'] == null ? 1.0 : _d(j['alpha']),
      shine = j['shine'] == null ? 0.0 : _d(j['shine']),
      glow = j['glow'] == null ? 0.0 : _d(j['glow']),
      grain = j['grain'] == null ? 0.05 : _d(j['grain']),
      bubble = j['bubble'] == null ? 0.0 : _d(j['bubble']),
      rim = j['rim'] == true,
      drop = (j['drop'] ?? j['id']) as String;

  /// Position in [BlockConfig.types]; the block id stored in the world is
  /// this + 1 (0 means air).
  final int index;
  final String id, drop;
  @override
  final String nameEn;
  @override
  final String nameMs;
  final Color top, side;

  /// Seconds to mine with bare hands, before [BlockConfig.mineSpeed].
  final double hardness;

  /// < 1 for see-through blocks (glass).
  final double alpha;

  /// Specular highlight strength, self-lit amount and colour noise.
  final double shine, glow, grain;

  /// Clean-air bubble radius this block creates in the haze (filter block).
  final double bubble;

  /// Grass-style green rim on the top of the side faces.
  final bool rim;

  bool get solid => alpha >= 0.999;
}

/// Turns a few blocks into something else. [item] recipes give an inventory
/// item (a seed pack, a water bottle) instead of a block.
class BlockRecipe {
  BlockRecipe.fromJson(Map<String, dynamic> j)
    : out = j['out'] as String,
      count = j['count'] as int,
      item = j['item'] == true,
      nameEn = j['name_en'] as String?,
      nameMs = j['name_ms'] as String?,
      inputs = (j['in'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));

  final String out;
  final int count;
  final bool item;
  final String? nameEn, nameMs;
  final Map<String, int> inputs;
}

/// A patch of minable blocks seeded onto one map area.
class BlockNodeDef {
  BlockNodeDef.fromJson(Map<String, dynamic> j)
    : area = j['area'] as String,
      block = j['block'] as String,
      clusters = j['clusters'] as int,
      size = (j['size'] as List).cast<int>(),
      stack = (j['stack'] as List).cast<int>();

  final String area, block;
  final int clusters;
  final List<int> size, stack;
}

class BlockConfig {
  BlockConfig.fromJson(Map<String, dynamic> j)
    : size = _d(j['size']),
      maxHeight = j['max_height'] as int,
      reach = _d(j['reach']),
      placeCooldown = _d(j['place_cooldown']),
      mineSpeed = _d(j['mine_speed']),
      types = [
        for (var i = 0; i < (j['types'] as List).length; i++)
          BlockType.fromJson((j['types'] as List)[i] as Map<String, dynamic>, i),
      ],
      recipes = [for (final r in j['recipes'] as List) BlockRecipe.fromJson(r as Map<String, dynamic>)],
      nodes = (j['nodes'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, [for (final n in v as List) BlockNodeDef.fromJson(n as Map<String, dynamic>)]),
      ),
      startBlocks = (j['start_blocks'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as Map<String, dynamic>).map((a, b) => MapEntry(a, b as int))),
      ),
      startSeeds = (j['start_seeds'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));

  /// World units per block edge.
  final double size;

  /// How many blocks can be stacked in one column.
  final int maxHeight;

  /// Targeting distance in blocks, and how much faster than [BlockType.hardness] mining is.
  final double reach, placeCooldown, mineSpeed;

  final List<BlockType> types;
  final List<BlockRecipe> recipes;
  final Map<String, List<BlockNodeDef>> nodes;
  final Map<String, Map<String, int>> startBlocks;
  final Map<String, int> startSeeds;

  late final Map<String, int> indexOf = {for (final t in types) t.id: t.index};

  BlockType? byId(String id) {
    final i = indexOf[id];
    return i == null ? null : types[i];
  }
}
