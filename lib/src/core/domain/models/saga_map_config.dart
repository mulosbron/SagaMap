import '../biome_ids.dart';
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

  /// Biome ids the generator cycles through, in order.
  ///
  /// Defaults to the built-in three, [kSagaBiomeIds]. A host with its own
  /// realms passes its own list and stops maintaining a parallel one.
  ///
  /// [biomeSpan] sets how many levels each id covers; the list length sets how
  /// many ids there are. The full cycle closes after
  /// `biomeSpan * biomeIds.length` levels:
  ///
  /// | `biomeSpan` | `biomeIds.length` | biome changes every | cycle closes at |
  /// | --- | --- | --- | --- |
  /// | 50 | 3 (default) | 50 levels | 150 levels |
  /// | 5 | 10 | 5 levels | 50 levels |
  /// | 1 | 4 | every level | 4 levels |
  /// | 50 | 1 | never | never |
  ///
  /// Must not be empty: the generator indexes it modulo its length, and an
  /// empty list is a division by zero. `SagaMapLevelGenerator` throws an
  /// [ArgumentError] for one. The check lives there rather than in this
  /// constructor because a `const` constructor cannot inspect a list, and an
  /// assert would be stripped from exactly the release builds a host's own
  /// list arrives in.
  ///
  /// Duplicate ids are allowed and are not deduplicated — repeating an id is
  /// how you weight one biome more heavily, as in
  /// `[forest, forest, desert]`. Each slot is one [biomeSpan] stretch.
  ///
  /// Ids the theme resolver does not recognise fall back to its default theme;
  /// see [SagaBiomeThemeResolver].
  final List<String> biomeIds;

  const SagaMapConfig({
    required this.minX,
    required this.maxX,
    required this.stepHeight,
    required this.biomeSpan,
    this.biomeIds = kSagaBiomeIds,
  }) : assert(biomeSpan > 0, 'biomeSpan must be greater than 0');

  /// A copy with the given fields replaced.
  ///
  /// The usual way to reach [biomeIds] without restating the geometry:
  /// `SagaMapConfig.defaultConfig.copyWith(biomeIds: myRealms)`.
  SagaMapConfig copyWith({
    double? minX,
    double? maxX,
    double? stepHeight,
    int? biomeSpan,
    List<String>? biomeIds,
  }) {
    return SagaMapConfig(
      minX: minX ?? this.minX,
      maxX: maxX ?? this.maxX,
      stepHeight: stepHeight ?? this.stepHeight,
      biomeSpan: biomeSpan ?? this.biomeSpan,
      biomeIds: biomeIds ?? this.biomeIds,
    );
  }

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
    // Guarded at runtime, not only asserted. This value is handed straight to
    // `chunkSpanNormalized`, where it is a divisor: a non-positive count
    // produces a zero or negative span, and in release — where the assert is
    // gone — that surfaces as NaN coordinates far from here. The message names
    // `levelCount`, the argument the caller actually passed; the release error
    // used to name `chunkSpanNormalized` and send hosts looking at the wrong
    // field.
    if (levelCount <= 0) {
      throw ArgumentError.value(
        levelCount,
        'levelCount',
        'must be greater than 0',
      );
    }
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
