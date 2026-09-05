import '../models/level_data.dart';
import '../models/saga_map_config.dart';

/// Contract for deterministic level generation implementations.
abstract class LevelGenerator {
  /// Generates a contiguous list of levels for a map segment.
  /// `startLevelId` is zero-based.
  List<LevelData> generateLevels({
    required int globalSeed,
    required SagaMapConfig config,
    required int startLevelId,
    required int count,
  });
}
