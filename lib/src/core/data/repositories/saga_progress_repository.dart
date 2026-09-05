import '../../domain/models/saga_progress.dart';

/// Persistence contract for map progression state.
abstract interface class SagaProgressRepository {
  /// Loads current progression state.
  Future<SagaProgress> loadProgress();

  /// Saves progression state.
  Future<void> saveProgress(SagaProgress progress);

  /// Loads global map seed used for deterministic generation.
  /// Implementations must not persist as a side effect of loading.
  Future<int> loadGlobalSeed();
}
