import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/game/components/actor.dart';
import 'package:haze_royale/game/systems/match_manager.dart';

import 'simulation_test.dart' show loadConfig;

void main() {
  final config = loadConfig();
  final blockCfg = config.blocks;
  final stone = blockCfg.indexOf['stone']!;
  final plank = blockCfg.indexOf['plank']!;
  final filter = blockCfg.indexOf['filter']!;

  /// A match with the player alone in the open, ready to build.
  MatchSimulation openField({int seed = 11}) {
    final sim = MatchSimulation(config, seed: seed)..start(1500, 1500);
    for (final a in sim.actors.skip(1)) {
      a.alive = false;
    }
    sim.aliveCount = 2;
    final spot = sim.map.randomFreePoint(sim.rng, outdoorOnly: true, r: 120);
    sim.player.pos.setValues(spot.dx, spot.dy);
    return sim;
  }

  test('the island is seeded with minable resource patches', () {
    final sim = MatchSimulation(config, seed: 1);
    expect(sim.blocks.blockCount, greaterThan(100));
    final craft = MatchSimulation(config, seed: 1, mode: GameMode.craft);
    expect(craft.blocks.blockCount, greaterThan(sim.blocks.blockCount));
  });

  test('placing takes a block from the bag and stacks it in front', () {
    final sim = openField();
    final p = sim.player
      ..aimAngle = 0
      ..give(plank, 3);
    final (bx, by) = sim.targetColumn(p);
    expect(sim.blocks.height(bx, by), 0);

    expect(sim.placeBlock(p), isTrue);
    expect(sim.blocks.height(bx, by), 1);
    expect(p.carried(plank), 2);
    expect(p.blocksPlaced, 1);

    // A second block stacks on the same column, not beside it.
    p.placeCooldown = 0;
    expect(sim.placeBlock(p), isTrue);
    expect(sim.blocks.height(bx, by), 2);
    expect(sim.targetColumn(p), (bx, by));
  });

  test('mining the column in front returns the block to the bag', () {
    final sim = openField();
    final p = sim.player
      ..aimAngle = 0
      ..give(plank, 1);
    sim.placeBlock(p);
    final (bx, by) = sim.targetColumn(p);
    expect(p.carried(plank), 0);

    expect(sim.startMining(p), isTrue);
    expect(p.action, ActorAction.mining);
    for (var i = 0; i < 120 && p.busy; i++) {
      sim.update(1 / 60);
    }
    expect(sim.blocks.height(bx, by), 0);
    expect(p.carried(plank), 1);
    expect(p.blocksMined, 1);
  });

  test('a stone block drops cobblestone and blocks movement', () {
    final sim = openField();
    final p = sim.player..aimAngle = 0;
    final (bx, by) = sim.targetColumn(p);
    sim.blocks.set(bx, by, 0, stone);
    final cx = sim.blocks.wx(bx), cy = sim.blocks.wy(by);

    expect(sim.free(cx, cy, Actor.radius), isFalse);
    // Walking east pushes up against the block instead of through it.
    p.moveInput.setValues(1, 0);
    for (var i = 0; i < 90; i++) {
      sim.update(1 / 60);
    }
    expect(p.pos.x, lessThan(cx - Actor.radius * 0.5));

    sim.startMining(p);
    for (var i = 0; i < 200 && p.busy; i++) {
      sim.update(1 / 60);
    }
    expect(p.carried(blockCfg.indexOf['cobble']!), 1);
  });

  test('crafting spends the inputs and can make a seed pack', () {
    final sim = openField();
    final p = sim.player;
    final recipes = blockCfg.recipes;
    final seedRecipe = recipes.indexWhere((r) => r.out == 'seed');
    expect(seedRecipe, isNot(-1));

    expect(sim.canCraft(p, seedRecipe), isFalse);
    p
      ..give(blockCfg.indexOf['leaves']!, 3)
      ..give(blockCfg.indexOf['dirt']!, 2);
    final seeds = p.seeds;
    expect(sim.craft(p, seedRecipe), isTrue);
    expect(p.seeds, seeds + 1);
    expect(p.carried(blockCfg.indexOf['leaves']!), 0);
    expect(p.carried(blockCfg.indexOf['dirt']!), 0);
  });

  test('an air filter block makes clean air in the haze', () {
    final sim = openField();
    final p = sim.player..aimAngle = 0;
    final (bx, by) = sim.targetColumn(p);
    final cx = sim.blocks.wx(bx), cy = sim.blocks.wy(by);
    // Push the haze far away so only the block can be keeping this spot safe.
    sim.zone
      ..cx = 0
      ..cy = 0
      ..r = 10;
    expect(sim.isSafeAt(cx, cy), isFalse);
    sim.blocks.set(bx, by, 0, filter);
    expect(sim.isSafeAt(cx, cy), isTrue);
    expect(sim.isSafeAt(cx + 400, cy), isFalse);
  });

  test('blasters chew through a block wall', () {
    final sim = openField();
    final p = sim.player..aimAngle = 0;
    final (bx, by) = sim.targetColumn(p);
    sim.blocks.set(bx, by, 0, blockCfg.indexOf['leaves']!);
    p.wantFire = true;
    for (var i = 0; i < 60 * 6 && sim.blocks.height(bx, by) > 0; i++) {
      sim.update(1 / 60);
    }
    expect(sim.blocks.height(bx, by), 0, reason: 'leaves should not survive six seconds of blaster fire');
  });

  test('Blok Craft runs on alone, with no bots and no haze', () {
    final sim = MatchSimulation(config, seed: 7, mode: GameMode.craft);
    expect(sim.actors.length, 1);
    expect(sim.hazeActive, isFalse);
    sim.start(1500, 1500);
    expect(sim.player.carried(blockCfg.indexOf['plank']!), greaterThan(0));
    expect(sim.player.seeds, greaterThan(0));

    final startR = sim.zone.r;
    for (var i = 0; i < 60 * 240; i++) {
      sim.update(1 / 60);
    }
    expect(sim.phase, MatchPhase.running, reason: 'the sandbox never ends by itself');
    expect(sim.zone.r, startR, reason: 'the haze does not close in');
    expect(sim.player.health, sim.player.maxHealth);
  });

  test('the target column is the nearest block within reach', () {
    final sim = openField();
    final p = sim.player..aimAngle = 0;
    final far = sim.targetColumn(p);
    // Drop a block halfway there; it becomes the target instead.
    final near = (sim.blocks.gx(p.pos.x + blockCfg.size * 1.1), sim.blocks.gy(p.pos.y));
    expect(near, isNot(far));
    sim.blocks.set(near.$1, near.$2, 0, stone);
    expect(sim.targetColumn(p), near);

    // Aiming somewhere else picks a different column again.
    p.aimAngle = math.pi;
    expect(sim.targetColumn(p), isNot(near));
  });
}
