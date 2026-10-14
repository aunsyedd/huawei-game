import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../state/providers.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final summary = ref.watch(lastMatchProvider);
    if (summary == null) {
      return Scaffold(
        body: HazeBackground(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                TextButton(onPressed: () => context.go('/'), child: Text(s('menu'))),
              ],
            ),
          ),
        ),
      );
    }
    final r = summary.result;
    final t = r.timeSurvived.round();
    final rs = Responsive.of(context);
    final tileW = rs.compact ? 128.0 : 150.0;
    return Scaffold(
      body: HazeBackground(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: rs.compact ? 14 : 24, vertical: rs.compact ? 4 : 12),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: CenteredScroll(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.won ? s('you_win') : s('results'),
                        style: TextStyle(
                          fontSize: rs.compact ? 24 : 32,
                          fontWeight: FontWeight.w900,
                          color: r.won ? Colors.amber : Colors.white,
                        ),
                      ),
                      SizedBox(height: rs.compact ? 6 : 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _tile(
                            Icons.emoji_events,
                            s('placement'),
                            s('placement_of', {'p': r.placement, 'n': r.totalPlayers}),
                            tileW,
                          ),
                          _tile(Icons.water_drop, s('tags'), '${r.tagOuts}', tileW),
                          _tile(Icons.park, s('trees_planted'), '${r.treesPlanted}', tileW),
                          _tile(
                            Icons.timer,
                            s('time_survived'),
                            '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}',
                            tileW,
                          ),
                        ],
                      ),
                      SizedBox(height: rs.compact ? 6 : 14),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: summary.score.toDouble()),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${s('score')}: ',
                              style: TextStyle(fontSize: rs.compact ? 18 : 22, color: Colors.white70),
                            ),
                            Text(
                              '${v.round()}',
                              style: TextStyle(
                                fontSize: rs.compact ? 26 : 34,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFFFCC80),
                              ),
                            ),
                            if (summary.newBest) ...[
                              const SizedBox(width: 10),
                              Chip(label: Text(s('new_best')), backgroundColor: AppColors.leaf),
                            ],
                          ],
                        ),
                      ),
                      for (final a in summary.unlocked)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.military_tech, color: Colors.amber, size: 18),
                              const SizedBox(width: 6),
                              Flexible(child: Text(s('achievement_unlocked', {'name': s('ach_$a')}))),
                            ],
                          ),
                        ),
                      SizedBox(height: rs.compact ? 8 : 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              ref.read(audioServiceProvider).sfx('ui_click');
                              context.go('/lobby');
                            },
                            icon: const Icon(Icons.replay),
                            label: Text(s('play_again')),
                          ),
                          OutlinedButton(onPressed: () => context.go('/'), child: Text(s('menu'))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: CenteredScroll(
                  child: Card(
                    color: const Color(0xFF1B3A24),
                    child: Padding(
                      padding: EdgeInsets.all(rs.compact ? 12 : 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lightbulb, color: Colors.amber),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  s('did_you_know'),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            summary.fact.text(s.lang),
                            style: TextStyle(fontSize: rs.compact ? 14 : 16, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value, double width) => Container(
    width: width,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0xCC16283A), borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.white60),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}
