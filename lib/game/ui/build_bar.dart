import 'package:flutter/material.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../../data/game_config.dart';
import '../components/actor.dart';
import '../haze_royale_game.dart';

/// A little isometric cube in a block's own colours, used for hotbar slots
/// and crafting rows.
class BlockIcon extends StatelessWidget {
  const BlockIcon({super.key, required this.type, this.size = 26});
  final BlockType type;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _CubePainter(type));
}

class _CubePainter extends CustomPainter {
  _CubePainter(this.type);
  final BlockType type;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width / 2, size.height / 2);
    final s = size.width * 0.34;
    Path face(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final q in pts.skip(1)) {
        p.lineTo(q.dx, q.dy);
      }
      return p..close();
    }

    final alpha = type.alpha;
    Paint fill(Color c, double shade) => Paint()
      ..color = Color.lerp(c, const Color(0xFF000000), shade)!.withValues(alpha: alpha)
      ..isAntiAlias = true;

    canvas.drawPath(
      face([o.translate(0, -s), o.translate(s, -s * 0.5), o, o.translate(-s, -s * 0.5)]),
      fill(type.top, 0),
    );
    canvas.drawPath(
      face([o.translate(-s, -s * 0.5), o, o.translate(0, s), o.translate(-s, s * 0.5)]),
      fill(type.side, 0.12),
    );
    canvas.drawPath(
      face([o.translate(s, -s * 0.5), o, o.translate(0, s), o.translate(s, s * 0.5)]),
      fill(type.side, 0.3),
    );
  }

  @override
  bool shouldRepaint(_CubePainter old) => old.type != type;
}

/// Minecraft-style hotbar: every block type the player carries, tap to select.
class BlockHotbar extends StatelessWidget {
  const BlockHotbar({super.key, required this.game, required this.slot});
  final HazeRoyaleGame game;
  final double slot;

  @override
  Widget build(BuildContext context) {
    final sim = game.sim;
    final p = sim.player;
    final bar = sim.hotbar(p);
    if (bar.isEmpty) return const SizedBox.shrink();
    final types = game.config.blocks.types;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in bar.take(9))
          GestureDetector(
            onTap: () => game.selectBlock(t),
            child: Container(
              width: slot,
              height: slot,
              margin: EdgeInsets.symmetric(horizontal: slot * 0.04),
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                border: Border.all(color: p.selected == t ? Colors.white : Colors.white24, width: 2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  BlockIcon(type: types[t], size: slot * 0.78),
                  Positioned(
                    right: 2,
                    bottom: 0,
                    child: Text(
                      '${p.carried(t)}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: slot * 0.28,
                        fontWeight: FontWeight.w800,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Buttons for building: toggle build mode, hold to mine, place, craft.
class BuildButtons extends StatelessWidget {
  const BuildButtons({super.key, required this.game, required this.size, required this.onCraft});
  final HazeRoyaleGame game;
  final double size;
  final VoidCallback onCraft;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudTick,
      builder: (context, _, _) {
        final p = game.sim.player;
        if (!p.alive) return const SizedBox.shrink();
        final gap = SizedBox(height: size * 0.16);
        final building = game.buildMode;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Btn(
              icon: Icons.grid_view_rounded,
              size: size,
              color: building ? const Color(0xFFFFD54F) : Colors.white70,
              filled: building,
              onTap: () => game.buildMode = !game.buildMode,
            ),
            // Mining, building and crafting replace the combat buttons while
            // build mode is on, so the column never gets taller.
            if (building) ...[
              gap,
              _HoldBtn(game: game, size: size * 1.12),
              gap,
              _Btn(
                icon: Icons.add_box,
                size: size,
                color: const Color(0xFF9CCC65),
                enabled: p.carried(p.selected) > 0,
                onTap: game.placeBlock,
              ),
              gap,
              _Btn(icon: Icons.handyman, size: size, color: const Color(0xFFFFB74D), onTap: onCraft),
            ],
          ],
        );
      },
    );
  }
}

/// Hold to keep mining the block in front of you.
class _HoldBtn extends StatefulWidget {
  const _HoldBtn({required this.game, required this.size});
  final HazeRoyaleGame game;
  final double size;

  @override
  State<_HoldBtn> createState() => _HoldBtnState();
}

class _HoldBtnState extends State<_HoldBtn> {
  bool _down = false;

  void _set(bool v) {
    widget.game.mineHeld = v;
    if (!v) widget.game.sim.player.wantMine = false;
    if (mounted) setState(() => _down = v);
  }

  @override
  void dispose() {
    widget.game.mineHeld = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.game.sim.player;
    final s = widget.size;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _down ? const Color(0xDD6D4C41) : const Color(0x88000000),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD7CCC8), width: 2),
              ),
            ),
            if (p.action == ActorAction.mining)
              Positioned.fill(
                child: CircularProgressIndicator(value: p.actionProgress, strokeWidth: 4, color: Colors.amberAccent),
              ),
            Icon(Icons.construction, color: Colors.white, size: s * 0.5),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.size,
    required this.onTap,
    this.color = Colors.white,
    this.enabled = true,
    this.filled = false,
  });
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color color;
  final bool enabled, filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: 0.3) : const Color(0x88000000),
          shape: BoxShape.circle,
          border: Border.all(color: enabled ? color.withValues(alpha: 0.85) : Colors.white24, width: 2),
        ),
        child: Icon(icon, color: enabled ? color : Colors.white30, size: size * 0.48),
      ),
    );
  }
}

/// Drag to orbit the camera, double tap to snap back behind the player.
class LookPad extends StatelessWidget {
  const LookPad({super.key, required this.game, required this.size});
  final HazeRoyaleGame game;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => game.orbitCamera(d.delta.dx, d.delta.dy),
      onDoubleTap: game.recentreCamera,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38, width: 2),
        ),
        child: Icon(Icons.threesixty, color: Colors.white70, size: size * 0.6),
      ),
    );
  }
}

/// The crafting sheet: every recipe, what it needs and whether you can make it.
class CraftSheet extends StatefulWidget {
  const CraftSheet({super.key, required this.game});
  final HazeRoyaleGame game;

  @override
  State<CraftSheet> createState() => _CraftSheetState();
}

class _CraftSheetState extends State<CraftSheet> {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final game = widget.game;
    final cfg = game.config.blocks;
    final sim = game.sim;
    final p = sim.player;
    final r = Responsive.of(context);
    final k = r.scale;

    String label(BlockRecipe rec) {
      if (rec.item) return (s.lang == 'ms' ? rec.nameMs : rec.nameEn) ?? rec.out;
      return cfg.byId(rec.out)?.name(s.lang) ?? rec.out;
    }

    return Dialog(
      backgroundColor: const Color(0xF21B2430),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: r.size.height * 0.86),
        child: Padding(
          padding: EdgeInsets.all(12 * k),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.handyman, color: Color(0xFFFFB74D)),
                  SizedBox(width: 8 * k),
                  Expanded(
                    child: Text(
                      s('craft_title'),
                      style: TextStyle(fontSize: 18 * k, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cfg.recipes.length,
                  itemBuilder: (context, i) {
                    final rec = cfg.recipes[i];
                    final can = sim.canCraft(p, i);
                    final out = cfg.byId(rec.out);
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 3 * k),
                      child: Row(
                        children: [
                          if (out != null)
                            BlockIcon(type: out, size: 30 * k)
                          else
                            Icon(
                              rec.out == 'seed' ? Icons.eco : Icons.water_drop,
                              color: rec.out == 'seed' ? const Color(0xFF66BB6A) : const Color(0xFF29B6F6),
                              size: 26 * k,
                            ),
                          SizedBox(width: 8 * k),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${label(rec)} x${rec.count}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13 * k,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Wrap(
                                  spacing: 8 * k,
                                  children: [
                                    for (final e in rec.inputs.entries)
                                      Text(
                                        '${cfg.byId(e.key)?.name(s.lang) ?? e.key} ${p.carried(cfg.indexOf[e.key] ?? 0)}/${e.value}',
                                        style: TextStyle(
                                          color: p.carried(cfg.indexOf[e.key] ?? 0) >= e.value
                                              ? Colors.white60
                                              : const Color(0xFFEF9A9A),
                                          fontSize: 11 * k,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: can
                                ? () {
                                    game.craft(i);
                                    setState(() {});
                                  }
                                : null,
                            child: Text(s('make')),
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
