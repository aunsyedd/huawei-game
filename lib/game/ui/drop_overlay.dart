import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/l10n/strings.dart';
import '../../app/responsive.dart';
import '../systems/match_manager.dart';
import 'minimap.dart';

/// Drop phase: the player taps the island to choose a landing spot before the
/// countdown runs out (a random spot is used if they don't).
class DropOverlay extends StatefulWidget {
  const DropOverlay({super.key, required this.sim, required this.seconds, required this.onDrop});

  final MatchSimulation sim;
  final double seconds;
  final void Function(Offset world) onDrop;

  @override
  State<DropOverlay> createState() => _DropOverlayState();
}

class _DropOverlayState extends State<DropOverlay> {
  Offset? _landing;
  late int _left = widget.seconds.ceil();
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _left--);
      if (_left <= 0) _drop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _drop() {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    final map = widget.sim.map;
    final l =
        _landing ??
        Offset(
          map.width * (0.2 + math.Random().nextDouble() * 0.6),
          map.height * (0.2 + math.Random().nextDouble() * 0.6),
        );
    widget.onDrop(l);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final map = widget.sim.map;
    final landing = _landing;
    final r = Responsive.of(context);
    final k = r.scale;
    return ColoredBox(
      color: const Color(0xEE0D1B2A),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(r.compact ? 8 : 12),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: r.size.width * 0.6),
                child: AspectRatio(
                  aspectRatio: map.width / map.height,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final scale = c.maxWidth / map.width;
                      return GestureDetector(
                        onTapDown: (d) => setState(() => _landing = d.localPosition / scale),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CustomPaint(
                            size: Size(c.maxWidth, c.maxHeight),
                            painter: MinimapPainter(widget.sim, landing: landing),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(width: 16 * k),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s('choose_landing'),
                              style: TextStyle(color: Colors.white, fontSize: 20 * k, fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 10 * k),
                            if (landing != null)
                              Text(
                                s('area_${map.areaAt(landing.dx, landing.dy)}'),
                                style: TextStyle(color: const Color(0xFF81C784), fontSize: 18 * k),
                              ),
                            SizedBox(height: 12 * k),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final a in const ['forest', 'plantation', 'kampung', 'town', 'beach'])
                                  Chip(
                                    label: Text(s('area_$a'), style: TextStyle(fontSize: 13 * k)),
                                    avatar: CircleAvatar(backgroundColor: MinimapPainter.areaColors[a]),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 6 * k),
                    Text(
                      s('landing_in', {'n': math.max(0, _left)}),
                      style: TextStyle(color: Colors.white70, fontSize: 16 * k),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _drop,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 22 * k, vertical: 12 * k),
                        textStyle: TextStyle(fontSize: 16 * k, fontWeight: FontWeight.w700),
                      ),
                      icon: Icon(Icons.paragliding, size: 22 * k),
                      label: Text(s('drop_now')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
