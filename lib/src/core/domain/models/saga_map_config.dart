import 'saga_geometry.dart';

/// Geometry parameters used by [SagaMapLevelGenerator].
class SagaMapConfig {
  /// Lower bound of the lateral zig-zag band, normalized `0..1`.
  final double minX;

  /// Upper bound of the lateral zig-zag band, normalized `0..1`.
  final double maxX;

  /// Normalized distance the path advances per level, along the path axis.
  final double stepHeight;

  /// Number of levels before the biome cycles. Must be positive — the
  /// generator uses it as a divisor (`levelId ~/ biomeSpan`), so `0` is an
  /// integer division-by-zero.
  final int biomeSpan;

  const SagaMapConfig({
    required this.minX,
    required this.maxX,
    required this.stepHeight,
    required this.biomeSpan,
  }) : assert(biomeSpan > 0, 'biomeSpan must be greater than 0');

  /// Lateral band this config generates levels within.
  ///
  /// Pass to `MapChunkWidget.lateralBounds` so the rendered band is centered
  /// identically in every chunk.
  SagaLateralBounds get lateralBounds =>
      SagaLateralBounds(min: minX, max: maxX);

  /// Normalized span covered by [levelCount] consecutive levels.
  ///
  /// This is the value a chunk's `chunkSpanNormalized` must carry: a chunk
  /// holding `n` levels spans `stepHeight * n`. Supplying anything else silently
  /// pushes out-of-range levels onto the chunk edge.
  double spanForLevelCount(int levelCount) {
    assert(levelCount > 0, 'levelCount must be greater than 0');
    return stepHeight * levelCount;
  }

  /// Sensible defaults for casual world-map progression paths.
  static const SagaMapConfig defaultConfig = SagaMapConfig(
    minX: 0.2,
    maxX: 0.8,
    stepHeight: 0.08,
    biomeSpan: 50,
  );
}
