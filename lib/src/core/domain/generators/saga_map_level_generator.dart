import '../models/level_data.dart';
import '../models/saga_geometry.dart';
import '../models/saga_map_config.dart';
import '../saga_stable_hash.dart';
import 'level_generator.dart';

/// Default implementation that generates deterministic zig-zag map paths.
///
/// Each level is derived from `(globalSeed, levelId)` alone, so generating a
/// chunk costs the same whether it is the first or the ten-thousandth. The
/// previous implementation replayed the random sequence from level zero on
/// every call, making deep chunks progressively more expensive to load.
class SagaMapLevelGenerator implements LevelGenerator {
  const SagaMapLevelGenerator();

  @override

  /// Builds level data from a seed and geometry config.
  List<LevelData> generateLevels({
    required int globalSeed,
    required SagaMapConfig config,
    required int startLevelId,
    required int count,
  }) {
    assert(count >= 0, 'count must not be negative');
    // A runtime guard, not an assert: `% biomeIds.length` on an empty list is
    // an integer division by zero, and asserts are stripped from release
    // builds, which is precisely where a host's own list arrives.
    if (config.biomeIds.isEmpty) {
      throw ArgumentError.value(
        config.biomeIds,
        'config.biomeIds',
        'must not be empty',
      );
    }
    // Same reasoning, same fix: `biomeSpan` is the divisor in
    // `levelId ~/ config.biomeSpan`, so a non-positive value is an integer
    // division by zero (or, for a negative span, silently wrong biomes) exactly
    // where the constructor's assert is stripped — release builds.
    if (config.biomeSpan <= 0) {
      throw ArgumentError.value(
        config.biomeSpan,
        'config.biomeSpan',
        'must be greater than 0',
      );
    }

    final mid = (config.minX + config.maxX) / 2;
    final bandHalf = (config.maxX - config.minX) / 4;
    final jitterMax = (config.maxX - config.minX) * 0.1;

    return List<LevelData>.generate(
      count,
      (offset) {
        final levelId = startLevelId + offset;

        // Alternating lateral targets, nudged by a per-level jitter.
        final target = levelId.isEven ? mid - bandHalf : mid + bandHalf;
        final jitter =
            _unitJitter(globalSeed, levelId) * 2 * jitterMax - jitterMax;
        final lateral = (target + jitter).clamp(config.minX, config.maxX);

        // Computed rather than accumulated: repeated addition drifts, and the
        // renderer compares this against a multiplied chunk origin.
        final along = levelId * config.stepHeight;

        final biomeIndex = levelId ~/ config.biomeSpan;

        return LevelData(
          id: levelId,
          position: SagaPoint(lateral, along),
          biomeId: config.biomeIds[biomeIndex % config.biomeIds.length],
          difficulty: 1 + (levelId % 5),
        );
      },
      growable: false,
    );
  }

  /// Deterministic `0..1` value for one level, independent of any other level
  /// and stable across program runs.
  double _unitJitter(int globalSeed, int levelId) {
    return stableUnitValue([globalSeed, levelId]);
  }
}
