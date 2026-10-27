import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../state/providers.dart';

/// The game's story in four short cards. Shown on first launch and from the menu.
class StoryScreen extends ConsumerStatefulWidget {
  const StoryScreen({super.key});

  @override
  ConsumerState<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends ConsumerState<StoryScreen> {
  int _page = 0;

  static const _icons = [Icons.local_fire_department, Icons.water_drop, Icons.park, Icons.emoji_events];
  static const _colors = [Color(0xFFBF7A3A), AppColors.sky, AppColors.leaf, Color(0xFFFFCA28)];

  void _finish() {
    ref.read(settingsProvider.notifier).setStorySeen(true);
    ref.read(audioServiceProvider).sfx('ui_click');
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final r = Responsive.of(context);
    final last = _page == 3;
    final n = _page + 1;
    return Scaffold(
      body: HazeBackground(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: r.compact ? 16 : 32, vertical: r.compact ? 8 : 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(onPressed: _finish, child: Text(s('skip'))),
              ),
              Expanded(
                child: CenteredScroll(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Row(
                      key: ValueKey(_page),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: r.s(110),
                          height: r.s(110),
                          decoration: BoxDecoration(
                            color: _colors[_page].withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icons[_page], size: r.s(64), color: _colors[_page]),
                        ),
                        SizedBox(width: r.s(28)),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s('story_${n}_title'),
                                  style: TextStyle(fontSize: r.compact ? 24 : 30, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 10),
                                Text(s('story_$n'), style: TextStyle(fontSize: r.compact ? 15 : 18, height: 1.4)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: last
                        ? _finish
                        : () {
                            ref.read(audioServiceProvider).sfx('ui_click');
                            setState(() => _page++);
                          },
                    icon: Icon(last ? Icons.play_arrow_rounded : Icons.arrow_forward),
                    label: Text(last ? s('lets_go') : s('next')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
