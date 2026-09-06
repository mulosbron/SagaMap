import 'dart:math' as math;

import '../loot_table.dart';
import '../models/inventory_item.dart';
import '../models/level_progress.dart';
import '../models/saga_progress.dart';

/// Result object returned by [CompleteLevelUseCase.execute].
class CompleteLevelResult {
  const CompleteLevelResult({
    required this.nextProgress,
    this.reward,
  });

  final SagaProgress nextProgress;

  /// Returned, **not persisted**.
  /// The caller must write it to its `InventoryRepository`; dropping this value silently loses the item.
  final InventoryItem? reward;
}

/// Marks a level complete, unlocks the next level and rolls boss rewards.
///
/// The reward rules are injected, not baked in. [bossRule] decides which levels
/// drop, [lootTable] decides what they drop from, and both default to the
/// package's own values — `const CompleteLevelUseCase()` behaves exactly as it
/// did before either existed. A host with its own economy passes its own two
/// and never touches this class (ADR-0003).
class CompleteLevelUseCase {
  const CompleteLevelUseCase({
    this.bossRule = isBossLevel,
    this.lootTable = kMvpLootTable,
  });

  /// Which levels drop a boss reward. Defaults to [isBossLevel].
  ///
  /// Consulted once per completion, before the first-clear guard.
  final SagaBossRule bossRule;

  /// Weighted table the reward is rolled from. Defaults to [kMvpLootTable].
  ///
  /// Must be non-empty, free of negative weights and total more than `0`;
  /// anything else throws an [ArgumentError] at roll time rather than falling
  /// back to the built-in table.
  final List<LootTableEntry> lootTable;

  /// Applies the completion transition for [levelId].
  ///
  /// [stars] is the score achieved this run. A previous better result is kept:
  /// replaying a level can raise its star count but never lower it.
  ///
  /// Progress only ever moves forward. Completing a level unlocks its successor
  /// whether or not a record for it already exists, and never demotes a level
  /// that is already completed.
  /// Set [enforceUnlockOrder] to reject completing a level the player has not
  /// reached yet. Off by default to preserve existing behaviour; a host that
  /// treats progression as authoritative should turn it on. When a level beyond
  /// [SagaProgress.currentMaxUnlockedLevelId] is completed with the guard on,
  /// the call is a no-op and returns the progress unchanged.
  CompleteLevelResult execute({
    required SagaProgress currentProgress,
    required int levelId,
    required int globalSeed,
    int stars = 1,
    bool enforceUnlockOrder = false,
    DateTime? now,
  }) {
    // Clamp rather than assert: an assert is stripped from release builds, so
    // it is no guard at all in production. A negative or absurd score coming
    // from a caller or a tampered save is coerced to a plausible range.
    final clampedStars =
        stars < 0 ? 0 : (stars > kMaxLevelStars ? kMaxLevelStars : stars);

    // Skipping ahead: with the guard on, only an already-reachable level may be
    // completed, closing the "complete any level id" arbitrary-skip path.
    if (enforceUnlockOrder &&
        levelId > currentProgress.currentMaxUnlockedLevelId) {
      return CompleteLevelResult(nextProgress: currentProgress);
    }

    final levels = Map<int, LevelProgress>.from(currentProgress.levels);
    final previous = levels[levelId];

    levels[levelId] = LevelProgress(
      levelId: levelId,
      state: LevelCompletionState.completed,
      // Keep the best run: overwriting would silently discard a three-star
      // result the moment the player replayed the level.
      stars: math.max(clampedStars, previous?.stars ?? 0),
      lastPlayedAt: now ?? DateTime.now(),
      extra: previous?.extra ?? const {},
    );

    final unlockLevelId = levelId + 1;
    final existingNext = levels[unlockLevelId];
    if (existingNext == null) {
      levels[unlockLevelId] = LevelProgress(
        levelId: unlockLevelId,
        state: LevelCompletionState.unlocked,
        stars: 0,
      );
    } else if (existingNext.state == LevelCompletionState.locked) {
      // A host that seeds every level as locked up front would otherwise keep
      // the successor locked forever, while currentMaxUnlockedLevelId claimed
      // it was open — the map would stop responding after one completion.
      levels[unlockLevelId] =
          existingNext.copyWith(state: LevelCompletionState.unlocked);
    }

    final currentUnlocked = currentProgress.currentMaxUnlockedLevelId;
    final nextProgress = currentProgress.copyWith(
      currentMaxUnlockedLevelId: math.max(unlockLevelId, currentUnlocked),
      levels: levels,
    );

    // Reward on first clear only. Without this, replaying a boss re-rolls the
    // (client-predictable) reward and mints a duplicate item every time, which
    // a host promoting inventory to a server would see as an integrity hole.
    final firstClear = previous?.state != LevelCompletionState.completed;
    if (!bossRule(levelId) || !firstClear) {
      return CompleteLevelResult(nextProgress: nextProgress);
    }

    return CompleteLevelResult(
      nextProgress: nextProgress,
      reward: rollBossReward(
        levelId: levelId,
        globalSeed: globalSeed,
        table: lootTable,
        now: now,
      ),
    );
  }
}
