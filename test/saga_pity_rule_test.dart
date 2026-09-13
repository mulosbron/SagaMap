import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Nearly every roll against it is common, so a guarantee that works is
/// visible, and one that does not cannot hide behind luck.
const _stingyTable = <LootTableEntry>[
  LootTableEntry(
    itemId: 'pebble',
    itemName: 'Pebble',
    rarity: InventoryRarity.common,
    weight: 97,
  ),
  LootTableEntry(
    itemId: 'amulet',
    itemName: 'Amulet',
    rarity: InventoryRarity.rare,
    weight: 2,
  ),
  LootTableEntry(
    itemId: 'crown',
    itemName: 'Crown',
    rarity: InventoryRarity.legendary,
    weight: 1,
  ),
];

/// An economy with no rare tier at all, which is legitimate.
const _commonsOnly = <LootTableEntry>[
  LootTableEntry(
    itemId: 'pebble',
    itemName: 'Pebble',
    rarity: InventoryRarity.common,
    weight: 3,
  ),
  LootTableEntry(
    itemId: 'stick',
    itemName: 'Stick',
    rarity: InventoryRarity.common,
    weight: 1,
  ),
];

/// The roll exactly as 2.0.0 made it, restated here so that "unchanged" means
/// unchanged from that algorithm rather than from whatever the code does today.
String _rollAs200(int levelId, int globalSeed, List<LootTableEntry> table) {
  final total = table.fold<int>(0, (sum, entry) => sum + entry.weight);
  var roll = Random(levelId ^ globalSeed).nextInt(total);
  for (final entry in table) {
    if (roll < entry.weight) return entry.itemId;
    roll -= entry.weight;
  }
  throw StateError('unreachable');
}

bool _always(int levelId) => true;

SagaProgress _reached(int levelId) => SagaProgress(
      currentMaxUnlockedLevelId: levelId,
      levels: {
        levelId: LevelProgress(
          levelId: levelId,
          state: LevelCompletionState.unlocked,
        ),
      },
    );

void main() {
  const rule = SagaPityRule();

  group('SagaPityRule', () {
    test('defaults to ten rolls and a rare guarantee', () {
      expect(rule.threshold, 10);
      expect(rule.guaranteedRarity, InventoryRarity.rare);
    });

    test('a threshold of zero or less is refused', () {
      // The constructor asserts, which a release build strips; `isDue` throws
      // an ArgumentError there instead. A test run keeps asserts, so either is
      // the refusal — what must never happen is a rule that silently applies.
      final refused =
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>()));
      for (final threshold in [0, -3]) {
        expect(() => SagaPityRule(threshold: threshold).isDue(0), refused);
      }
    });

    test('isDue is at or past the threshold, never before it', () {
      expect(rule.isDue(9), isFalse);
      expect(rule.isDue(10), isTrue);
      expect(rule.isDue(11), isTrue);
    });

    test('nextCounter resets on the guaranteed rarity or better', () {
      expect(rule.nextCounter(7, InventoryRarity.rare), 0);
      expect(rule.nextCounter(7, InventoryRarity.legendary), 0);
      expect(rule.nextCounter(7, InventoryRarity.common), 8);
      // A negative counter only a tampered save holds counts from zero.
      expect(rule.nextCounter(-4, InventoryRarity.common), 1);
    });
  });

  group('200.15 — at the threshold, the guarantee holds', () {
    test('every roll is the guaranteed rarity or better', () {
      for (var levelId = 0; levelId < 300; levelId++) {
        final item = rollBossReward(
          levelId: levelId,
          globalSeed: 42,
          table: _stingyTable,
          pityCounter: 10,
          pityRule: rule,
        );
        expect(
          rule.satisfies(item.rarity),
          isTrue,
          reason: 'level $levelId rolled ${item.rarity}',
        );
      }
    });

    test('a counter well past the threshold is still guaranteed', () {
      for (var levelId = 0; levelId < 100; levelId++) {
        final item = rollBossReward(
          levelId: levelId,
          globalSeed: 42,
          table: _stingyTable,
          pityCounter: 250,
          pityRule: rule,
        );
        expect(rule.satisfies(item.rarity), isTrue, reason: 'level $levelId');
      }
    });

    test('a legendary guarantee draws only legendaries', () {
      const legendary = SagaPityRule(
        threshold: 3,
        guaranteedRarity: InventoryRarity.legendary,
      );
      for (var levelId = 0; levelId < 100; levelId++) {
        final item = rollBossReward(
          levelId: levelId,
          globalSeed: 42,
          table: _stingyTable,
          pityCounter: 3,
          pityRule: legendary,
        );
        expect(item.itemId, 'crown', reason: 'level $levelId');
      }
    });

    test('the use case hands the counter and the rule to the roll', () {
      const useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: _stingyTable,
        pityRule: rule,
      );
      for (var levelId = 0; levelId < 100; levelId++) {
        final reward = useCase
            .execute(
              currentProgress: _reached(levelId),
              levelId: levelId,
              globalSeed: 7,
              pityCounter: 10,
            )
            .reward;
        expect(reward, isNotNull);
        expect(rule.satisfies(reward!.rarity), isTrue,
            reason: 'level $levelId');
      }
    });

    test('a guaranteed roll is as deterministic as any other', () {
      // 200.12: the counter narrows the entries; it is never mixed into the
      // seed, so the same inputs still mint the same item.
      for (var levelId = 0; levelId < 60; levelId++) {
        InventoryItem roll() => rollBossReward(
              levelId: levelId,
              globalSeed: 31337,
              table: _stingyTable,
              pityCounter: 12,
              pityRule: rule,
            );
        expect(roll().itemId, roll().itemId, reason: 'level $levelId');
      }
    });

    test('with no entry of that rarity the roll falls back, not throws', () {
      // 200.11: a table with no rare tier is a legitimate economy, and a
      // guarantee it cannot keep is not a misconfiguration.
      for (var levelId = 0; levelId < 60; levelId++) {
        final item = rollBossReward(
          levelId: levelId,
          globalSeed: 42,
          table: _commonsOnly,
          pityCounter: 99,
          pityRule: rule,
        );
        expect(item.itemId, _rollAs200(levelId, 42, _commonsOnly));
      }
    });

    test('a zero-weight rare tier counts as no tier at all', () {
      const table = <LootTableEntry>[
        LootTableEntry(
          itemId: 'pebble',
          itemName: 'Pebble',
          rarity: InventoryRarity.common,
          weight: 5,
        ),
        LootTableEntry(
          itemId: 'ghost',
          itemName: 'Ghost',
          rarity: InventoryRarity.rare,
          weight: 0,
        ),
      ];
      for (var levelId = 0; levelId < 30; levelId++) {
        expect(
          rollBossReward(
            levelId: levelId,
            globalSeed: 42,
            table: table,
            pityCounter: 10,
            pityRule: rule,
          ).itemId,
          'pebble',
        );
      }
    });

    test('a malformed table is refused even when pity would narrow it', () {
      // Validating only the narrowed pool would let a broken table through on
      // exactly the rolls a player notices least.
      const broken = <LootTableEntry>[
        LootTableEntry(
          itemId: 'pebble',
          itemName: 'Pebble',
          rarity: InventoryRarity.common,
          weight: -1,
        ),
        LootTableEntry(
          itemId: 'amulet',
          itemName: 'Amulet',
          rarity: InventoryRarity.rare,
          weight: 5,
        ),
      ];
      expect(
        () => rollBossReward(
          levelId: 1,
          globalSeed: 42,
          table: broken,
          pityCounter: 10,
          pityRule: rule,
        ),
        throwsArgumentError,
      );
    });
  });

  group('200.16 — below the threshold, the normal distribution', () {
    test('one short of the threshold rolls as if there were no rule', () {
      var commons = 0;
      for (var levelId = 0; levelId < 300; levelId++) {
        final item = rollBossReward(
          levelId: levelId,
          globalSeed: 42,
          table: _stingyTable,
          pityCounter: 9,
          pityRule: rule,
        );
        expect(item.itemId, _rollAs200(levelId, 42, _stingyTable));
        if (item.rarity == InventoryRarity.common) commons++;
      }
      // The stingy table shows through: the rule did not quietly apply early.
      expect(commons, greaterThan(250));
    });
  });

  group('200.17 — without a rule, exactly 2.0.0', () {
    test('rollBossReward ignores the counter and rolls as 2.0.0 did', () {
      for (final table in [kMvpLootTable, _stingyTable]) {
        for (var levelId = 0; levelId < 200; levelId++) {
          for (final counter in [0, 10, 1000]) {
            expect(
              rollBossReward(
                levelId: levelId,
                globalSeed: 1234,
                table: table,
                pityCounter: counter,
              ).itemId,
              _rollAs200(levelId, 1234, table),
              reason: 'level $levelId, counter $counter',
            );
          }
        }
      }
    });

    test('the default use case mints what 2.0.0 minted', () {
      const useCase = CompleteLevelUseCase(bossRule: _always);
      for (var levelId = 0; levelId < 60; levelId++) {
        final reward = useCase
            .execute(
              currentProgress: _reached(levelId),
              levelId: levelId,
              globalSeed: 99,
              pityCounter: 50,
            )
            .reward;
        expect(reward?.itemId, _rollAs200(levelId, 99, kMvpLootTable));
      }
    });
  });
}
