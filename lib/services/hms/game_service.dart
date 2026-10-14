import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Leaderboard ids (map these to AppGallery Connect ids in the HMS implementation).
abstract final class Leaderboards {
  static const wins = 'wins';
  static const treesPlanted = 'trees_planted';
  static const tagOuts = 'total_tag_outs';
  static const all = [wins, treesPlanted, tagOuts];
}

/// Achievement ids; display names live in l10n as `ach_<id>`.
abstract final class Achievements {
  static const firstMatch = 'first_match';
  static const firstWin = 'first_win';
  static const pacifistWin = 'pacifist_win';
  static const greenThumb = 'green_thumb';
  static const forestMaker = 'forest_maker';
  static const sharpshooter = 'sharpshooter';
  static const survivor = 'survivor';
  static const hazeWalker = 'haze_walker';
  static const all = [firstMatch, firstWin, pacifistWin, greenThumb, forestMaker, sharpshooter, survivor, hazeWalker];
}

class LeaderboardEntry {
  const LeaderboardEntry(this.rank, this.name, this.score, {this.isMe = false});
  final int rank;
  final String name;
  final int score;
  final bool isMe;
}

/// Huawei Game Service (leaderboards + achievements), behind an interface.
abstract class GameService {
  Future<void> submitScore(String leaderboardId, int score);
  Future<List<LeaderboardEntry>> topScores(String leaderboardId, {required String myName});

  /// Returns true when this call newly unlocked it.
  Future<bool> unlockAchievement(String id);
  Future<Set<String>> unlockedAchievements();
}

/// Offline stand-in: stores the player's totals on the device and mixes them
/// into a fixed field of local rivals.
class FakeGameService implements GameService {
  FakeGameService(this._prefs);
  final SharedPreferences _prefs;

  static const _rivals = ['Aiman', 'Siti', 'Mei Ling', 'Arjun', 'Nurul', 'Wei Jie', 'Kavitha', 'Faris', 'Aisyah'];

  @override
  Future<void> submitScore(String leaderboardId, int score) async {
    await _prefs.setInt('lb_$leaderboardId', score);
  }

  @override
  Future<List<LeaderboardEntry>> topScores(String leaderboardId, {required String myName}) async {
    final rng = math.Random(leaderboardId.length * 7919);
    final scale = switch (leaderboardId) {
      Leaderboards.wins => 12,
      Leaderboards.treesPlanted => 120,
      _ => 90,
    };
    final rows = <(String, int, bool)>[
      for (final r in _rivals) (r, rng.nextInt(scale) + 1, false),
      (myName, _prefs.getInt('lb_$leaderboardId') ?? 0, true),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (var i = 0; i < rows.length; i++) LeaderboardEntry(i + 1, rows[i].$1, rows[i].$2, isMe: rows[i].$3)];
  }

  @override
  Future<bool> unlockAchievement(String id) async {
    final set = await unlockedAchievements();
    if (set.contains(id)) return false;
    await _prefs.setStringList('achievements', [...set, id]);
    return true;
  }

  @override
  Future<Set<String>> unlockedAchievements() async => (_prefs.getStringList('achievements') ?? const []).toSet();
}
