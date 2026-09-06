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
  Future<void> saveGlobalSeed(int seed);
}
