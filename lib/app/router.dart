import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/game/game_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/results/results_screen.dart';
import '../features/settings/settings_screen.dart';

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 250),
  transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
);

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', pageBuilder: (c, s) => _fade(s, const MenuScreen())),
    GoRoute(path: '/lobby', pageBuilder: (c, s) => _fade(s, const LobbyScreen())),
    GoRoute(path: '/game', pageBuilder: (c, s) => _fade(s, const GameScreen())),
    GoRoute(path: '/results', pageBuilder: (c, s) => _fade(s, const ResultsScreen())),
    GoRoute(path: '/leaderboard', pageBuilder: (c, s) => _fade(s, const LeaderboardScreen())),
    GoRoute(path: '/settings', pageBuilder: (c, s) => _fade(s, const SettingsScreen())),
  ],
);
