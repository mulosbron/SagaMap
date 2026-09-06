import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

void main() {
  group('CompleteLevelUseCase', () {
    test('marks current level completed and unlocks next level', () {
      const useCase = CompleteLevelUseCase();
      final now = DateTime.utc(2026, 4, 28, 20);

      final result = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 0,
        globalSeed: 7,
        now: now,
      );

      expect(
        result.nextProgress.levels[0]?.state,
        LevelCompletionState.completed,
      );
      expect(result.nextProgress.levels[0]?.stars, 1);
      expect(result.nextProgress.levels[0]?.lastPlayedAt, now);
      expect(
        result.nextProgress.levels[1]?.state,
        LevelCompletionState.unlocked,
      );
      expect(result.nextProgress.currentMaxUnlockedLevelId, 1);
    });

    test('unlocks a successor that was already stored as locked', () {
      const useCase = CompleteLevelUseCase();

      // Seeding every level as locked up front is a natural thing for a host to
      // do. The successor used to stay locked forever while
      // currentMaxUnlockedLevelId claimed otherwise, so the map went dead after
      // a single completion.
      const preSeeded = SagaProgress(
        currentMaxUnlockedLevelId: 0,
        levels: {
          0: LevelProgress(levelId: 0, state: LevelCompletionState.unlocked),
          1: LevelProgress(levelId: 1, state: LevelCompletionState.locked),
          2: LevelProgress(levelId: 2, state: LevelCompletionState.locked),
        },
      );

      final result = useCase.execute(
        currentProgress: preSeeded,
        levelId: 0,
        globalSeed: 7,
      );

      expect(
        result.nextProgress.levels[1]?.state,
        LevelCompletionState.unlocked,
      );
      expect(result.nextProgress.currentMaxUnlockedLevelId, 1);
      // Levels further ahead stay shut.
      expect(result.nextProgress.levels[2]?.state, LevelCompletionState.locked);
    });

    test('keeps the best star count when a level is replayed', () {
      const useCase = CompleteLevelUseCase();
      const threeStarred = SagaProgress(
        currentMaxUnlockedLevelId: 3,
        levels: {
          2: LevelProgress(
            levelId: 2,
            state: LevelCompletionState.completed,
            stars: 3,
          ),
        },
      );

      final replayed = useCase.execute(
        currentProgress: threeStarred,
        levelId: 2,
        globalSeed: 7,
        stars: 1,
      );

      // A weaker replay keeps the earlier three-star result.
      expect(replayed.nextProgress.levels[2]?.stars, 3);
    });

    test('clamps an out-of-range star score', () {
      const useCase = CompleteLevelUseCase();

      // Genre norm is three stars; a caller (or tampered save) passing more is
      // coerced rather than propagated. The guard is a runtime clamp, not a
      // release-stripped assert.
      final tooMany = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 0,
        globalSeed: 7,
        stars: 5,
      );
      expect(tooMany.nextProgress.levels[0]?.stars, kMaxLevelStars);

      final negative = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 0,
        globalSeed: 7,
        stars: -3,
      );
      expect(negative.nextProgress.levels[0]?.stars, 0);
    });

    test('completing a level ahead is rejected when unlock order is enforced',
        () {
      const useCase = CompleteLevelUseCase();
      const atStart = SagaProgress(
        currentMaxUnlockedLevelId: 2,
        levels: {},
      );

      // Skipping to level 50 with the guard on is a no-op.
      final skipped = useCase.execute(
        currentProgress: atStart,
        levelId: 50,
        globalSeed: 7,
        enforceUnlockOrder: true,
      );
      expect(skipped.nextProgress.currentMaxUnlockedLevelId, 2);
      expect(skipped.nextProgress.levels.containsKey(50), isFalse);

      // A reachable level still completes.
      final reachable = useCase.execute(
        currentProgress: atStart,
        levelId: 2,
        globalSeed: 7,
        enforceUnlockOrder: true,
      );
      expect(
        reachable.nextProgress.levels[2]?.state,
        LevelCompletionState.completed,
      );
    });

    test('a boss reward is minted only on first clear', () {
      const useCase = CompleteLevelUseCase();

      final first = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 14,
        globalSeed: 99,
      );
      expect(first.reward, isNotNull);

      // Replaying the boss must not re-mint the reward.
      final replay = useCase.execute(
        currentProgress: first.nextProgress,
        levelId: 14,
        globalSeed: 99,
      );
      expect(replay.reward, isNull);
    });

    test('never lowers currentMaxUnlockedLevelId', () {
      const useCase = CompleteLevelUseCase();
      const deepProgress = SagaProgress(
        currentMaxUnlockedLevelId: 20,
        levels: {},
      );

      // Replaying an early level must not roll progression back.
      final result = useCase.execute(
        currentProgress: deepProgress,
        levelId: 1,
        globalSeed: 7,
      );

      expect(result.nextProgress.currentMaxUnlockedLevelId, 20);
    });

    test('does not demote an already completed successor', () {
      const useCase = CompleteLevelUseCase();
      const bothDone = SagaProgress(
        currentMaxUnlockedLevelId: 5,
        levels: {
          3: LevelProgress(levelId: 3, state: LevelCompletionState.completed),
          4: LevelProgress(
            levelId: 4,
            state: LevelCompletionState.completed,
            stars: 2,
          ),
        },
      );

      final result = useCase.execute(
        currentProgress: bothDone,
        levelId: 3,
        globalSeed: 7,
      );

      expect(
        result.nextProgress.levels[4]?.state,
        LevelCompletionState.completed,
      );
      expect(result.nextProgress.levels[4]?.stars, 2);
    });

    test('returns boss reward only on boss levels', () {
      const useCase = CompleteLevelUseCase();
      final initial = SagaProgress.initial();

      final nonBoss = useCase.execute(
        currentProgress: initial,
        levelId: 9,
        globalSeed: 99,
      );
      // The 15th level a player sees, zero-based.
      final boss = useCase.execute(
        currentProgress: initial,
        levelId: 14,
        globalSeed: 99,
      );
      // Where 1.x wrongly put the boss: the 16th node, difficulty 1.
      final formerBoss = useCase.execute(
        currentProgress: initial,
        levelId: 15,
        globalSeed: 99,
      );

      expect(nonBoss.reward, isNull);
      expect(boss.reward, isNotNull);
      expect(formerBoss.reward, isNull);
    });

    test('the 1.x boss placement can be restored with bossRule', () {
      // The escape hatch ADR-0002 promises: a host that already paid out at
      // ids 15/30/45 injects the old rule and nothing moves under its players.
      const legacy = CompleteLevelUseCase(bossRule: _legacyBossRule);
      final initial = SagaProgress.initial();

      expect(
        legacy.execute(currentProgress: initial, levelId: 15, globalSeed: 99).reward,
        isNotNull,
      );
      expect(
        legacy.execute(currentProgress: initial, levelId: 14, globalSeed: 99).reward,
        isNull,
      );
      expect(
        legacy.execute(currentProgress: initial, levelId: 0, globalSeed: 99).reward,
        isNull,
      );
    });
  });

  group('CompleteLevelUseCase injection', () {
    // A one-entry table: every roll against it must yield this item, so a test
    // asserting on the reward says something about the injection rather than
    // about whatever the package's own table happens to contain today.
    const soleEntry = LootTableEntry(
      itemId: 'test_relic_01',
      itemName: 'Test Relic',
      rarity: InventoryRarity.rare,
      weight: 1,
    );
    const fakeTable = <LootTableEntry>[soleEntry];

    test('a custom bossRule decides which levels drop', () {
      // Every seventh level is a boss here, and nothing else is — 15 is not a
      // multiple of 7, so the package's own milestone stops being special.
      const useCase = CompleteLevelUseCase(
        bossRule: _everySeventh,
        lootTable: fakeTable,
      );
      final initial = SagaProgress.initial();

      expect(
        useCase.execute(currentProgress: initial, levelId: 7, globalSeed: 1).reward,
        isNotNull,
      );
      expect(
        useCase.execute(currentProgress: initial, levelId: 8, globalSeed: 1).reward,
        isNull,
      );
      expect(
        useCase.execute(currentProgress: initial, levelId: 15, globalSeed: 1).reward,
        isNull,
      );
    });

    test('a custom lootTable is the only source of rewards', () {
      const useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: fakeTable,
      );

      for (var levelId = 0; levelId < 40; levelId++) {
        final reward = useCase
            .execute(
              currentProgress: SagaProgress.initial(),
              levelId: levelId,
              globalSeed: 4242,
            )
            .reward;
        expect(reward?.itemId, soleEntry.itemId);
        expect(reward?.rarity, soleEntry.rarity);
      }
    });

    test('the no-argument constructor keeps the default behaviour', () {
      const injected = CompleteLevelUseCase();
      final initial = SagaProgress.initial();

      // Whatever `isBossLevel` says today, the defaulted use case agrees with
      // it — the point is that injection did not shift the default.
      for (var levelId = 0; levelId < 40; levelId++) {
        final result = injected.execute(
          currentProgress: initial,
          levelId: levelId,
          globalSeed: 7,
        );
        expect(result.reward != null, isBossLevel(levelId),
            reason: 'level $levelId');
      }
    });

    test('a bossRule that never fires drops nothing at all', () {
      const useCase = CompleteLevelUseCase(
        bossRule: _never,
        lootTable: fakeTable,
      );

      for (var levelId = 0; levelId < 60; levelId++) {
        expect(
          useCase
              .execute(
                currentProgress: SagaProgress.initial(),
                levelId: levelId,
                globalSeed: 7,
              )
              .reward,
          isNull,
          reason: 'level $levelId',
        );
      }
    });

    test('a bossRule that always fires still honours the first-clear guard', () {
      const useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: fakeTable,
      );

      final first = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 2,
        globalSeed: 7,
      );
      expect(first.reward, isNotNull);

      final replay = useCase.execute(
        currentProgress: first.nextProgress,
        levelId: 2,
        globalSeed: 7,
      );
      expect(replay.reward, isNull);
    });

    test('an empty loot table throws instead of falling back', () {
      const useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: <LootTableEntry>[],
      );

      expect(
        () => useCase.execute(
          currentProgress: SagaProgress.initial(),
          levelId: 1,
          globalSeed: 7,
        ),
        throwsArgumentError,
      );
    });

    test('a zero-weight table throws instead of falling back', () {
      const useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: <LootTableEntry>[
          LootTableEntry(
            itemId: 'weightless',
            itemName: 'Weightless',
            rarity: InventoryRarity.common,
            weight: 0,
          ),
        ],
      );

      expect(
        () => useCase.execute(
          currentProgress: SagaProgress.initial(),
          levelId: 1,
          globalSeed: 7,
        ),
        throwsArgumentError,
      );
    });

    test('the same level, seed and table always mint the same item', () {
      const spread = <LootTableEntry>[
        LootTableEntry(
          itemId: 'a',
          itemName: 'A',
          rarity: InventoryRarity.common,
          weight: 3,
        ),
        LootTableEntry(
          itemId: 'b',
          itemName: 'B',
          rarity: InventoryRarity.rare,
          weight: 2,
        ),
        LootTableEntry(
          itemId: 'c',
          itemName: 'C',
          rarity: InventoryRarity.legendary,
          weight: 1,
        ),
      ];
      const useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: spread,
      );

      for (var levelId = 0; levelId < 30; levelId++) {
        final first = useCase.execute(
          currentProgress: SagaProgress.initial(),
          levelId: levelId,
          globalSeed: 31337,
        );
        final second = useCase.execute(
          currentProgress: SagaProgress.initial(),
          levelId: levelId,
          globalSeed: 31337,
        );
        expect(first.reward?.itemId, second.reward?.itemId,
            reason: 'level $levelId');
      }
    });
  });
}

bool _everySeventh(int levelId) => levelId > 0 && levelId % 7 == 0;

bool _always(int levelId) => true;

bool _never(int levelId) => false;

/// The 1.0.0 / 1.1.0 boss formula, kept as the documented downgrade path.
bool _legacyBossRule(int levelId) => levelId > 0 && levelId % 15 == 0;
