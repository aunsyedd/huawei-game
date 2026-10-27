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
import '../../game/ui/build_bar.dart';
import '../../game/ui/drop_overlay.dart';
import '../../game/ui/hud.dart';
import '../../game/ui/joystick.dart';
import '../../services/audio_service.dart';
import '../../services/feedback_service.dart';
import '../../state/providers.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key, this.mode = GameMode.royale});

  /// Royale match or the Blok Craft sandbox.
  final GameMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: config.when(
        data: (c) => _Match(config: c, mode: mode),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

class _Match extends ConsumerStatefulWidget {
  const _Match({required this.config, required this.mode});
  final GameConfig config;
  final GameMode mode;

  @override
  ConsumerState<_Match> createState() => _MatchState();
}

class _MatchState extends ConsumerState<_Match> {
  late final HazeRoyaleGame game;
  final _focus = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};
  PlayerResult? _result;
  bool _spectating = false;
  bool _stickPush = false;
  int _tutorialStep = -1;
  Timer? _tutorialTimer;

  static const _tutorialRoyale = ['tut_move', 'tut_aim', 'tut_loot', 'tut_haze', 'tut_plant', 'tut_build'];
  static const _tutorialCraft = ['tut_move', 'tut_camera', 'tut_build', 'tut_craft', 'tut_plant'];

  List<String> get _tutorial => widget.mode == GameMode.craft ? _tutorialCraft : _tutorialRoyale;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final account = ref.read(accountProvider);
    game = HazeRoyaleGame(
      config: widget.config,
      lang: settings.language,
      feedback: FeedbackService(hapticsEnabled: settings.haptics, audio: ref.read(audioServiceProvider)),
      aimSensitivity: settings.sensitivity,
      playerSkin: ref.read(progressProvider).skin,
      playerName: account?.displayName ?? (settings.language == 'ms' ? 'Anda' : 'You'),
      mode: widget.mode,
      graphics: settings.graphics,
      cameraFollow: settings.cameraFollow,
      cameraTilt: settings.cameraTilt,
    );
    game.buildMode = widget.mode == GameMode.craft;
    game.onPlayerFinishedCallback = _onPlayerFinished;
    game.phase.addListener(_onPhase);
    _audio = ref.read(audioServiceProvider)..music('music_match');
  }

  late final AudioService _audio;

  @override
  void dispose() {
    game.phase.removeListener(_onPhase);
    _tutorialTimer?.cancel();
    _focus.dispose();
    _audio.music('music_menu');
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
    _audio
      ..music(null)
      ..sfx(r.won ? 'win' : 'lose');
    final summary = await ref.read(profileProvider.notifier).recordMatch(r, widget.config);
    ref.read(lastMatchProvider.notifier).set(summary);
  }

  void _onDrop(Offset world) {
    _audio.sfx('ui_click');
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
      if (k == LogicalKeyboardKey.keyB) setState(() => game.buildMode = !game.buildMode);
      if (k == LogicalKeyboardKey.keyV || k == LogicalKeyboardKey.space) game.placeBlock();
      if (k == LogicalKeyboardKey.keyX) game.mineHeld = true;
      if (k == LogicalKeyboardKey.keyC) _openCraft();
      if (k == LogicalKeyboardKey.keyZ) game.recentreCamera();
      if (k == LogicalKeyboardKey.comma) game.cycleBlock(-1);
      if (k == LogicalKeyboardKey.period) game.cycleBlock(1);
    } else if (e is KeyUpEvent) {
      _keys.remove(e.logicalKey);
      if (e.logicalKey == LogicalKeyboardKey.keyF && sim.player.action == ActorAction.planting) {
        sim.player.cancelAction();
      }
      if (e.logicalKey == LogicalKeyboardKey.keyX) {
        game.mineHeld = false;
        sim.player.wantMine = false;
      }
    }
    // Arrow keys orbit the camera.
    var oy = 0.0, ox = 0.0;
    if (_keys.contains(LogicalKeyboardKey.arrowLeft)) ox -= 6;
    if (_keys.contains(LogicalKeyboardKey.arrowRight)) ox += 6;
    if (_keys.contains(LogicalKeyboardKey.arrowUp)) oy -= 4;
    if (_keys.contains(LogicalKeyboardKey.arrowDown)) oy += 4;
    if (ox != 0 || oy != 0) game.orbitCamera(ox, oy);
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

  void _openCraft() {
    showDialog<void>(context: context, builder: (ctx) => CraftSheet(game: game));
  }

  void _pause() {
    final s = S.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s(widget.mode == GameMode.craft ? 'leave_craft' : 'quit_confirm')),
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
                      final push = v.distance > 0.55;
                      if (game.buildMode) {
                        if (push && !_stickPush) game.placeBlock();
                        _stickPush = push;
                      } else {
                        game.fireHeld = push;
                      }
                    },
                  ),
                ),
                Positioned(
                  right: safe.right + stickBox + 6 * k,
                  bottom: safe.bottom,
                  child: ValueListenableBuilder<int>(
                    valueListenable: game.hudTick,
                    builder: (context, _, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BuildButtons(game: game, size: buttonSize, onCraft: _openCraft),
                        SizedBox(height: buttonSize * 0.18),
                        ActionButtons(game: game, size: buttonSize, minimal: game.buildMode),
                      ],
                    ),
                  ),
                ),
                // Camera orbit pad, just above the aim stick.
                Positioned(
                  right: safe.right + stickBox * 0.22,
                  bottom: safe.bottom + stickBox + 4 * k,
                  child: LookPad(game: game, size: (buttonSize * 0.95).clamp(34.0, 56.0)),
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
