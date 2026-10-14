import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../data/game_config.dart';
import '../../game/components/actor.dart';
import '../../game/haze_royale_game.dart';
import '../../game/systems/match_manager.dart';
import '../../game/ui/drop_overlay.dart';
import '../../game/ui/hud.dart';
import '../../game/ui/joystick.dart';
import '../../services/feedback_service.dart';
import '../../state/providers.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: config.when(
        data: (c) => _Match(config: c),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

class _Match extends ConsumerStatefulWidget {
  const _Match({required this.config});
  final GameConfig config;

  @override
  ConsumerState<_Match> createState() => _MatchState();
}

class _MatchState extends ConsumerState<_Match> {
  late final HazeRoyaleGame game;
  final _focus = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};
  PlayerResult? _result;
  bool _spectating = false;
  int _tutorialStep = -1;
  Timer? _tutorialTimer;

  static const _tutorial = ['tut_move', 'tut_aim', 'tut_loot', 'tut_haze', 'tut_plant'];

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final account = ref.read(accountProvider);
    game = HazeRoyaleGame(
      config: widget.config,
      lang: settings.language,
      feedback: FeedbackService(hapticsEnabled: settings.haptics, soundVolume: settings.soundVolume),
      aimSensitivity: settings.sensitivity,
      playerName: account?.displayName ?? (settings.language == 'ms' ? 'Anda' : 'You'),
    );
    game.onPlayerFinishedCallback = _onPlayerFinished;
    game.phase.addListener(_onPhase);
  }

  @override
  void dispose() {
    game.phase.removeListener(_onPhase);
    _tutorialTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onPhase() {
    if (!mounted) return;
    setState(() {});
    if (game.phase.value == MatchPhase.running && !ref.read(settingsProvider).tutorialDone && _tutorialStep < 0) {
      _advanceTutorial();
    }
  }

  void _advanceTutorial() {
    _tutorialTimer?.cancel();
    setState(() => _tutorialStep++);
    if (_tutorialStep >= _tutorial.length) {
      ref.read(settingsProvider.notifier).setTutorialDone(true);
      return;
    }
    _tutorialTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) _advanceTutorial();
    });
  }

  Future<void> _onPlayerFinished(PlayerResult r) async {
    setState(() => _result = r);
    final summary = await ref.read(profileProvider.notifier).recordMatch(r, widget.config);
    ref.read(lastMatchProvider.notifier).set(summary);
  }

  void _onDrop(Offset world) {
    game.startMatch(world.dx, world.dy);
    _focus.requestFocus();
  }

  // ---------------- keyboard + mouse (desktop / web testing) ----------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final sim = game.sim;
    if (e is KeyDownEvent) {
      _keys.add(e.logicalKey);
      final k = e.logicalKey;
      if (k == LogicalKeyboardKey.keyR) sim.reload();
      if (k == LogicalKeyboardKey.keyQ) sim.swapWeapon();
      if (k == LogicalKeyboardKey.keyE) sim.pickupNearbyWeapon();
      if (k == LogicalKeyboardKey.digit1) sim.startAction(sim.player, ActorAction.healing);
      if (k == LogicalKeyboardKey.digit2) sim.startAction(sim.player, ActorAction.masking);
      if (k == LogicalKeyboardKey.keyF) sim.startAction(sim.player, ActorAction.planting);
    } else if (e is KeyUpEvent) {
      _keys.remove(e.logicalKey);
      if (e.logicalKey == LogicalKeyboardKey.keyF && sim.player.action == ActorAction.planting) {
        sim.player.cancelAction();
      }
    }
    var x = 0.0, y = 0.0;
    if (_keys.contains(LogicalKeyboardKey.keyA)) x -= 1;
    if (_keys.contains(LogicalKeyboardKey.keyD)) x += 1;
    if (_keys.contains(LogicalKeyboardKey.keyW)) y -= 1;
    if (_keys.contains(LogicalKeyboardKey.keyS)) y += 1;
    final len = math.sqrt(x * x + y * y);
    game.moveInput.setValues(len > 0 ? x / len : 0, len > 0 ? y / len : 0);
    return KeyEventResult.handled;
  }

  void _mouseAim(PointerEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    final w = game.screenToWorld(e.localPosition.dx, e.localPosition.dy);
    final p = game.sim.player.pos;
    final v = Vector2(w.x - p.x, w.y - p.y);
    if (v.length2 > 1) game.aimInput.setFrom(v.normalized() * 0.2);
  }

  // ---------------- UI ----------------

  void _pause() {
    final s = S.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s('quit_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s('cancel'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/');
            },
            child: Text(s('quit')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = ref.watch(settingsProvider);
    final dropping = game.phase.value == MatchPhase.dropping;
    final result = _result;
    final r = Responsive.of(context);
    final size = r.size;
    final safe = r.safe;
    final k = r.scale;
    final stick = (r.shortest * 0.15).clamp(42.0, 84.0);
    final stickBox = stick * 2.6;
    final buttonSize = (r.shortest * 0.115).clamp(36.0, 62.0);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerHover: _mouseAim,
        onPointerMove: _mouseAim,
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.mouse && e.buttons == kPrimaryMouseButton) {
            _mouseAim(e);
            game.fireHeld = true;
          }
        },
        onPointerUp: (e) {
          if (e.kind == PointerDeviceKind.mouse) game.fireHeld = false;
        },
        child: Stack(
          children: [
            Positioned.fill(child: GameWidget(game: game)),
            if (dropping)
              Positioned.fill(
                child: DropOverlay(sim: game.sim, seconds: widget.config.zone.dropTime, onDrop: _onDrop),
              )
            else ...[
              if (result == null) ...[
                // Left half: floating move stick.
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: size.width * 0.42,
                  height: size.height * 0.72,
                  child: Joystick(
                    floating: true,
                    radius: stick,
                    onChanged: (v) => game.moveInput.setValues(v.dx, v.dy),
                  ),
                ),
                // Bottom right: aim + fire stick.
                Positioned(
                  right: safe.right,
                  bottom: safe.bottom,
                  width: stickBox,
                  height: stickBox,
                  child: Joystick(
                    radius: stick,
                    fireThreshold: 0.55,
                    onChanged: (v) {
                      final a = Offset(v.dx, v.dy) * settings.sensitivity;
                      game.aimInput.setValues(a.dx, a.dy);
                      game.fireHeld = v.distance > 0.55;
                    },
                  ),
                ),
                Positioned(
                  right: safe.right + stickBox + 6 * k,
                  bottom: safe.bottom,
                  child: ActionButtons(game: game, size: buttonSize),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: safe.bottom + 74 * k,
                  child: Center(child: PickupButton(game: game)),
                ),
              ],
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: Hud(game: game, showFps: settings.showFps, onPause: _pause),
                ),
              ),
              if (_tutorialStep >= 0 && _tutorialStep < _tutorial.length && result == null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: size.height * 0.36,
                  child: Center(
                    child: _TutorialCard(
                      text: s(_tutorial[_tutorialStep]),
                      button: s('ok'),
                      onTap: _advanceTutorial,
                      maxWidth: (size.width * 0.55).clamp(260.0, 460.0),
                    ),
                  ),
                ),
              if (result != null && !_spectating) Positioned.fill(child: _endOverlay(s, result, k)),
              if (result != null && _spectating)
                Positioned(
                  left: safe.left,
                  right: safe.right,
                  bottom: safe.bottom,
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: () => context.go('/results'),
                      icon: const Icon(Icons.emoji_events),
                      label: Text('${s('spectating', {'name': game.sim.focus.name})} · ${s('see_results')}'),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _endOverlay(S s, PlayerResult r, double k) {
    return ColoredBox(
      color: const Color(0xAA000000),
      child: CenteredScroll(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              r.won ? Icons.emoji_events : Icons.water_drop,
              size: 56 * k,
              color: r.won ? Colors.amber : Colors.lightBlueAccent,
            ),
            const SizedBox(height: 8),
            Text(
              r.won ? s('you_win') : s('you_out'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 32 * k, fontWeight: FontWeight.w900),
            ),
            Text(
              s('placement_of', {'p': r.placement, 'n': r.totalPlayers}),
              style: TextStyle(color: Colors.white70, fontSize: 20 * k),
            ),
            SizedBox(height: 16 * k),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (!r.won && game.sim.phase == MatchPhase.running)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => setState(() => _spectating = true),
                    icon: const Icon(Icons.visibility),
                    label: Text(s('spectate')),
                  ),
                FilledButton.icon(
                  onPressed: () => context.go('/results'),
                  icon: const Icon(Icons.emoji_events),
                  label: Text(s('see_results')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({required this.text, required this.button, required this.onTap, required this.maxWidth});
  final String text, button;
  final VoidCallback onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xE61B5E20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white54),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lightbulb, color: Colors.amber),
          const SizedBox(width: 10),
          Flexible(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(button, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
