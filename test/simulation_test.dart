import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/data/game_config.dart';
import 'package:haze_royale/game/components/actor.dart';
import 'package:haze_royale/game/systems/match_manager.dart';

GameConfig loadConfig() =>
    GameConfig.fromSources({for (final f in GameConfig.files) f: File('assets/data/$f.json').readAsStringSync()});

void main() {
  final config = loadConfig();

  test('map generates buildings, walls and obstacles', () {
    final sim = MatchSimulation(config, seed: 1);
    expect(sim.map.buildings.length, greaterThanOrEqualTo(20));
    expect(sim.map.obstacles, isNotEmpty);
    expect(sim.loot.length, greaterThan(100));
    for (final b in sim.map.buildings) {
      expect(
        sim.map.isFree(b.doorOutside.dx, b.doorOutside.dy, 10),
        isTrue,
        reason: 'door outside of ${b.rect} blocked',
      );
    }
  });

  test('armour absorbs part of the damage', () {
    final sim = MatchSimulation(config, seed: 2)..start(1500, 1500);
    final a = sim.actors[1];
    a.vest = config.loot.armour.last;
    a.armour = a.vest!.armour;
    sim.combat.damage(a, 40, cause: 'test');
    expect(a.health, closeTo(100 - 40 * (1 - a.vest!.absorb), 0.01));
  });

  test('planting takes time and creates a growing tree', () {
    final sim = MatchSimulation(config, seed: 3)..start(1500, 1500);
    for (final a in sim.actors.skip(1)) {
      a.alive = false; // keep bots out of the way
    }
    sim.aliveCount = 2;
    final p = sim.player..seeds = 1;
    final spot = sim.map.randomFreePoint(sim.rng, outdoorOnly: true);
    p.pos.setValues(spot.dx, spot.dy);
    expect(sim.startAction(p, ActorAction.planting), isTrue);
    for (var i = 0; i < 70; i++) {
      sim.update(1 / 30);
    }
    expect(sim.trees.length, 1);
    expect(p.treesPlanted, 1);
    for (var i = 0; i < 30 * 45; i++) {
      sim.update(1 / 30);
    }
    expect(sim.trees.first.stage, 2);
    expect(sim.inTreeBubble(p.pos.x, p.pos.y), isTrue);
  });

  test('5 full headless matches finish without stuck bots', () {
    for (var m = 0; m < 5; m++) {
      final sim = MatchSimulation(config, seed: 100 + m, autopilotPlayer: true);
      sim.start(1500, 1500);
      const dt = 1 / 30;
      final sw = Stopwatch()..start();
      var steps = 0;
      var maxStuck = 0.0;
      while (sim.phase != MatchPhase.ended && sim.time < 700) {
        sim.update(dt);
        steps++;
        for (final a in sim.actors) {
          if (!a.alive) continue;
          expect(a.pos.x.isFinite && a.pos.y.isFinite, isTrue);
          if (a.brain!.stuckSeconds > maxStuck) maxStuck = a.brain!.stuckSeconds;
        }
      }
      sw.stop();
      final planted = sim.actors.fold(0, (s, a) => s + a.treesPlanted);
      final tags = sim.actors.fold(0, (s, a) => s + a.tagOuts);
      final hazeOuts = sim.feed.where((f) => f.cause == 'haze').length;
      // ignore: avoid_print
      print(
        'match $m: ${sim.time.toStringAsFixed(0)}s, winner ${sim.winner?.name}, '
        'tag-outs $tags, haze outs $hazeOuts, trees $planted, max stuck ${maxStuck}s, '
        'sim ${(sw.elapsedMicroseconds / steps / 1000).toStringAsFixed(2)} ms/step',
      );
      expect(sim.phase, MatchPhase.ended);
      expect(sim.winner, isNotNull);
      expect(sim.playerResult, isNotNull);
      expect(maxStuck, lessThan(15), reason: 'a bot made no progress for too long');
    }
  });
}
