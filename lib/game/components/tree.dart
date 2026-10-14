import '../../data/game_config.dart';
import 'actor.dart';

/// A planted tree. Each growth stage enlarges its clean-air bubble.
class Tree {
  Tree(this.x, this.y, this.planter, TreeConfig cfg) : health = cfg.health[0], maxHealth = cfg.health[0];

  final double x, y;
  final Actor? planter;
  double age = 0;
  int stage = 0;
  double health, maxHealth;
  double bubble = 0;
  bool alive = true;
  double hitFlash = 0;

  /// [witherRate] > 0 once the last haze phase is over: bubbles shrink so the
  /// match always ends.
  void update(double dt, TreeConfig cfg, {double witherRate = 0}) {
    age += dt;
    hitFlash = (hitFlash - dt).clamp(0, 1);
    while (stage < cfg.stageTimes.length - 1 && age >= cfg.stageTimes[stage + 1]) {
      stage++;
      final ratio = health / maxHealth;
      maxHealth = cfg.health[stage];
      health = maxHealth * ratio;
    }
    if (witherRate > 0) {
      bubble = (bubble - dt * witherRate).clamp(0, 9999);
      return;
    }
    final target = cfg.bubbleRadius[stage];
    if (bubble < target) {
      bubble = (bubble + cfg.bubbleGrowRate * dt).clamp(0, target);
    }
  }
}
