import 'loot_table.dart';
import 'models/inventory_item.dart';

/// Drop-rate maths over a loot table, so a host can show the odds it is
/// actually rolling against rather than restating the weights by hand.
///
/// Every method reads the weights only; nothing here rolls or mutates.
extension LootTableOdds on List<LootTableEntry> {
  /// The total weight of all entries in the loot table.
  ///
  /// Throws [ArgumentError] if the table is empty, if any entry has a negative weight,
  /// or if the total weight is 0.
  int get totalWeight {
    if (isEmpty) {
      throw ArgumentError('Loot table cannot be empty.');
    }
    int sum = 0;
    for (final entry in this) {
      if (entry.weight < 0) {
        throw ArgumentError('Loot table entries cannot have negative weights.');
      }
      sum += entry.weight;
    }
    if (sum == 0) {
      throw ArgumentError(
          'Loot table must have a total weight greater than 0.');
    }
    return sum;
  }

  /// Calculates the probability of a specific [LootTableEntry] being rolled.
  ///
  /// If the given [entry] is not in this loot table, throws an [ArgumentError].
  /// If the entry has a weight of 0, it is valid but its probability is 0.0 and it will never be rolled.
  double probabilityOf(LootTableEntry entry) {
    if (!contains(entry)) {
      throw ArgumentError('The entry is not present in the loot table.');
    }
    final weight = totalWeight;
    return entry.weight / weight;
  }

  /// The numbers a disclosure screen should show — derived from the same
  /// weights the roll uses, so the two cannot drift apart.
  ///
  /// **This is a disclosed rate, not a guarantee**, and the difference is the
  /// seed. `rollBossReward` is deterministic in `globalSeed` and the level id,
  /// so these odds describe what a player gets only while the seed is
  /// something the player cannot choose. The moment the seed is writable — and
  /// `SagaProgressRepository.saveGlobalSeed` exists to write it — a player can
  /// search seeds for the outcome they want and the distribution below stops
  /// describing them. The audit found `ancient_crown_01` at level 14 under
  /// `globalSeed == 21` by doing exactly that.
  ///
  /// That is a deliberate trust boundary, not a defect: rewards are rolled on
  /// the client, and a client-side roll is advisory (ADR-0009). If these
  /// numbers back a regulatory disclosure or anything a player can spend money
  /// against, the roll belongs on a server and this method describes the
  /// server's table, not the device's.
  Map<InventoryRarity, double> rarityOdds() {
    final weight = totalWeight;
    final Map<InventoryRarity, double> odds = {};

    for (final entry in this) {
      odds[entry.rarity] =
          (odds[entry.rarity] ?? 0.0) + (entry.weight / weight);
    }

    return odds;
  }
}
