import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';

/// In-game user guide: how to play, in English and Bahasa Malaysia.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const sections = [
    ('controls', Icons.sports_esports, AppColors.sky),
    ('goal', Icons.emoji_events, Color(0xFFFFCA28)),
    ('haze', Icons.cloud, Color(0xFFBF7A3A)),
    ('trees', Icons.park, AppColors.leaf),
    ('loot', Icons.backpack, Color(0xFFBA68C8)),
    ('blocks', Icons.grid_view_rounded, Color(0xFF8D6E63)),
    ('craft', Icons.handyman, Color(0xFFFFB74D)),
    ('camera', Icons.threesixty, Color(0xFF4DD0E1)),
    ('rewards', Icons.military_tech, Color(0xFFFF7043)),
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final r = Responsive.of(context);
    final columns = r.size.width > 900 ? 3 : 2;
    return Scaffold(
      body: HazeBackground(
        child: Padding(
          padding: EdgeInsets.all(r.compact ? 8 : 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back)),
                  Flexible(
                    child: Text(
                      s('how_to_play'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = (c.maxWidth - 10 * (columns - 1)) / columns;
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final (id, icon, color) in sections)
                            SizedBox(
                              width: w,
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(icon, color: color),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              s('guide_${id}_title'),
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(s('guide_$id'), style: const TextStyle(fontSize: 13, height: 1.35)),
                                    ],
                                  ),
                                ),
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
