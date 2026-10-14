import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'actor.dart';
import 'loot.dart';

enum BotState { wander, loot, fight, flee, retreat }

/// Per-bot memory and skill. The decision logic lives in `systems/bot_ai.dart`.
class BotBrain {
  BotBrain({
    required this.aimError,
    required this.reaction,
    required this.aggression,
    required this.phase,
    required this.caution,
  });

  /// Random skill, drawn from bots.json ranges.
  factory BotBrain.random(math.Random rng, List<double> aimDeg, List<double> reaction, List<double> aggression) {
    double between(List<double> r) => r[0] + rng.nextDouble() * (r[1] - r[0]);
    return BotBrain(
      aimError: between(aimDeg) * math.pi / 180,
      reaction: between(reaction),
      aggression: between(aggression),
      phase: rng.nextDouble() * 10,
      caution: rng.nextDouble() * 12,
    );
  }

  final double aimError, reaction, aggression, phase, caution;

  BotState state = BotState.wander;
  double thinkTimer = 0;

  Actor? target;
  bool targetVisible = false;
  double acquiredAt = 0, lastEnemySeen = -99;

  final Vector2 dest = Vector2.zero();
  bool hasDest = false;
  LootItem? lootTarget;

  double strafeDir = 1, strafeTimer = 0;

  // Stuck detection.
  final Vector2 lastCheckPos = Vector2.zero();
  double stuckCheck = 1, unstuckTimer = 0, unstuckAngle = 0;
  int avoidSide = 1;

  /// For tests: how long the bot has made no progress.
  double stuckSeconds = 0;
}
