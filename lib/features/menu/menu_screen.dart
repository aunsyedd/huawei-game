import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../services/hms/air_quality_service.dart';
import '../../state/providers.dart';
import 'progress_card.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<AirAlert>? _alerts;
  AirAlert? _alert;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _alerts = ref.read(hmsServicesProvider).push.alerts.listen((a) {
      if (mounted) setState(() => _alert = a);
    });
    // Warm up config loading so the lobby opens instantly.
    ref.read(audioServiceProvider).music('music_menu');
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpen());
  }

  /// First launch shows the story; every new day grants the login bonus.
  Future<void> _onOpen() async {
    if (!ref.read(settingsProvider).storySeen) {
      if (mounted) context.go('/story');
      return;
    }
    final cfg = await ref.read(gameConfigProvider.future);
    if (!mounted) return;
    final bonus = ref.read(progressProvider.notifier).login(cfg);
    if (bonus > 0 && mounted) {
      final s = S.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s('daily_bonus', {'xp': bonus, 'n': ref.read(progressProvider).streak})),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _alerts?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = ref.watch(settingsProvider);
    final account = ref.watch(accountProvider);
    final stats = ref.watch(profileProvider);
    final hms = ref.read(hmsServicesProvider).hmsAvailable;
    final alert = _alert;
    final r = Responsive.of(context);
    final titleSize = r.compact ? 34.0 : 46.0 * r.scale.clamp(0.9, 1.3);

    return Scaffold(
      body: HazeBackground(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: r.compact ? 14 : 24, vertical: r.compact ? 6 : 12),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: CenteredScroll(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(Icons.park, color: AppColors.leaf, size: titleSize * 0.95),
                            const SizedBox(width: 10),
                            Text(
                              s('app_title'),
                              style: TextStyle(
                                fontSize: titleSize,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        s('tagline'),
                        style: TextStyle(fontSize: r.compact ? 15 : 18, color: const Color(0xFFFFCC80)),
                      ),
                      SizedBox(height: r.compact ? 14 : 28),
                      ScaleTransition(
                        scale: Tween(
                          begin: 1.0,
                          end: 1.05,
                        ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                        child: FilledButton.icon(
                          onPressed: () {
                            ref.read(audioServiceProvider).sfx('ui_click');
                            context.go('/lobby');
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 30),
                          label: Text(s('play'), style: const TextStyle(fontSize: 22)),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 40, vertical: r.compact ? 12 : 18),
                          ),
                        ),
                      ),
                      SizedBox(height: r.compact ? 8 : 12),
                      FilledButton.icon(
                        onPressed: () {
                          ref.read(audioServiceProvider).sfx('ui_click');
                          context.go('/craft');
                        },
                        icon: const Icon(Icons.grid_view_rounded, size: 22),
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s('blok_craft'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                            if (!r.compact)
                              Text(s('blok_craft_sub'), style: const TextStyle(fontSize: 11, height: 1.1)),
                          ],
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6D4C41),
                          padding: EdgeInsets.symmetric(horizontal: 22, vertical: r.compact ? 8 : 12),
                        ),
                      ),
                      SizedBox(height: r.compact ? 8 : 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => context.go('/leaderboard'),
                            icon: const Icon(Icons.leaderboard),
                            label: Text(s('leaderboard')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/settings'),
                            icon: const Icon(Icons.settings),
                            label: Text(s('settings')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/guide'),
                            icon: const Icon(Icons.help_outline),
                            label: Text(s('how_to_play')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/story'),
                            icon: const Icon(Icons.auto_stories),
                            label: Text(s('story')),
                          ),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'en', label: Text('EN')),
                              ButtonSegment(value: 'ms', label: Text('BM')),
                            ],
                            selected: {settings.language},
                            onSelectionChanged: (v) => ref.read(settingsProvider.notifier).setLanguage(v.first),
                            showSelectedIcon: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: r.compact ? 8 : 16),
              Expanded(
                flex: 3,
                child: CenteredScroll(
                  child: Column(
                    children: [
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(r.compact ? 10 : 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppColors.sky,
                                    child: Icon(
                                      account == null ? Icons.person_outline : Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      account == null ? s('guest') : s('signed_in_as', {'name': account.displayName}),
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: r.compact ? 0 : 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => account == null
                                      ? ref.read(accountProvider.notifier).signIn()
                                      : ref.read(accountProvider.notifier).signOut(),
                                  child: Text(account == null ? s('sign_in') : s('sign_out')),
                                ),
                              ),
                              const Divider(),
                              ProgressCard(compact: r.compact),
                              const Divider(),
                              _stat(s('wins'), stats.wins),
                              _stat(s('best_score'), stats.bestScore),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(hms ? Icons.cloud_done : Icons.cloud_off, size: 14, color: Colors.white54),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      hms ? s('hms_on') : s('hms_off'),
                                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (alert != null)
                        Card(
                          color: const Color(0xFF6D3B12),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.warning_amber, color: Colors.amber),
                            title: Text(s('air_alert')),
                            subtitle: Text(alert.text(settings.language)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _alert = null),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
