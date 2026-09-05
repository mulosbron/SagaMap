import '../../domain/models/saga_progress.dart';

/// Persistence contract for map progression state.
/// 
/// Note: The decision to keep reader and writer methods in a single interface
/// is documented in ADR-0004.
abstract interface class SagaProgressRepository {
  /// Loads current progression state.
  Future<SagaProgress> loadProgress();

  /// Saves progression state.
  Future<void> saveProgress(SagaProgress progress);

  /// Loads global map seed used for deterministic generation.
  /// 
  /// Implementations must not persist as a side effect of loading.
  Future<int> loadGlobalSeed();

  /// Persists the global map seed.
  ///
  /// Changing a stored seed regenerates the whole map: level positions,
  /// biomes and boss rewards all derive from it.
  ///
  /// Existing [SagaProgress] keeps its level ids but those ids now point
  /// at different terrain.
  Future<void> saveGlobalSeed(int seed);
}
