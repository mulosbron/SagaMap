import 'dart:math' as math;

import '../../data/repositories/inventory_repository.dart';
import '../loot_table.dart';
import '../models/inventory_item.dart';
import '../models/level_progress.dart';
import '../models/saga_progress.dart';
import '../pity_rule.dart';

/// What [CompleteLevelUseCase.execute] did with the request.
enum CompleteLevelOutcome {
  /// The completion was applied and nothing blocked the successor.
  applied,

  /// `enforceUnlockOrder` rejected the level as unreached; nothing changed.
  rejectedUnreached,

  /// The completion was applied, but `canUnlock` refused to open the successor.
  appliedUnlockBlocked,
}

/// Result object returned by [CompleteLevelUseCase.execute].
class CompleteLevelResult {
  const CompleteLevelResult({
    required this.nextProgress,
    this.reward,
    this.unlockBlocked = false,
    this.outcome = CompleteLevelOutcome.applied,
    this.rewardPersisted = false,
  });

  final SagaProgress nextProgress;

  /// The boss reward this completion minted, or `null`.
  ///
  /// From [CompleteLevelUseCase.execute] it is returned, **not persisted**:
  /// the caller must write it to its `InventoryRepository`, and dropping this
  /// value silently loses the item. [CompleteLevelUseCase.executeAndPersist]
  /// writes it for you and says so through [rewardPersisted].
  ///
  /// Minted on first clear only, decided from the [SagaProgress] passed in.
  /// That snapshot *is* the guard: two calls made against the same
  /// `currentProgress` — a widget callback and an async persistence path, say
  /// — both see an uncompleted level and both mint the same item. That is as
  /// true of `executeAndPersist` as of `execute`: owning the write closes the
  /// dropped-value hole, not this one. Thread each result's [nextProgress]
  /// into the next call, or serialise completions per level.
  final InventoryItem? reward;

  /// The level completed, but `canUnlock` refused to open its successor.
  ///
  /// Without reading this a host cannot tell "you finished the level" from
  /// "you finished the level and the road ahead is still shut" — both look
  /// like a completion that went nowhere. Read it to show the player why:
  /// a closed gate, an unbought chapter, a locked episode.
  ///
  /// Always `false` when no `canUnlock` is injected.
  final bool unlockBlocked;

  /// Categorises what happened, so a host can tell a refusal from a success.
  ///
  /// [CompleteLevelOutcome.rejectedUnreached] is the case [unlockBlocked]
  /// cannot express: `enforceUnlockOrder` refused the level as unreached, so
  /// nothing was applied and the progress is returned unchanged.
  /// [CompleteLevelOutcome.appliedUnlockBlocked] is a completion whose
  /// successor stayed shut — [unlockBlocked] is exactly
  /// `outcome == CompleteLevelOutcome.appliedUnlockBlocked`.
  final CompleteLevelOutcome outcome;

  /// Whether [reward] was written to the use case's `inventory`.
  ///
  /// Only [CompleteLevelUseCase.executeAndPersist] sets it, and only when
  /// there was a reward to write. From `execute` it is always `false`:
  /// `execute` is synchronous and never writes, even with an `inventory`
  /// injected.
  final bool rewardPersisted;
}

/// Marks a level complete, unlocks the next level and rolls boss rewards.
///
/// The reward rules are injected, not baked in. [bossRule] decides which levels
/// drop, [lootTable] decides what they drop from, [pityRule] adds a bad-luck
/// guarantee, and [inventory] is where [executeAndPersist] writes the result.
/// Every one of them defaults to the package's own behaviour —
/// `const CompleteLevelUseCase()` behaves exactly as it did before any of them
/// existed. A host with its own economy passes its own and never touches this
/// class (ADR-0003).
class CompleteLevelUseCase {
  const CompleteLevelUseCase({
    this.bossRule = isBossLevel,
    this.lootTable = kMvpLootTable,
    this.canUnlock,
    this.enforceUnlockOrder = true,
    this.pityRule,
    this.inventory,
  });

  /// Whether a level the player has not reached may be completed at all.
  ///
  /// **On by default since 2.0.0.** It used to be an `execute` parameter
  /// defaulting to `false`, which made the shipped configuration accept any
  /// level id — and made the guard something a host had to remember at every
  /// call site. One omission among five re-opened the hole. As a constructor
  /// field it is decided once, next to [canUnlock], and covers every call the
  /// instance serves.
  ///
  /// Turn it off for a level select that deliberately jumps ahead (a debug
  /// build, a chapter-skip purchase), and prefer overriding it on the single
  /// [execute] call that means it rather than on the instance.
  final bool enforceUnlockOrder;

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

  /// Vetoes unlocking the successor. Given the id about to be unlocked,
  /// returning `false` completes the level but leaves the next one shut — the
  /// gate stays closed.
  ///
  /// `null`, the default, is 1.x behaviour: the successor always unlocks.
  ///
  /// This and [execute]'s `enforceUnlockOrder` guard opposite directions.
  /// `enforceUnlockOrder` looks backwards and rejects completing a level the
  /// player has not reached; `canUnlock` looks forwards and refuses to open
  /// the one after. A host can use either, both or neither.
  ///
  /// A veto does not undo the completion: the level's own record still becomes
  /// [LevelCompletionState.completed], and a boss reward still drops, because
  /// the player did clear it. Only the successor and
  /// [SagaProgress.currentMaxUnlockedLevelId] stand still, and
  /// [CompleteLevelResult.unlockBlocked] says so.
  ///
  /// Derive it from the same predicate as
  /// `SagaNodeInteractionPolicy.isReachable`, so a node the player can tap is
  /// never a node whose successor silently refuses to open.
  final bool Function(int levelId)? canUnlock;

  /// Bad-luck protection for boss rewards. `null`, the default, rolls exactly
  /// as 2.0.0 did.
  ///
  /// The rule is decided here, once, like the rest of the economy. The counter
  /// it reads is save data, so it arrives per call as [execute]'s
  /// `pityCounter`; after a reward, store
  /// `pityRule.nextCounter(counter, reward.rarity)`. See [rollBossReward] for
  /// what a guaranteed roll draws from.
  final SagaPityRule? pityRule;

  /// Where [executeAndPersist] writes the boss reward. `null` by default.
  ///
  /// When supplied, the rolled reward is written here before the result
  /// returns. [execute] ignores it: the repository is asynchronous and
  /// `execute` is not, and turning `execute` into a `Future` would break every
  /// caller for a write most of them already make themselves. The write
  /// therefore has its own entry point rather than a flag on the old one.
  final InventoryRepository? inventory;

  /// Applies the completion transition for [levelId].
  ///
  /// [stars] is the score achieved this run. A previous better result is kept:
  /// replaying a level can raise its star count but never lower it.
  ///
  /// Progress only ever moves forward. Completing a level unlocks its successor
  /// whether or not a record for it already exists, and never demotes a level
  /// that is already completed.
  /// Pass `enforceUnlockOrder` to override the instance's own
  /// [CompleteLevelUseCase.enforceUnlockOrder] for this one call. When the
  /// guard is on and a level beyond
  /// [SagaProgress.currentMaxUnlockedLevelId] is completed, the call is a
  /// no-op: the progress comes back unchanged and the outcome is
  /// [CompleteLevelOutcome.rejectedUnreached].
  ///
  /// A negative [levelId] is rejected the same way whatever the guard says. A
  /// level below zero is an impossible state in every configuration, so there
  /// is no setting under which writing one is correct.
  ///
  /// [pityCounter] is the host's stored count of boss rewards in a row below
  /// [pityRule]'s guaranteed rarity. Without a [pityRule] it is ignored.
  ///
  /// [modeId] names an alternate replay mode; `null`, the default, is the
  /// normal game. A mode run records its score in [LevelProgress.starsByMode]
  /// under [modeId] — keeping the best, as [stars] does — and changes nothing
  /// that matters to progression:
  ///
  /// - **It never unlocks.** The successor,
  ///   [SagaProgress.currentMaxUnlockedLevelId], and the level's own state and
  ///   [LevelProgress.stars] are left as they were, and [canUnlock] is not
  ///   consulted. Otherwise clearing a level on "hard" would open the next one
  ///   a second time, and a mode meant to be optional would become a second
  ///   road through the map.
  /// - **It never drops a boss reward.** The reward belongs to the first
  ///   clear, and the first clear is the default mode's; rolling again for a
  ///   mode would mint a second item for the same boss.
  ///
  /// The order guard still applies, so a mode run on a level the player has
  /// not reached is rejected like any other. Whether a mode also requires the
  /// default clear first is the host's rule, not this method's. A [modeId]
  /// that names the default mode throws an [ArgumentError]; see
  /// [LevelProgress.checkModeId].
  ///
  /// **Call this against the latest progress you hold.** The first-clear guard
  /// that stops a boss reward being minted twice is read from
  /// [currentProgress]; two calls made against the same snapshot both see an
  /// uncompleted level and both mint. See [CompleteLevelResult.reward].
  CompleteLevelResult execute({
    required SagaProgress currentProgress,
    required int levelId,
    required int globalSeed,
    int stars = 1,
    bool? enforceUnlockOrder,
    DateTime? now,
    int pityCounter = 0,
    String? modeId,
  }) {
    if (modeId != null) LevelProgress.checkModeId(modeId);
    final orderEnforced = enforceUnlockOrder ?? this.enforceUnlockOrder;

    // A negative level is an impossible state in every configuration — the
    // same reasoning `SagaProgress.fromJson` applies to a negative unlock
    // pointer — so it is refused whatever the order guard says.
    if (levelId < 0) {
      return CompleteLevelResult(
        nextProgress: currentProgress,
        outcome: CompleteLevelOutcome.rejectedUnreached,
      );
    }
    // Clamp rather than assert: an assert is stripped from release builds, so
    // it is no guard at all in production. A negative or absurd score coming
    // from a caller or a tampered save is coerced to a plausible range.
    final clampedStars =
        stars < 0 ? 0 : (stars > kMaxLevelStars ? kMaxLevelStars : stars);

    // Skipping ahead: with the guard on, only an already-reachable level may be
    // completed, closing the "complete any level id" arbitrary-skip path.
    if (orderEnforced && levelId > currentProgress.currentMaxUnlockedLevelId) {
      return CompleteLevelResult(
        nextProgress: currentProgress,
        outcome: CompleteLevelOutcome.rejectedUnreached,
      );
    }

    if (modeId != null) {
      return CompleteLevelResult(
        nextProgress: _recordModeRun(
          currentProgress: currentProgress,
          levelId: levelId,
          modeId: modeId,
          stars: clampedStars,
          now: now,
        ),
      );
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
      starsByMode: previous?.starsByMode ?? const {},
    );

    final unlockLevelId = levelId + 1;
    // The gate is asked once, about the level it would open. A veto leaves the
    // successor exactly as it was — it is not demoted, because a gate closing
    // behind a player who already passed it would erase real progress.
    final unlockBlocked = !(canUnlock?.call(unlockLevelId) ?? true);

    if (!unlockBlocked) {
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
    }

    final currentUnlocked = currentProgress.currentMaxUnlockedLevelId;
    final nextProgress = currentProgress.copyWith(
      currentMaxUnlockedLevelId: unlockBlocked
          ? currentUnlocked
          : math.max(unlockLevelId, currentUnlocked),
      levels: levels,
    );

    // Reward on first clear only. Without this, replaying a boss re-rolls the
    // (client-predictable) reward and mints a duplicate item every time, which
    // a host promoting inventory to a server would see as an integrity hole.
    final firstClear = previous?.state != LevelCompletionState.completed;
    final outcome = unlockBlocked
        ? CompleteLevelOutcome.appliedUnlockBlocked
        : CompleteLevelOutcome.applied;
    if (!bossRule(levelId) || !firstClear) {
      return CompleteLevelResult(
        nextProgress: nextProgress,
        unlockBlocked: unlockBlocked,
        outcome: outcome,
      );
    }

    return CompleteLevelResult(
      nextProgress: nextProgress,
      unlockBlocked: unlockBlocked,
      outcome: outcome,
      reward: rollBossReward(
        levelId: levelId,
        globalSeed: globalSeed,
        table: lootTable,
        now: now,
        pityCounter: pityCounter,
        pityRule: pityRule,
      ),
    );
  }

  /// [execute], then writes the reward to [inventory] before returning.
  ///
  /// Takes exactly [execute]'s parameters and applies exactly its rules — the
  /// order guard, the first-clear guard, pity, replay modes — so a completion
  /// that mints nothing writes nothing, and replaying a cleared boss against
  /// the progress the first clear returned does not write a second item.
  ///
  /// **If the write throws, the exception propagates and no result is
  /// returned.** Treat the completion as not having happened: there is no
  /// `nextProgress` to persist, so a host that saves progress only after this
  /// future completes never records a clear whose reward was lost. The package
  /// cannot make the reward write and the progress save one transaction —
  /// they are two stores it does not own — so atomicity across them is the
  /// host's to build. Writing the reward first means a crash between the two
  /// leaves an item the player earned rather than a clear with nothing to
  /// show for it; it also means a retry against the old progress mints the
  /// same item again, which a host that cannot tolerate it checks for.
  ///
  /// Throws a [StateError] when no [inventory] was injected: a method named
  /// for persisting that silently did not persist is the bug this entry point
  /// exists to remove.
  Future<CompleteLevelResult> executeAndPersist({
    required SagaProgress currentProgress,
    required int levelId,
    required int globalSeed,
    int stars = 1,
    bool? enforceUnlockOrder,
    DateTime? now,
    int pityCounter = 0,
    String? modeId,
  }) async {
    final repository = inventory;
    if (repository == null) {
      throw StateError(
        'executeAndPersist needs an inventory. Pass one to the '
        'CompleteLevelUseCase constructor, or call execute and write '
        'CompleteLevelResult.reward yourself.',
      );
    }

    final result = execute(
      currentProgress: currentProgress,
      levelId: levelId,
      globalSeed: globalSeed,
      stars: stars,
      enforceUnlockOrder: enforceUnlockOrder,
      now: now,
      pityCounter: pityCounter,
      modeId: modeId,
    );
    final reward = result.reward;
    if (reward == null) return result;

    await repository.addItem(reward);
    return CompleteLevelResult(
      nextProgress: result.nextProgress,
      reward: reward,
      unlockBlocked: result.unlockBlocked,
      outcome: result.outcome,
      rewardPersisted: true,
    );
  }

  SagaProgress _recordModeRun({
    required SagaProgress currentProgress,
    required int levelId,
    required String modeId,
    required int stars,
    required DateTime? now,
  }) {
    final levels = Map<int, LevelProgress>.from(currentProgress.levels);
    final previous = levels[levelId];

    levels[levelId] = LevelProgress(
      levelId: levelId,
      // A mode run never changes what is reachable. With no record to keep, the
      // state is the one the pointer already implies, so writing the record
      // cannot open a level the default game has not.
      state: previous?.state ??
          (levelId <= currentProgress.currentMaxUnlockedLevelId
              ? LevelCompletionState.unlocked
              : LevelCompletionState.locked),
      stars: previous?.stars ?? 0,
      lastPlayedAt: now ?? DateTime.now(),
      extra: previous?.extra ?? const {},
      starsByMode: {
        ...?previous?.starsByMode,
        // The same "best run stays" rule as the default score.
        modeId: math.max(stars, previous?.starsByMode[modeId] ?? 0),
      },
    );

    return currentProgress.copyWith(levels: levels);
  }
}
