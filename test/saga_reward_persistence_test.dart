import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Records every write, so a test can count them.
class _RecordingInventory implements InventoryRepository {
  final List<InventoryItem> written = [];

  @override
  Future<void> addItem(InventoryItem item) async => written.add(item);

  @override
  Future<List<InventoryItem>> getItems() async => List.unmodifiable(written);
}

class _WriteFailed implements Exception {}

/// A store that refuses every write — a full disk, a revoked session.
class _FailingInventory implements InventoryRepository {
  var attempts = 0;

  @override
  Future<void> addItem(InventoryItem item) async {
    attempts++;
    throw _WriteFailed();
  }

  @override
  Future<List<InventoryItem>> getItems() async => const [];
}

/// Every roll against a one-entry table yields this item, so an assertion on
/// the reward is about the write rather than about the roll.
const _sole = <LootTableEntry>[
  LootTableEntry(
    itemId: 'relic',
    itemName: 'Relic',
    rarity: InventoryRarity.rare,
    weight: 1,
  ),
];

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
  group('210.07 — without an inventory, 2.0.0 exactly', () {
    test('execute returns the reward and never claims to have written it', () {
      final result = const CompleteLevelUseCase().execute(
        currentProgress: _reached(14),
        levelId: 14,
        globalSeed: 7,
      );
      expect(result.reward, isNotNull);
      expect(result.rewardPersisted, isFalse);
    });

    test('execute ignores an injected inventory', () {
      final inventory = _RecordingInventory();
      final result = CompleteLevelUseCase(inventory: inventory).execute(
        currentProgress: _reached(14),
        levelId: 14,
        globalSeed: 7,
      );
      expect(result.reward, isNotNull);
      expect(result.rewardPersisted, isFalse);
      expect(inventory.written, isEmpty);
    });

    test('executeAndPersist without an inventory is refused', () async {
      // A method named for persisting that quietly did not persist is the
      // failure this entry point exists to remove.
      await expectLater(
        const CompleteLevelUseCase().executeAndPersist(
          currentProgress: _reached(14),
          levelId: 14,
          globalSeed: 7,
        ),
        throwsStateError,
      );
    });
  });

  group('210.11, 210.12 — an injected inventory receives the reward', () {
    test('the rolled item is written, and the result says so', () async {
      final inventory = _RecordingInventory();
      final useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: _sole,
        inventory: inventory,
      );

      final result = await useCase.executeAndPersist(
        currentProgress: _reached(3),
        levelId: 3,
        globalSeed: 7,
      );

      expect(inventory.written, hasLength(1));
      expect(inventory.written.single.itemId, 'relic');
      expect(inventory.written.single.obtainedFromLevelId, 3);
      expect(result.rewardPersisted, isTrue);
      expect(result.reward?.itemId, 'relic');
      expect(result.outcome, CompleteLevelOutcome.applied);
      expect(
        result.nextProgress.levels[3]?.state,
        LevelCompletionState.completed,
      );
    });

    test('the item written is the one execute would have returned', () async {
      final inventory = _RecordingInventory();
      final useCase = CompleteLevelUseCase(inventory: inventory);
      final now = DateTime.utc(2026, 9, 13);

      final plain = useCase.execute(
        currentProgress: _reached(14),
        levelId: 14,
        globalSeed: 99,
        now: now,
      );
      final persisted = await useCase.executeAndPersist(
        currentProgress: _reached(14),
        levelId: 14,
        globalSeed: 99,
        now: now,
      );

      expect(inventory.written.single.itemId, plain.reward?.itemId);
      expect(inventory.written.single.obtainedAt, now);
      expect(persisted.nextProgress, plain.nextProgress);
    });

    test('the package in-memory repository works as the inventory', () async {
      final inventory = InMemoryInventoryRepository();
      final useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: _sole,
        inventory: inventory,
      );

      await useCase.executeAndPersist(
        currentProgress: _reached(0),
        levelId: 0,
        globalSeed: 1,
      );

      expect((await inventory.getItems()).single.itemId, 'relic');
    });

    test('a completion that mints nothing writes nothing', () async {
      final inventory = _RecordingInventory();
      // Level 3 is not a boss under the default rule.
      final result =
          await CompleteLevelUseCase(inventory: inventory).executeAndPersist(
        currentProgress: _reached(3),
        levelId: 3,
        globalSeed: 7,
      );

      expect(result.reward, isNull);
      expect(result.rewardPersisted, isFalse);
      expect(inventory.written, isEmpty);
    });

    test('a rejected completion writes nothing', () async {
      final inventory = _RecordingInventory();
      final useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: _sole,
        inventory: inventory,
      );

      final result = await useCase.executeAndPersist(
        currentProgress: SagaProgress.initial(),
        levelId: 50,
        globalSeed: 7,
      );

      expect(result.outcome, CompleteLevelOutcome.rejectedUnreached);
      expect(inventory.written, isEmpty);
    });
  });

  group('210.10, 210.13 — the first-clear guard holds on the write path', () {
    test('replaying a boss does not write a second item', () async {
      final inventory = _RecordingInventory();
      final useCase = CompleteLevelUseCase(inventory: inventory);

      final first = await useCase.executeAndPersist(
        currentProgress: _reached(14),
        levelId: 14,
        globalSeed: 7,
      );
      final replay = await useCase.executeAndPersist(
        currentProgress: first.nextProgress,
        levelId: 14,
        globalSeed: 7,
        stars: 3,
      );

      expect(inventory.written, hasLength(1));
      expect(replay.reward, isNull);
      expect(replay.rewardPersisted, isFalse);
    });

    test('a replay-mode run on a boss writes nothing', () async {
      final inventory = _RecordingInventory();
      final result =
          await CompleteLevelUseCase(inventory: inventory).executeAndPersist(
        currentProgress: _reached(14),
        levelId: 14,
        globalSeed: 7,
        modeId: 'hard',
      );

      expect(result.reward, isNull);
      expect(inventory.written, isEmpty);
    });

    test('two calls on one stale snapshot still both write', () async {
      // Pinned, not fixed. The guard reads the snapshot it is handed, and
      // owning the write does not change what the snapshot says. What 2.1.0
      // closed is the other hole: a reward returned and then dropped.
      final inventory = _RecordingInventory();
      final useCase = CompleteLevelUseCase(inventory: inventory);
      final snapshot = _reached(14);

      await useCase.executeAndPersist(
        currentProgress: snapshot,
        levelId: 14,
        globalSeed: 7,
      );
      await useCase.executeAndPersist(
        currentProgress: snapshot,
        levelId: 14,
        globalSeed: 7,
      );

      expect(inventory.written, hasLength(2));
    });
  });

  group('210.14 — a failed write', () {
    test('the exception reaches the caller', () async {
      final inventory = _FailingInventory();
      final useCase = CompleteLevelUseCase(
        bossRule: _always,
        lootTable: _sole,
        inventory: inventory,
      );

      await expectLater(
        useCase.executeAndPersist(
          currentProgress: _reached(2),
          levelId: 2,
          globalSeed: 7,
        ),
        throwsA(isA<_WriteFailed>()),
      );
      expect(inventory.attempts, 1);
    });

    test('a completion with nothing to write never reaches the store',
        () async {
      final inventory = _FailingInventory();
      final result =
          await CompleteLevelUseCase(inventory: inventory).executeAndPersist(
        currentProgress: _reached(3),
        levelId: 3,
        globalSeed: 7,
      );

      expect(result.outcome, CompleteLevelOutcome.applied);
      expect(inventory.attempts, 0);
    });
  });
}
