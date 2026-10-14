import 'dart:math' as math;

import '../../data/game_config.dart';

/// The shrinking safe circle. Outside it is haze.
class ZoneSystem {
  ZoneSystem(this.cfg, this.mapW, this.mapH, this.rng) : cx = mapW / 2, cy = mapH / 2, r = cfg.initialRadius {
    _pickNext();
    timer = cfg.phases.first.warning;
  }

  final ZoneConfig cfg;
  final double mapW, mapH;
  final math.Random rng;

  double cx, cy, r;
  double _fromX = 0, _fromY = 0, _fromR = 0;
  double nextX = 0, nextY = 0, nextR = 0;
  int phaseIndex = 0;
  bool shrinking = false;
  bool finished = false;
  double timer = 0;

  ZonePhase get phase => cfg.phases[math.min(phaseIndex, cfg.phases.length - 1)];

  /// Damage per second outside the safe circle right now.
  double get dps {
    // Before the first shrink the circle covers the whole island anyway.
    if (finished) return cfg.phases.last.dps * 1.5;
    return phase.dps;
  }

  void _pickNext() {
    final p = cfg.phases[phaseIndex];
    final newR = cfg.initialRadius * p.radiusFraction;
    final maxOffset = math.max(0.0, r - newR);
    final a = rng.nextDouble() * math.pi * 2;
    final d = math.sqrt(rng.nextDouble()) * maxOffset;
    var x = cx + math.cos(a) * d, y = cy + math.sin(a) * d;
    // Keep the safe area on the island.
    final inset = math.min(newR, 700.0).clamp(150.0, 700.0);
    x = x.clamp(inset, mapW - inset);
    y = y.clamp(inset, mapH - inset);
    // Make sure the new circle is still inside the current one.
    final dx = x - cx, dy = y - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > maxOffset && dist > 0) {
      x = cx + dx / dist * maxOffset;
      y = cy + dy / dist * maxOffset;
    }
    nextX = x;
    nextY = y;
    nextR = newR;
  }

  void update(double dt) {
    if (finished) return;
    timer -= dt;
    if (!shrinking) {
      if (timer <= 0) {
        shrinking = true;
        timer = phase.shrink;
        _fromX = cx;
        _fromY = cy;
        _fromR = r;
      }
      return;
    }
    final t = (1 - timer / phase.shrink).clamp(0.0, 1.0);
    cx = _fromX + (nextX - _fromX) * t;
    cy = _fromY + (nextY - _fromY) * t;
    r = _fromR + (nextR - _fromR) * t;
    if (timer <= 0) {
      cx = nextX;
      cy = nextY;
      r = nextR;
      phaseIndex++;
      shrinking = false;
      if (phaseIndex >= cfg.phases.length) {
        finished = true;
        timer = 0;
      } else {
        _pickNext();
        timer = phase.warning;
      }
    }
  }

  bool isSafe(double x, double y) {
    final dx = x - cx, dy = y - cy;
    return dx * dx + dy * dy <= r * r;
  }

  /// Will (x, y) still be safe after the next shrink?
  bool isSafeNext(double x, double y, {double margin = 0}) {
    final dx = x - nextX, dy = y - nextY;
    final rr = math.max(0.0, nextR - margin);
    return dx * dx + dy * dy <= rr * rr;
  }
}
