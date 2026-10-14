import 'dart:ui' show Color;

import 'package:vector_math/vector_math.dart';

import '../../data/game_config.dart';
import 'bot.dart';

enum ActorAction { none, healing, masking, planting }

class WeaponInstance {
  WeaponInstance(this.stats) : ammo = stats.magazine;
  final WeaponStats stats;
  int ammo;
  double reloadTimer = 0;
  bool get reloading => reloadTimer > 0;
}

/// Anyone taking part in the match: the player or a bot.
class Actor {
  Actor({required this.id, required this.name, required this.isPlayer, required this.color, required this.speed});

  static const double radius = 18;

  final int id;
  final String name;
  final bool isPlayer;
  final Color color;
  final double speed;

  final Vector2 pos = Vector2.zero();
  final Vector2 vel = Vector2.zero();
  final Vector2 moveInput = Vector2.zero();
  double aimAngle = 0;
  bool wantFire = false;

  double maxHealth = 100, health = 100;
  double armour = 0;
  ArmourStats? vest;

  final List<WeaponInstance?> slots = [null, null];
  int activeSlot = 0;
  int water = 0, masks = 0, seeds = 0;

  bool alive = true;
  double fireCooldown = 0;
  double hazeShield = 0;

  ActorAction action = ActorAction.none;
  double actionTime = 0, actionDuration = 0;

  // Stats for results.
  int tagOuts = 0, treesPlanted = 0, placement = 0;
  double timeAlive = 0, hazeTime = 0, damageDealt = 0;

  // Feedback.
  double hitFlash = 0;
  double lastDamageTime = -99;
  Actor? lastAttacker;

  /// Set for bots (and the player on autopilot in tests).
  BotBrain? brain;

  WeaponInstance? get weapon => slots[activeSlot];
  bool get busy => action != ActorAction.none;
  double get actionProgress => actionDuration <= 0 ? 0 : (actionTime / actionDuration).clamp(0, 1);

  void cancelAction() {
    action = ActorAction.none;
    actionTime = 0;
  }
}
