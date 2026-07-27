import '../../core/data/repositories/saga_progress_repository.dart';
import '../../core/domain/models/saga_progress.dart';
import '../../core/domain/saga_seed_constants.dart';

/// In-memory [SagaProgressRepository] implementation for demos and tests.
class InMemorySagaProgressRepository implements SagaProgressRepository {
  SagaProgress _progress;
  final int _globalSeed;

  InMemorySagaProgressRepository({
    SagaProgress? initialProgress,
    int? globalSeed,
  })  : _progress = initialProgress ?? SagaProgress.initial(),
        _globalSeed = globalSeed ?? kDefaultSagaMapSeed;

  @override
  Future<int> loadGlobalSeed() async => _globalSeed;

  @override
  Future<SagaProgress> loadProgress() async => _progress;

  @override
  Future<void> saveProgress(SagaProgress progress) async {
    _progress = progress;
  }
}
