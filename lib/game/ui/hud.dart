import 'package:flutter/material.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../components/actor.dart';
import '../haze_royale_game.dart';
import '../systems/match_manager.dart';
import 'minimap.dart';

/// Heads-up display: rebuilt ~12x per second from [HazeRoyaleGame.hudTick].
/// Everything is sized from the screen's short side and kept inside the
/// notch / rounded-corner safe area.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.game, required this.showFps, required this.onPause});

  final HazeRoyaleGame game;
  final bool showFps;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(valueListenable: game.hudTick, builder: (context, _, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final s = S.of(context);
    final r = Responsive.of(context);
    final k = r.scale;
    final safe = r.safe;
    final sim = game.sim;
    final p = sim.player;
    final lang = s.lang;
    final size = r.size;
    final mapSize = (size.height * 0.32).clamp(88.0, 200.0);
    final slotW = (108 * k).clamp(92.0, 150.0);
    final barW = slotW * 2 + 6;

    return Stack(
      children: [
        // Top-left: pause, alive, tag-outs, haze timer.
        Positioned(
          left: safe.left,
          top: safe.top,
          right: size.width / 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoundButton(icon: Icons.pause, onTap: onPause, size: (38 * k).clamp(34.0, 52.0)),
              SizedBox(width: 6 * k),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6 * k,
                      runSpacing: 4,
                      children: [
                        _chip(Icons.person, '${sim.aliveCount} ${s('alive')}', k),
                        _chip(Icons.water_drop, '${p.tagOuts} ${s('tags')}', k),
                        if (showFps) _chip(Icons.speed, '${game.fps.round()} fps', k),
                      ],
                    ),
                    SizedBox(height: 5 * k),
                    _zoneLabel(s, k),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Top-right: minimap + feed.
        Positioned(
          right: safe.right,
          top: safe.top,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: mapSize,
                height: mapSize,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(painter: MinimapPainter(sim, repaint: game.hudTick)),
                ),
              ),
              SizedBox(height: 4 * k),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size.width * 0.34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final f in sim.feed.reversed.take(r.compact ? 2 : 4))
                      if (sim.time - f.time < 7) _feedLine(f, s, lang, k),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Centre messages.
        Positioned(
          left: 0,
          right: 0,
          top: size.height * 0.24,
          child: Column(
            children: [
              if (p.alive && !sim.isSafeAt(p.pos.x, p.pos.y) && sim.phase == MatchPhase.running)
                _banner(s('in_haze'), const Color(0xCC8D6E3A), k),
              if (p.busy)
                _banner(
                  switch (p.action) {
                    ActorAction.planting => s('planting'),
                    ActorAction.healing => s('healing'),
                    _ => s('masking'),
                  },
                  const Color(0xAA1B5E20),
                  k,
                ),
              if (p.weapon?.reloading ?? false) _banner(s('reloading'), const Color(0xAA37474F), k),
            ],
          ),
        ),

        // Bottom centre: weapons, health, armour.
        if (p.alive)
          Positioned(
            left: 0,
            right: 0,
            bottom: safe.bottom,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (var i = 0; i < 2; i++) _weaponSlot(i, lang, slotW, k)],
                  ),
                  SizedBox(height: 5 * k),
                  _bar(p.armour / 100, const Color(0xFF42A5F5), barW, 6 * k),
                  SizedBox(height: 3 * k),
                  _bar(
                    p.health / p.maxHealth,
                    p.health < 30 ? const Color(0xFFEF5350) : const Color(0xFF66BB6A),
                    barW,
                    12 * k,
                    label: '${p.health.ceil()}',
                    k: k,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _zoneLabel(S s, double k) {
    final z = game.sim.zone;
    final String text;
    if (z.finished) {
      text = s('haze_final');
    } else if (z.shrinking) {
      text = s('haze_closing');
    } else {
      final t = z.timer.ceil();
      text = s('haze_in', {'t': '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}'});
    }
    final urgent = z.shrinking || z.finished || z.timer < 10;
    return _chip(Icons.cloud, text, k, color: urgent ? const Color(0xCCBF5B1E) : const Color(0x99000000));
  }

  Widget _feedLine(FeedEntry f, S s, String lang, double k) {
    final text = f.cause == 'haze' || f.by == null
        ? s('haze_out', {'b': f.victim})
        : '${s('tagged_out_by', {'a': f.by!, 'b': f.victim})} · ${game.config.weapons[f.cause]?.name(lang) ?? ''}';
    return Padding(
      padding: EdgeInsets.only(top: 3 * k),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 3 * k),
        decoration: BoxDecoration(
          color: f.involvesPlayer ? const Color(0xCC0277BD) : const Color(0x88000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontSize: 11 * k),
        ),
      ),
    );
  }

  Widget _weaponSlot(int i, String lang, double width, double k) {
    final p = game.sim.player;
    final w = p.slots[i];
    final active = p.activeSlot == i;
    return GestureDetector(
      onTap: () {
        if (!active) game.sim.swapWeapon();
      },
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 4 * k),
        decoration: BoxDecoration(
          color: active ? const Color(0xCC263238) : const Color(0x77000000),
          border: Border.all(color: active ? (w?.stats.color ?? Colors.white54) : Colors.white24, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: w == null
            ? Text(
                '—',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 14 * k),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.stats.name(lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 11 * k, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    w.reloading ? '…' : '${w.ammo}/${w.stats.magazine}',
                    style: TextStyle(color: w.ammo == 0 ? Colors.redAccent : Colors.white70, fontSize: 12 * k),
                  ),
                ],
              ),
      ),
    );
  }

  static Widget _chip(IconData icon, String text, double k, {Color color = const Color(0x99000000)}) => Container(
    padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 4 * k),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14 * k)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14 * k, color: Colors.white),
        SizedBox(width: 4 * k),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontSize: 12 * k, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  static Widget _banner(String text, Color color, double k) => Padding(
    padding: EdgeInsets.only(bottom: 6 * k),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 6 * k),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16 * k)),
      child: Text(
        text,
        style: TextStyle(color: Colors.white, fontSize: 14 * k, fontWeight: FontWeight.w700),
      ),
    ),
  );

  static Widget _bar(double frac, Color color, double width, double height, {String? label, double k = 1}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: const Color(0x88000000), borderRadius: BorderRadius.circular(height / 2)),
    child: Stack(
      children: [
        FractionallySizedBox(
          widthFactor: frac.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
          ),
        ),
        if (label != null)
          Center(
            child: Text(
              label,
              style: TextStyle(color: Colors.white, fontSize: 9 * k, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    ),
  );
}

/// Column of action buttons beside the aim stick: plant (hold), water, mask, reload.
class ActionButtons extends StatelessWidget {
  const ActionButtons({super.key, required this.game, this.size = 46});
  final HazeRoyaleGame game;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudTick,
      builder: (context, _, _) {
        final sim = game.sim;
        final p = sim.player;
        if (!p.alive) return const SizedBox.shrink();
        final gap = SizedBox(height: size * 0.16);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlantButton(game: game, size: size * 1.25),
            gap,
            _RoundButton(
              icon: Icons.water_drop,
              count: p.water,
              size: size,
              color: const Color(0xFF29B6F6),
              onTap: () => sim.startAction(p, ActorAction.healing),
            ),
            gap,
            _RoundButton(
              icon: Icons.masks,
              count: p.masks,
              size: size,
              color: const Color(0xFFCFD8DC),
              onTap: () => sim.startAction(p, ActorAction.masking),
            ),
            gap,
            _RoundButton(icon: Icons.refresh, size: size, onTap: sim.reload),
          ],
        );
      },
    );
  }
}

/// "Take [weapon]" button shown when standing on a weapon you can swap for.
class PickupButton extends StatelessWidget {
  const PickupButton({super.key, required this.game});
  final HazeRoyaleGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudTick,
      builder: (context, _, _) {
        final s = S.of(context);
        final sim = game.sim;
        final pickup = sim.player.alive ? sim.nearbyWeaponFor(sim.player) : null;
        if (pickup == null) return const SizedBox.shrink();
        final k = Responsive.of(context).scale;
        return FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xDD0277BD),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 8 * k),
            textStyle: TextStyle(fontSize: 14 * k, fontWeight: FontWeight.w700),
          ),
          onPressed: sim.pickupNearbyWeapon,
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: Text(s('pick_up', {'item': game.config.weapons[pickup.refId]!.name(s.lang)})),
        );
      },
    );
  }
}

class _PlantButton extends StatelessWidget {
  const _PlantButton({required this.game, required this.size});
  final HazeRoyaleGame game;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = game.sim.player;
    final enabled = p.seeds > 0;
    final planting = p.action == ActorAction.planting;
    return Listener(
      onPointerDown: (_) => game.sim.startAction(p, ActorAction.planting),
      onPointerUp: (_) {
        if (p.action == ActorAction.planting) p.cancelAction();
      },
      onPointerCancel: (_) {
        if (p.action == ActorAction.planting) p.cancelAction();
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: enabled ? const Color(0xDD2E7D32) : const Color(0x66000000),
                shape: BoxShape.circle,
                border: Border.all(color: enabled ? Colors.white70 : Colors.white24, width: 2),
              ),
            ),
            if (planting)
              Positioned.fill(
                child: CircularProgressIndicator(
                  value: p.actionProgress,
                  strokeWidth: 4,
                  color: Colors.lightGreenAccent,
                ),
              ),
            Icon(Icons.park, color: enabled ? Colors.white : Colors.white30, size: size * 0.5),
            Positioned(
              right: size * 0.12,
              bottom: size * 0.06,
              child: Text(
                '${p.seeds}',
                style: TextStyle(color: Colors.white, fontSize: size * 0.22, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.count, this.color = Colors.white, this.size = 46});
  final IconData icon;
  final VoidCallback onTap;
  final int? count;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final disabled = count != null && count == 0;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x88000000),
          shape: BoxShape.circle,
          border: Border.all(color: disabled ? Colors.white24 : color.withValues(alpha: 0.8), width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: disabled ? Colors.white30 : color, size: size * 0.48),
            if (count != null)
              Positioned(
                right: 4,
                bottom: 2,
                child: Text(
                  '$count',
                  style: TextStyle(color: Colors.white, fontSize: size * 0.24, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
