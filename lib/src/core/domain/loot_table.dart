import 'dart:math';

import 'models/inventory_item.dart';

/// Weighted loot entry used by reward roll logic.
class LootTableEntry {
  final String itemId;
  final String itemName;
  final InventoryRarity rarity;
  final int weight;

  const LootTableEntry({
    required this.itemId,
    required this.itemName,
    required this.rarity,
    required this.weight,
  });
}

/// Default MVP boss-drop table.
const List<LootTableEntry> kMvpLootTable = [
  LootTableEntry(
      itemId: 'forest_hat_01',
      itemName: 'Forest Hat',
      rarity: InventoryRarity.common,
      weight: 60),
  LootTableEntry(
      itemId: 'desert_goggles_01',
      itemName: 'Desert Goggles',
      rarity: InventoryRarity.common,
      weight: 60),
  LootTableEntry(
      itemId: 'glacier_amulet_01',
      itemName: 'Glacier Amulet',
      rarity: InventoryRarity.rare,
      weight: 28),
  LootTableEntry(
      itemId: 'ancient_crown_01',
      itemName: 'Ancient Crown',
      rarity: InventoryRarity.legendary,
      weight: 12),
];

/// Returns true if the level is treated as a boss milestone.
bool isBossLevel(int levelId) => levelId > 0 && levelId % 15 == 0;

/// Rolls a deterministic reward for boss levels.
InventoryItem rollBossReward({
  required int levelId,
  required int globalSeed,
  DateTime? now,
}) {
  final totalWeight =
      kMvpLootTable.fold<int>(0, (sum, entry) => sum + entry.weight);
  final rng = Random(levelId ^ globalSeed);
  var roll = rng.nextInt(totalWeight);
  for (final entry in kMvpLootTable) {
    if (roll < entry.weight) {
      return InventoryItem(
        itemId: entry.itemId,
        itemName: entry.itemName,
        rarity: entry.rarity,
        obtainedFromLevelId: levelId,
        obtainedAt: now ?? DateTime.now(),
      );
    }
    roll -= entry.weight;
  }
  final fallback = kMvpLootTable.first;
  return InventoryItem(
    itemId: fallback.itemId,
    itemName: fallback.itemName,
    rarity: fallback.rarity,
    obtainedFromLevelId: levelId,
    obtainedAt: now ?? DateTime.now(),
  );
}
