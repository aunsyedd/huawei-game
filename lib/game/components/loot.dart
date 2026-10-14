enum LootKind { weapon, armour, water, mask, seed }

class LootItem {
  LootItem(this.kind, this.refId, this.x, this.y, {this.amount = 1, this.ammo});

  final LootKind kind;
  final String refId;
  double x, y;
  int amount;

  /// Remaining magazine for dropped weapons (null = full).
  int? ammo;
  bool taken = false;

  static LootKind kindFor(String id) => switch (id) {
    'water_bottle' => LootKind.water,
    'air_mask' => LootKind.mask,
    'seed_pack' => LootKind.seed,
    _ when id.startsWith('vest') => LootKind.armour,
    _ => LootKind.weapon,
  };
}
