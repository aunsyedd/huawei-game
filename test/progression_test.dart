import 'package:flutter_test/flutter_test.dart';
import 'package:haze_royale/game/systems/match_manager.dart';
import 'package:haze_royale/state/progression.dart';

import 'simulation_test.dart' show loadConfig;

PlayerResult result({int placement = 10, int tags = 0, int trees = 0, double time = 60, bool won = false}) => PlayerResult(
  placement: placement,
  totalPlayers: 25,
  tagOuts: tags,
  treesPlanted: trees,
  treesAlive: trees,
  timeSurvived: time,
  hazeTime: 0,
  damageDealt: 0,
  won: won,
);

void main() {
  final cfg = loadConfig().progression;
  final p = Progression(cfg);

  test('levels grow with XP and progress stays in 0..1', () {
    expect(p.levelFor(0), 1);
    expect(p.levelFor(p.xpForLevel(2)), 2);
    expect(p.levelFor(p.xpForLevel(5) - 1), 4);
    expect(p.levelFor(1 << 30), cfg.maxLevel);
    for (final xp in [0, 10, 149, 150, 1000, 99999]) {
      expect(p.levelProgress(xp), inInclusiveRange(0, 1));
    }
  });

  test('daily missions: fixed per day, one per type, change between days', () {
    final a = p.missionsFor(20000), b = p.missionsFor(20000), c = p.missionsFor(20001);
    expect(a.map((m) => m.id), b.map((m) => m.id));
    expect(a.length, cfg.missionsPerDay);
    expect(a.map((m) => m.type).toSet().length, a.length);
    expect({for (var d = 20000; d < 20010; d++) p.missionsFor(d).map((m) => m.id).join()}.length, greaterThan(1));
    expect(c, isNotEmpty);
  });

  test('login streak: consecutive days build a bonus, a gap resets it, same day pays once', () {
    var s = const ProgressState();
    int bonus;
    (s, bonus) = p.login(s, 100);
    expect(s.streak, 1);
    expect(bonus, cfg.dailyLoginXp);
    (s, bonus) = p.login(s, 100);
    expect(bonus, 0);
    (s, bonus) = p.login(s, 101);
    expect(s.streak, 2);
    expect(bonus, cfg.dailyLoginXp + cfg.streakBonusXp);
    (s, bonus) = p.login(s, 105);
    expect(s.streak, 1);
  });

  test('matches give XP, complete missions once and unlock skins on level-up', () {
    const day = 30000;
    final missions = p.missionsFor(day);
    var s = const ProgressState();
    // A huge match completes every mission type at once.
    final big = result(placement: 1, tags: 99, trees: 99, time: 999, won: true);
    final (s1, r1) = p.applyMatch(s, big, 1000, day);
    expect(r1.missionsCompleted.length, missions.length);
    expect(r1.xpGained, greaterThan(missions.fold<int>(0, (a, m) => a + m.xp)));
    expect(s1.done.every((d) => d), isTrue);
    expect(r1.newSkins, isNotEmpty); // levelled past level 2
    // Same day again: missions already done, only match XP.
    final (_, r2) = p.applyMatch(s1, big, 1000, day);
    expect(r2.missionsCompleted, isEmpty);
    // Next day: fresh missions.
    final (s3, _) = p.applyMatch(s1, result(), 100, day + 1);
    expect(s3.missionDay, day + 1);
    s = s3;
    expect(s.xp, greaterThan(s1.xp));
  });
}
