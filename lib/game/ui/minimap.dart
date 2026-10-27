import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../systems/match_manager.dart';
import '../world/block_world.dart';

/// Island overview: areas, buildings, haze circles, trees and the player.
/// Also used full-screen for picking a landing spot.
class MinimapPainter extends CustomPainter {
  MinimapPainter(this.sim, {super.repaint, this.landing, this.showActors = false});

  final MatchSimulation sim;
  final Offset? landing;
  final bool showActors;

  static const areaColors = {
    'forest': Color(0xFF3E7D3A),
    'plantation': Color(0xFF7BAF4A),
    'kampung': Color(0xFF9CCB65),
    'town': Color(0xFFB8BEC2),
    'beach': Color(0xFFEBD9A4),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final map = sim.map;
    final s = math.min(size.width / map.width, size.height / map.height);
    canvas.save();
    canvas.scale(s);
    final p = Paint();
    p.color = const Color(0xFF2D7FB8);
    canvas.drawRect(Rect.fromLTWH(0, 0, map.width, map.height), p);
    for (final a in map.config.areas) {
      p.color = areaColors[a.type]!;
      canvas.drawRect(a.rect, p);
    }
    for (final d in map.decor) {
      if (d.kind != 'road') continue;
      p.color = const Color(0xFF5F6A70);
      canvas.drawRect(d.rect, p);
    }
    for (final b in map.buildings) {
      p.color = b.roofColor;
      canvas.drawRect(b.rect, p);
    }

    final stroke = Paint()..style = PaintingStyle.stroke;
    if (sim.phase != MatchPhase.dropping) {
      final z = sim.zone;
      // Haze outside the circle.
      final haze = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Rect.fromLTWH(0, 0, map.width, map.height))
        ..addOval(Rect.fromCircle(center: Offset(z.cx, z.cy), radius: math.max(0, z.r)));
      p.color = const Color(0x88A8784A);
      canvas.drawPath(haze, p);
      if (!z.finished) {
        stroke
          ..color = Colors.white
          ..strokeWidth = 2 / s;
        canvas.drawCircle(Offset(z.nextX, z.nextY), z.nextR, stroke);
      }
      stroke
        ..color = const Color(0xFFFF8A3D)
        ..strokeWidth = 2.5 / s;
      canvas.drawCircle(Offset(z.cx, z.cy), z.r, stroke);

      // Block columns, in their own colour, so you can see what you built.
      final blocks = sim.blocks;
      final bs = blocks.size;
      for (final e in blocks.heights.entries) {
        final bx = BlockWorld.keyX(e.key), by = BlockWorld.keyY(e.key);
        final t = blocks.top(bx, by);
        if (t == null) continue;
        p.color = t.top;
        canvas.drawRect(Rect.fromLTWH(bx * bs, by * bs, bs, bs), p);
      }

      p.color = const Color(0xFF43A047);
      for (final t in sim.trees) {
        if (t.alive) canvas.drawCircle(Offset(t.x, t.y), math.max(25, t.bubble), p);
      }
      if (showActors) {
        p.color = Colors.redAccent;
        for (final a in sim.actors) {
          if (a.alive && !a.isPlayer) canvas.drawCircle(Offset(a.pos.x, a.pos.y), 20, p);
        }
      }
      final pl = sim.focus;
      p.color = Colors.white;
      canvas.drawCircle(Offset(pl.pos.x, pl.pos.y), 4.5 / s, p);
      p.color = const Color(0xFF29B6F6);
      canvas.drawCircle(Offset(pl.pos.x, pl.pos.y), 3 / s, p);
    }

    final l = landing;
    if (l != null) {
      stroke
        ..color = Colors.white
        ..strokeWidth = 3 / s;
      canvas.drawCircle(l, 60, stroke);
      p.color = const Color(0xFF29B6F6);
      canvas.drawCircle(l, 7 / s, p);
    }
    stroke
      ..color = Colors.black54
      ..strokeWidth = 2 / s;
    canvas.drawRect(Rect.fromLTWH(0, 0, map.width, map.height), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MinimapPainter old) => old.landing != landing;
}
