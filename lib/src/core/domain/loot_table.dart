import 'dart:math';

import 'loot_table_odds.dart';
import 'models/level_data.dart';
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

/// Decides whether a level is a boss encounter.
///
/// The default is [isBossLevel]; a host injects its own through
/// `CompleteLevelUseCase.bossRule` to move, widen or remove boss milestones
/// without forking the use case.
typedef SagaBossRule = bool Function(int levelId);

/// Whether [levelId] is a boss level.
///
/// Ids are zero-based (see [LevelData.id]), so "every fifteenth level" — the
/// 15th, 30th and 45th a player sees — is `id % 15 == 14`, not `id % 15 == 0`.
/// The old formula landed on the 16th node and, because difficulty is
/// `1 + id % 5`, handed the boss the easiest board in the cycle.
///
/// The corrected milestone aligns three systems for free: `id % 15 == 14`
/// implies `id % 5 == 4`, so every boss is also a difficulty-5 board.
///
/// Negative ids are never boss levels.
///
/// This is the default value of `CompleteLevelUseCase.bossRule`, which is why
/// it stays public: it has to be nameable to be overridable. To keep the 1.x
/// placement, inject the old rule instead of forking the use case:
///
/// ```dart
/// const useCase = CompleteLevelUseCase(bossRule: legacyBossRule);
///
/// bool legacyBossRule(int levelId) => levelId > 0 && levelId % 15 == 0;
/// ```
bool isBossLevel(int levelId) => levelId >= 0 && levelId % 15 == 14;

/// Rolls a deterministic reward for boss levels.
///
/// > **This is an unguarded mint.** It stays public because a host needs it to
/// > preview a drop, to replay a save, or to run its own economy — but it
/// > applies **no** first-clear check, no progression check and no boss check.
/// > Calling it twice for the same `(levelId, globalSeed, table)` returns the
/// > same item twice, and a host that persists both has duplicated an item.
///
/// The invariant a direct caller must uphold, in full: roll **once** per level
/// per player, only after establishing that this is the level's first clear
/// against the *persisted* progress, and only for a level [isBossLevel] (or
/// the host's own rule) accepts. `CompleteLevelUseCase.execute` upholds all
/// three; nothing else does. Prefer it unless you specifically need an
/// unpersisted preview — a drop-odds screen or a "what would this boss give
/// me" tooltip, neither of which writes to an inventory.
///
/// [table] defaults to [kMvpLootTable]. An empty table, a negative weight or a
/// total weight of `0` throws an [ArgumentError] rather than falling back to
/// the built-in table: silently handing out the package's own items while the
/// host believes its own table is live is the hardest kind of bug to diagnose.
///
/// The seed is `levelId ^ globalSeed`, so the same `(levelId, globalSeed, table)`
/// always yields the same item.
InventoryItem rollBossReward({
  required int levelId,
  required int globalSeed,
  List<LootTableEntry> table = kMvpLootTable,
  DateTime? now,
}) {
  // Validates empty, negative and zero-total tables in one place, shared with
  // the odds extension so the roll and a disclosure screen cannot disagree.
  final totalWeight = table.totalWeight;
  final rng = Random(levelId ^ globalSeed);
  var roll = rng.nextInt(totalWeight);
  for (final entry in table) {
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
  // Unreachable: `roll` is drawn from `[0, totalWeight)` and the loop subtracts
  // exactly `totalWeight` across all entries. Kept as a loud failure rather
  // than the old silent first-entry fallback, which would have masked a table
  // mutated underneath the roll.
  throw StateError(
    'Loot roll fell through a table of total weight $totalWeight.',
  );
}
