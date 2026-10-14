import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../services/hms/game_service.dart';
import '../../state/providers.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _board = Leaderboards.wins;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final game = ref.read(hmsServicesProvider).game;
    final me = ref.watch(accountProvider)?.displayName ?? (s.lang == 'ms' ? 'Anda' : 'You');
    final r = Responsive.of(context);
    final labels = {
      Leaderboards.wins: s('wins'),
      Leaderboards.treesPlanted: s('total_trees'),
      Leaderboards.tagOuts: s('total_tags'),
    };

    return Scaffold(
      body: HazeBackground(
        child: Padding(
          padding: EdgeInsets.all(r.compact ? 8 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back)),
                        Flexible(
                          child: Text(
                            s('leaderboard'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<String>(
                        segments: [for (final b in Leaderboards.all) ButtonSegment(value: b, label: Text(labels[b]!))],
                        selected: {_board},
                        onSelectionChanged: (v) => setState(() => _board = v.first),
                        showSelectedIcon: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<LeaderboardEntry>>(
                        key: ValueKey(_board),
                        future: game.topScores(_board, myName: me),
                        builder: (context, snap) {
                          final rows = snap.data;
                          if (rows == null) return const Center(child: CircularProgressIndicator());
                          return ListView(
                            children: [
                              for (final e in rows)
                                Card(
                                  color: e.isMe ? const Color(0xFF1B5E20) : null,
                                  margin: const EdgeInsets.symmetric(vertical: 3),
                                  child: ListTile(
                                    dense: true,
                                    visualDensity: r.compact ? VisualDensity.compact : null,
                                    leading: Text(
                                      '#${e.rank}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                    ),
                                    title: Text(e.name),
                                    trailing: Text(
                                      '${e.score}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: r.compact ? 8 : 16),
              Expanded(
                flex: 2,
                child: FutureBuilder<Set<String>>(
                  future: game.unlockedAchievements(),
                  builder: (context, snap) {
                    final got = snap.data ?? const <String>{};
                    return Card(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Text(s('achievements'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          for (final a in Achievements.all)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                got.contains(a) ? Icons.military_tech : Icons.lock_outline,
                                color: got.contains(a) ? Colors.amber : Colors.white30,
                              ),
                              title: Text(
                                s('ach_$a'),
                                style: TextStyle(color: got.contains(a) ? Colors.white : Colors.white54, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
