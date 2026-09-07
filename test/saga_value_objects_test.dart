import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// T-20: three small model defects that a value-object audit turns up, each
/// invisible to a test that reuses the same instance it built.

void main() {
  group('LootTableEntry equality', () {
    test('a field-identical copy is the same entry', () {
      const original = LootTableEntry(
        itemId: 'ancient_crown_01',
        itemName: 'Ancient Crown',
        rarity: InventoryRarity.legendary,
        weight: 12,
      );

      expect(original, kMvpLootTable.last);
      expect(original.hashCode, kMvpLootTable.last.hashCode);
    });

    test('drop odds answer for a copy, not only for the instance', () {
      // probabilityOf finds the entry with `contains`. Without value equality
      // that is reference equality, so asking about a copy — the natural way to
      // write "what are the odds on the crown?" — threw. The package's own
      // test passed the same instance back in, which is why it never showed.
      const copy = LootTableEntry(
        itemId: 'forest_hat_01',
        itemName: 'Forest Hat',
        rarity: InventoryRarity.common,
        weight: 60,
      );

      expect(
        kMvpLootTable.probabilityOf(copy),
        kMvpLootTable.probabilityOf(kMvpLootTable.first),
      );
    });

    test('a differing weight is a different entry', () {
      const heavier = LootTableEntry(
        itemId: 'ancient_crown_01',
        itemName: 'Ancient Crown',
        rarity: InventoryRarity.legendary,
        weight: 13,
      );
      expect(heavier, isNot(kMvpLootTable.last));
    });
  });

  group('LevelProgress', () {
    test('is compared by value', () {
      const a = LevelProgress(
        levelId: 3,
        state: LevelCompletionState.completed,
        stars: 2,
        extra: {'app.score': 10},
      );
      const b = LevelProgress(
        levelId: 3,
        state: LevelCompletionState.completed,
        stars: 2,
        extra: {'app.score': 10},
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(b.copyWith(stars: 3)));
      expect(
          a,
          isNot(const LevelProgress(
              levelId: 3, state: LevelCompletionState.completed, stars: 2)));
    });

    test('copyWith can clear lastPlayedAt deliberately', () {
      final played = LevelProgress(
        levelId: 1,
        state: LevelCompletionState.completed,
        lastPlayedAt: DateTime.utc(2026),
      );

      // Omitted: kept. `null` used to mean both "leave it" and "clear it", so
      // clearing was simply unreachable.
      expect(played.copyWith(stars: 2).lastPlayedAt, DateTime.utc(2026));

      // Passed as a getter returning null: cleared.
      expect(played.copyWith(lastPlayedAt: () => null).lastPlayedAt, isNull);

      expect(
        played.copyWith(lastPlayedAt: () => DateTime.utc(2027)).lastPlayedAt,
        DateTime.utc(2027),
      );
    });
  });

  group('SagaMapResponsiveConfig.copyWith', () {
    test('the unconstrained lateral extent is reachable', () {
      const config = SagaMapResponsiveConfig.defaults;
      expect(config.maxLateralExtentPolicy, isNotNull);

      // Documented as nullable-meaning-unconstrained, and unreachable once set
      // until the getter told the two nulls apart.
      final lifted = config.copyWith(maxLateralExtentPolicy: () => null);
      expect(lifted.maxLateralExtentPolicy, isNull);

      // Omitting it still keeps the current policy.
      expect(
        config
            .copyWith(pathAxis: SagaMapPathAxis.horizontal)
            .maxLateralExtentPolicy,
        config.maxLateralExtentPolicy,
      );
    });
  });

  group('an empty level map', () {
    test('is documented as uninitialised, not round-tripped', () {
      // The chosen half of the asymmetry with `extra`: since an unrecorded
      // level reads as locked, an empty map loaded faithfully is a map nothing
      // can be tapped on.
      final restored = SagaProgress.fromJson(const {
        'currentMaxUnlockedLevelId': 0,
        'levels': <String, dynamic>{},
      });
      expect(restored.levels[0]?.state, LevelCompletionState.unlocked);

      // `extra: {}` does survive, which is what makes the difference worth
      // stating out loud.
      final withExtra = SagaProgress.fromJson(
        SagaProgress(
            currentMaxUnlockedLevelId: 0,
            levels: const {},
            extra: const {}).toJson(),
      );
      expect(withExtra.extra, isEmpty);
    });
  });
}
