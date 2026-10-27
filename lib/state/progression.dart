import 'dart:math' as math;

import '../data/game_config.dart';
import '../game/systems/match_manager.dart';

/// Saved progression: XP / level, daily login streak, today's missions, skin.
class ProgressState {
  const ProgressState({
    this.xp = 0,
    this.streak = 0,
    this.lastLoginDay = -1,
    this.missionDay = -1,
    this.progress = const [],
    this.done = const [],
    this.skin = 0,
  });

  final int xp, streak, lastLoginDay, missionDay, skin;

  /// Progress / completion for each of today's missions (same order as [Progression.missionsFor]).
  final List<int> progress;
  final List<bool> done;

  ProgressState copyWith({
    int? xp,
    int? streak,
    int? lastLoginDay,
    int? missionDay,
    List<int>? progress,
    List<bool>? done,
    int? skin,
  }) => ProgressState(
    xp: xp ?? this.xp,
    streak: streak ?? this.streak,
    lastLoginDay: lastLoginDay ?? this.lastLoginDay,
    missionDay: missionDay ?? this.missionDay,
    progress: progress ?? this.progress,
    done: done ?? this.done,
    skin: skin ?? this.skin,
  );
}

/// What one match earned, for the results screen.
class MatchReward {
  const MatchReward({
    required this.xpGained,
    required this.levelBefore,
    required this.levelAfter,
    required this.missionsCompleted,
    required this.newSkins,
  });

  final int xpGained, levelBefore, levelAfter;
  final List<MissionDef> missionsCompleted;
  final List<SkinDef> newSkins;
  bool get levelledUp => levelAfter > levelBefore;
}

/// Pure progression rules (no storage), so they can be unit-tested.
class Progression {
  Progression(this.cfg);
  final ProgressionConfig cfg;

  static int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

  /// Total XP needed to reach [level] (level 1 = 0 XP).
  int xpForLevel(int level) => cfg.xpPerLevelStep * (level - 1) * level ~/ 2;

  int levelFor(int xp) {
    var l = 1;
    while (l < cfg.maxLevel && xp >= xpForLevel(l + 1)) {
      l++;
    }
    return l;
  }

  /// 0..1 progress from the current level to the next.
  double levelProgress(int xp) {
    final l = levelFor(xp);
    if (l >= cfg.maxLevel) return 1;
    final a = xpForLevel(l), b = xpForLevel(l + 1);
    return (xp - a) / (b - a);
  }

  /// Today's missions: a fixed daily pick (same for everyone that day), one per type.
  List<MissionDef> missionsFor(int day) {
    final pool = [...cfg.missions]..shuffle(math.Random(day * 7919 + 13));
    final picked = <MissionDef>[];
    final types = <String>{};
    for (final m in pool) {
      if (types.add(m.type)) picked.add(m);
      if (picked.length == cfg.missionsPerDay) break;
    }
    return picked;
  }

  List<SkinDef> unlockedSkins(int xp) => [
    for (final s in cfg.skins)
      if (s.level <= levelFor(xp)) s,
  ];

  ProgressState _freshMissions(ProgressState s, int day) => s.missionDay == day
      ? s
      : s.copyWith(
          missionDay: day,
          progress: List.filled(cfg.missionsPerDay, 0),
          done: List.filled(cfg.missionsPerDay, false),
        );

  /// First open of the day: streak + daily bonus XP. Returns the bonus (0 if already claimed today).
  (ProgressState, int) login(ProgressState s, int today) {
    s = _freshMissions(s, today);
    if (s.lastLoginDay == today) return (s, 0);
    final streak = s.lastLoginDay == today - 1 ? s.streak + 1 : 1;
    final bonus = cfg.dailyLoginXp + cfg.streakBonusXp * (math.min(streak, cfg.streakCapDays) - 1);
    return (s.copyWith(streak: streak, lastLoginDay: today, xp: s.xp + bonus), bonus);
  }

  (ProgressState, MatchReward) applyMatch(ProgressState s, PlayerResult r, int score, int today) {
    s = _freshMissions(s, today);
    final missions = missionsFor(today);
    final progress = [...s.progress];
    final done = [...s.done];
    final completed = <MissionDef>[];
    var xp = cfg.matchXpBase + (score * cfg.matchXpPerScore).round();
    for (var i = 0; i < missions.length && i < progress.length; i++) {
      if (done[i]) continue;
      final m = missions[i];
      progress[i] = switch (m.type) {
        'trees' => progress[i] + r.treesPlanted,
        'tag_outs' => progress[i] + r.tagOuts,
        'survive_seconds' => math.max(progress[i], r.timeSurvived.round()),
        'top5' => progress[i] + (r.placement <= 5 ? 1 : 0),
        'matches' => progress[i] + 1,
        'wins' => progress[i] + (r.won ? 1 : 0),
        _ => progress[i],
      };
      if (progress[i] >= m.target) {
        progress[i] = m.target;
        done[i] = true;
        xp += m.xp;
        completed.add(m);
      }
    }
    final before = levelFor(s.xp);
    final after = levelFor(s.xp + xp);
    final newSkins = [
      for (final k in cfg.skins)
        if (k.level > before && k.level <= after) k,
    ];
    return (
      s.copyWith(xp: s.xp + xp, progress: progress, done: done),
      MatchReward(
        xpGained: xp,
        levelBefore: before,
        levelAfter: after,
        missionsCompleted: completed,
        newSkins: newSkins,
      ),
    );
  }
}
