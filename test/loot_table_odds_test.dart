import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/src/core/domain/loot_table.dart';
import 'package:saga_map/src/core/domain/loot_table_odds.dart';
import 'package:saga_map/src/core/domain/models/inventory_item.dart';

void main() {
  group('LootTableOdds', () {
    test('rarityOdds returns correct odds for MVP table', () {
      final odds = kMvpLootTable.rarityOdds();
      expect(odds[InventoryRarity.common], closeTo(0.75, 1e-9));
      expect(odds[InventoryRarity.rare], closeTo(0.175, 1e-9));
      expect(odds[InventoryRarity.legendary], closeTo(0.075, 1e-9));
    });

    test('sum of all probabilities is 1.0', () {
      final odds = kMvpLootTable.rarityOdds();
      final sum = odds.values.fold<double>(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('empirical distribution matches rarityOdds within 1% after 100,000 rolls', () {
      final odds = kMvpLootTable.rarityOdds();
      
      final Map<InventoryRarity, int> counts = {
        for (final rarity in InventoryRarity.values) rarity: 0,
      };

      const int numRolls = 100000;
      
      for (int i = 0; i < numRolls; i++) {
        final item = rollBossReward(levelId: i + 1, globalSeed: 42);
        counts[item.rarity] = counts[item.rarity]! + 1;
      }

      for (final rarity in odds.keys) {
        final expected = odds[rarity]!;
        final actual = counts[rarity]! / numRolls;
        expect(actual, closeTo(expected, 0.01));
      }
    });

    test('entry with zero weight has 0.0 probability and never drops', () {
      const table = [
        LootTableEntry(itemId: 'a', itemName: 'A', rarity: InventoryRarity.common, weight: 100),
        LootTableEntry(itemId: 'b', itemName: 'B', rarity: InventoryRarity.rare, weight: 0),
      ];

      expect(table.probabilityOf(table[1]), 0.0);
      final odds = table.rarityOdds();
      expect(odds[InventoryRarity.rare], 0.0);
    });

    test('invalid tables throw ArgumentError', () {
      expect(() => <LootTableEntry>[].totalWeight, throwsArgumentError);
      
      const zeroTable = [
        LootTableEntry(itemId: 'a', itemName: 'A', rarity: InventoryRarity.common, weight: 0),
      ];
      expect(() => zeroTable.totalWeight, throwsArgumentError);

      const negativeTable = [
        LootTableEntry(itemId: 'a', itemName: 'A', rarity: InventoryRarity.common, weight: -10),
      ];
      expect(() => negativeTable.totalWeight, throwsArgumentError);
      
      const table = [
        LootTableEntry(itemId: 'a', itemName: 'A', rarity: InventoryRarity.common, weight: 10),
      ];
      const notInTable = LootTableEntry(itemId: 'b', itemName: 'B', rarity: InventoryRarity.rare, weight: 5);
      expect(() => table.probabilityOf(notInTable), throwsArgumentError);
    });
  });
}
