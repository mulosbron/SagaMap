import '../../domain/models/saga_progress.dart';

/// Persistence contract for map progression state.
///
/// Reads and writes share one interface. Splitting it into a `Reader` and a
/// `Writer` role was considered and rejected; the reasoning is in ADR-0004 and
/// is not repeated here.
abstract interface class SagaProgressRepository {
  /// Loads current progression state.
  Future<SagaProgress> loadProgress();

  /// Saves progression state.
  Future<void> saveProgress(SagaProgress progress);

  /// Loads global map seed used for deterministic generation.
  ///
  /// Implementations must not persist as a side effect of loading. Writing a
  /// default seed on first read makes "load" mean "load, and possibly change
  /// the whole map" — use [saveGlobalSeed] for that write instead.
  Future<int> loadGlobalSeed();

  /// Persists the global map seed.
  ///
  /// Changing a stored seed regenerates the whole map: level positions,
  /// biomes and boss rewards all derive from it.
  ///
  /// Existing [SagaProgress] keeps its level ids but those ids now point
  /// at different terrain — level 12 is still complete, and it is no longer
  /// the same level 12.
  ///
  /// ## Trust boundary
  ///
  /// **Client-rolled loot is advisory, not authoritative.** A boss reward is a
  /// pure function of `(levelId, globalSeed, table)`, and this method makes the
  /// seed writable. A player who can reach the stored seed can compute, offline
  /// and before clearing the boss, which seed drops the item they want — then
  /// write that seed and clear it.
  ///
  /// That is not a defect to be patched; it is what determinism costs on a
  /// device the player owns. The package keeps determinism, because the same
  /// seed yielding the same world is what makes a bug reproducible and a
  /// golden test stable (ADR-0009).
  ///
  /// So: a host that promotes inventory to a server must roll the reward on
  /// that server and treat `rollBossReward` as a preview. A host whose
  /// inventory never leaves the device has nothing to defend and can ignore
  /// this entirely.
  Future<void> saveGlobalSeed(int seed);
}
