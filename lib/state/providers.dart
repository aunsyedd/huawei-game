import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/game_config.dart';
import '../game/systems/match_manager.dart';
import '../services/audio_service.dart';
import '../services/hms/account_service.dart';
import '../services/hms/game_service.dart';
import '../services/hms/hms_services.dart';
import 'progression.dart';

/// Overridden in main().
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final hmsServicesProvider = Provider<HmsServices>((ref) => throw UnimplementedError());

/// Silent by default (tests); main() overrides it with real audio.
final audioServiceProvider = Provider<AudioService>((ref) => SilentAudioService());

final gameConfigProvider = FutureProvider<GameConfig>((ref) => GameConfig.load());

// ---------------- Settings ----------------

class AppSettings {
  const AppSettings({
    this.language = 'en',
    this.soundVolume = 0.8,
    this.musicVolume = 0.5,
    this.sensitivity = 1.0,
    this.haptics = true,
    this.showFps = false,
    this.tutorialDone = false,
    this.storySeen = false,
    this.graphics = 3,
    this.cameraFollow = true,
    this.cameraTilt = 0.82,
  });

  final String language;
  final double soundVolume, musicVolume, sensitivity;
  final bool haptics, showFps, tutorialDone, storySeen;

  /// Graphics preset: 3 = ultra, 2 = high, 1 = medium, 0 = low.
  final int graphics;

  /// Camera swings behind the player as they move, and its tilt from
  /// straight down (bigger = closer to eye level).
  final bool cameraFollow;
  final double cameraTilt;

  Locale get locale => Locale(language);

  AppSettings copyWith({
    String? language,
    double? soundVolume,
    double? musicVolume,
    double? sensitivity,
    bool? haptics,
    bool? showFps,
    bool? tutorialDone,
    bool? storySeen,
    int? graphics,
    bool? cameraFollow,
    double? cameraTilt,
  }) => AppSettings(
    language: language ?? this.language,
    soundVolume: soundVolume ?? this.soundVolume,
    musicVolume: musicVolume ?? this.musicVolume,
    sensitivity: sensitivity ?? this.sensitivity,
    haptics: haptics ?? this.haptics,
    showFps: showFps ?? this.showFps,
    tutorialDone: tutorialDone ?? this.tutorialDone,
    storySeen: storySeen ?? this.storySeen,
    graphics: graphics ?? this.graphics,
    cameraFollow: cameraFollow ?? this.cameraFollow,
    cameraTilt: cameraTilt ?? this.cameraTilt,
  );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _p => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final p = ref.read(sharedPrefsProvider);
    return AppSettings(
      language: p.getString('language') ?? 'en',
      soundVolume: p.getDouble('sound') ?? 0.8,
      musicVolume: p.getDouble('music') ?? 0.5,
      sensitivity: p.getDouble('sensitivity') ?? 1.0,
      haptics: p.getBool('haptics') ?? true,
      showFps: p.getBool('show_fps') ?? false,
      tutorialDone: p.getBool('tutorial_done') ?? false,
      storySeen: p.getBool('story_seen') ?? false,
      graphics: p.getInt('graphics') ?? 3,
      cameraFollow: p.getBool('camera_follow') ?? true,
      cameraTilt: p.getDouble('camera_tilt') ?? 0.82,
    );
  }

  void setLanguage(String v) {
    state = state.copyWith(language: v);
    _p.setString('language', v);
  }

  void setSound(double v) {
    state = state.copyWith(soundVolume: v);
    ref.read(audioServiceProvider).setVolumes(sfx: v);
    _p.setDouble('sound', v);
  }

  void setMusic(double v) {
    state = state.copyWith(musicVolume: v);
    ref.read(audioServiceProvider).setVolumes(music: v);
    _p.setDouble('music', v);
  }

  void setSensitivity(double v) {
    state = state.copyWith(sensitivity: v);
    _p.setDouble('sensitivity', v);
  }

  void setHaptics(bool v) {
    state = state.copyWith(haptics: v);
    _p.setBool('haptics', v);
  }

  void setShowFps(bool v) {
    state = state.copyWith(showFps: v);
    _p.setBool('show_fps', v);
  }

  void setStorySeen(bool v) {
    state = state.copyWith(storySeen: v);
    _p.setBool('story_seen', v);
  }

  void setGraphics(int v) {
    state = state.copyWith(graphics: v);
    _p.setInt('graphics', v);
  }

  void setCameraFollow(bool v) {
    state = state.copyWith(cameraFollow: v);
    _p.setBool('camera_follow', v);
  }

  void setCameraTilt(double v) {
    state = state.copyWith(cameraTilt: v);
    _p.setDouble('camera_tilt', v);
  }

  void setTutorialDone(bool v) {
    state = state.copyWith(tutorialDone: v);
    _p.setBool('tutorial_done', v);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------------- Account ----------------

class AccountNotifier extends Notifier<PlayerAccount?> {
  AccountService get _svc => ref.read(hmsServicesProvider).account;

  @override
  PlayerAccount? build() => ref.read(hmsServicesProvider).account.current;

  Future<void> signIn() async => state = await _svc.signIn();

  Future<void> signOut() async {
    await _svc.signOut();
    state = null;
  }
}

final accountProvider = NotifierProvider<AccountNotifier, PlayerAccount?>(AccountNotifier.new);

// ---------------- Profile stats ----------------

class ProfileStats {
  const ProfileStats({this.matches = 0, this.wins = 0, this.tagOuts = 0, this.trees = 0, this.bestScore = 0});

  final int matches, wins, tagOuts, trees, bestScore;
}

/// What the results screen shows.
class MatchSummary {
  const MatchSummary({
    required this.result,
    required this.score,
    required this.fact,
    required this.newBest,
    required this.unlocked,
    required this.reward,
  });

  final PlayerResult result;
  final int score;
  final HazeFact fact;
  final bool newBest;
  final List<String> unlocked;
  final MatchReward reward;
}

class ProfileNotifier extends Notifier<ProfileStats> {
  SharedPreferences get _p => ref.read(sharedPrefsProvider);

  @override
  ProfileStats build() {
    final p = ref.read(sharedPrefsProvider);
    return ProfileStats(
      matches: p.getInt('stat_matches') ?? 0,
      wins: p.getInt('stat_wins') ?? 0,
      tagOuts: p.getInt('stat_tags') ?? 0,
      trees: p.getInt('stat_trees') ?? 0,
      bestScore: p.getInt('stat_best') ?? 0,
    );
  }

  /// Saves stats, submits leaderboards, unlocks achievements.
  Future<MatchSummary> recordMatch(PlayerResult r, GameConfig cfg) async {
    final score = r.score(cfg.score);
    final s = state;
    final next = ProfileStats(
      matches: s.matches + 1,
      wins: s.wins + (r.won ? 1 : 0),
      tagOuts: s.tagOuts + r.tagOuts,
      trees: s.trees + r.treesPlanted,
      bestScore: math.max(s.bestScore, score),
    );
    state = next;
    await _p.setInt('stat_matches', next.matches);
    await _p.setInt('stat_wins', next.wins);
    await _p.setInt('stat_tags', next.tagOuts);
    await _p.setInt('stat_trees', next.trees);
    await _p.setInt('stat_best', next.bestScore);

    final game = ref.read(hmsServicesProvider).game;
    await game.submitScore(Leaderboards.wins, next.wins);
    await game.submitScore(Leaderboards.treesPlanted, next.trees);
    await game.submitScore(Leaderboards.tagOuts, next.tagOuts);

    final earned = <String>[
      Achievements.firstMatch,
      if (r.won) Achievements.firstWin,
      if (r.won && r.tagOuts == 0) Achievements.pacifistWin,
      if (r.treesPlanted >= 10) Achievements.greenThumb,
      if (next.trees >= 50) Achievements.forestMaker,
      if (r.tagOuts >= 5) Achievements.sharpshooter,
      if (r.timeSurvived >= 180) Achievements.survivor,
      if (r.won && r.hazeTime >= 30) Achievements.hazeWalker,
    ];
    final unlocked = <String>[];
    for (final id in earned) {
      if (await game.unlockAchievement(id)) unlocked.add(id);
    }

    final fact = cfg.facts[math.Random().nextInt(cfg.facts.length)];
    final reward = ref.read(progressProvider.notifier).applyMatch(cfg, r, score);
    return MatchSummary(
      result: r,
      score: score,
      fact: fact,
      newBest: score > s.bestScore,
      unlocked: unlocked,
      reward: reward,
    );
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileStats>(ProfileNotifier.new);

class LastMatchNotifier extends Notifier<MatchSummary?> {
  @override
  MatchSummary? build() => null;

  void set(MatchSummary s) => state = s;
}

final lastMatchProvider = NotifierProvider<LastMatchNotifier, MatchSummary?>(LastMatchNotifier.new);

// ---------------- Progression (levels, missions, streak, skins) ----------------

class ProgressNotifier extends Notifier<ProgressState> {
  static const _key = 'progress_v1';
  SharedPreferences get _p => ref.read(sharedPrefsProvider);

  @override
  ProgressState build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const ProgressState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ProgressState(
        xp: j['xp'] as int,
        streak: j['streak'] as int,
        lastLoginDay: j['lastLoginDay'] as int,
        missionDay: j['missionDay'] as int,
        progress: (j['progress'] as List).cast<int>(),
        done: (j['done'] as List).cast<bool>(),
        skin: j['skin'] as int,
      );
    } catch (_) {
      return const ProgressState();
    }
  }

  void _save(ProgressState s) {
    state = s;
    _p.setString(
      _key,
      jsonEncode({
        'xp': s.xp,
        'streak': s.streak,
        'lastLoginDay': s.lastLoginDay,
        'missionDay': s.missionDay,
        'progress': s.progress,
        'done': s.done,
        'skin': s.skin,
      }),
    );
  }

  /// Daily login bonus; returns the XP granted (0 if already claimed today).
  int login(GameConfig cfg, {DateTime? now}) {
    final (next, bonus) = Progression(cfg.progression).login(state, Progression.dayNumber(now ?? DateTime.now()));
    _save(next);
    return bonus;
  }

  MatchReward applyMatch(GameConfig cfg, PlayerResult r, int score, {DateTime? now}) {
    final (next, reward) = Progression(cfg.progression)
        .applyMatch(state, r, score, Progression.dayNumber(now ?? DateTime.now()));
    _save(next);
    return reward;
  }

  void setSkin(int index) => _save(state.copyWith(skin: index));
}

final progressProvider = NotifierProvider<ProgressNotifier, ProgressState>(ProgressNotifier.new);
