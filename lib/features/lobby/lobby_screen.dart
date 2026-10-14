import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../state/providers.dart';

/// Short "matchmaking" moment: bots trickle into the lobby, then the match starts.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  int _joined = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 110), (t) {
      final total = (ref.read(gameConfigProvider).value?.bots.count ?? 24) + 1;
      if (_joined >= total) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) context.go('/game');
        });
      } else {
        setState(() => _joined++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final config = ref.watch(gameConfigProvider).value;
    final names = config?.bots.names ?? const [];
    final total = (config?.bots.count ?? 24) + 1;
    final me = ref.watch(accountProvider)?.displayName ?? (s.lang == 'ms' ? 'Anda' : 'You');
    final full = _joined >= total;
    final r = Responsive.of(context);

    return Scaffold(
      body: HazeBackground(
        child: Padding(
          padding: EdgeInsets.all(r.compact ? 10 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back)),
                  Expanded(
                    child: Text(
                      full ? s('lobby_ready') : s('lobby_title'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: r.compact ? 20 : 26, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    s('players_joined', {'n': _joined, 'total': total}),
                    style: const TextStyle(fontSize: 18, color: Color(0xFFFFCC80)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _joined / total, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              SizedBox(height: r.compact ? 8 : 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: r.compact ? 6 : 8,
                    runSpacing: r.compact ? 4 : 8,
                    children: [
                      for (var i = 0; i < _joined; i++)
                        TweenAnimationBuilder<double>(
                          key: ValueKey(i),
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 250),
                          builder: (context, v, child) => Opacity(
                            opacity: v,
                            child: Transform.scale(scale: 0.8 + v * 0.2, child: child),
                          ),
                          child: Chip(
                            avatar: CircleAvatar(
                              backgroundColor: i == 0 ? AppColors.sky : Colors.primaries[i % Colors.primaries.length],
                              child: Text(
                                i == 0 ? '★' : (names.isEmpty ? '?' : names[(i - 1) % names.length][0]),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                            label: Text(i == 0 ? me : (names.isEmpty ? 'Bot $i' : names[(i - 1) % names.length])),
                            visualDensity: r.compact ? VisualDensity.compact : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: config == null ? null : () => context.go('/game'),
                  icon: const Icon(Icons.paragliding),
                  label: Text(s('start_match')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
