import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/level_progress.dart';
import '../../core/domain/models/resolved_saga_layout.dart';
import '../../core/domain/responsive/saga_map_responsive_config.dart';
import '../../core/domain/models/saga_geometry.dart';
import '../../core/domain/saga_map_coordinates.dart';
import '../painters/saga_path_geometry.dart';
import '../painters/saga_path_metrics.dart';

/// Resolves persisted progress for a level, or `null` when untracked.
typedef SagaNodeProgressResolver = LevelProgress? Function(LevelData level);

/// Everything a renderer needs to draw one chunk.
///
/// Owns the level-to-pixel conversion via [pixelFor] so every renderer — path
/// painter, node widgets, any host-supplied renderer — places geometry through
/// one code path and cannot drift apart.
class SagaMapRenderContext {
  final List<LevelData> levels;
  final int chunkIndex;

  /// Chunk box in pixels. Which dimension is the path axis is decided by
  /// [ResolvedSagaLayout.pathAxis].
  final SagaSize chunkSize;

  /// Normalized span this chunk covers along the path axis.
  final double chunkSpanNormalized;

  final ResolvedSagaLayout layout;
  final SagaNodeProgressResolver? progressResolver;

  /// Lateral band the levels were generated within, used to center the path.
  final SagaLateralBounds lateralBounds;

  /// Whether the path axis runs in reverse, as it does for a right-to-left
  /// horizontal map.
  final bool reverseAlongAxis;

  /// Inset at each end of the path axis, as a fraction of the chunk's
  /// along-axis extent. Range `0..0.24`.
  final double alongEdgeInsetFraction;

  /// Levels immediately before this chunk, in path order, so the last entry is
  /// the closest.
  ///
  /// Extends the drawn path past the leading edge, so it reads as continuous
  /// instead of restarting at every seam. Supply [kSagaPathNeighborCount] of
  /// them for a curved path: a curve's shape depends on its surroundings, and
  /// with fewer the two chunks sharing a seam would each draw a different
  /// version of the same segment.
  final List<LevelData> leadingNeighbors;

  /// Levels immediately after this chunk, in path order, so the first entry is
  /// the closest.
  ///
  /// These do the visible work at a seam: the segment from this chunk's last
  /// level onward lands inside this chunk's box and meets the next chunk's path
  /// at the shared edge.
  final List<LevelData> trailingNeighbors;

  /// Path roundness, `0` for straight lines up to `1` for a fully rounded
  /// spline. Values outside the range are clamped.
  final double pathCurvature;

  /// How far along the path the player has reached, as a fractional level
  /// index. `null` paints the whole path in one style.
  final double? pathProgressPosition;

  // Not const: the context caches arc-length measurements after construction,
  // and nothing constructs it as a constant.
  SagaMapRenderContext({
    required this.levels,
    required this.chunkIndex,
    required this.chunkSize,
    required this.chunkSpanNormalized,
    required this.layout,
    this.progressResolver,
    this.lateralBounds = SagaLateralBounds.unit,
    this.reverseAlongAxis = false,
    this.alongEdgeInsetFraction = 0.0,
    this.leadingNeighbors = const <LevelData>[],
    this.trailingNeighbors = const <LevelData>[],
    this.pathCurvature = 0.0,
    this.pathProgressPosition,
  });

  /// Chunk-local pixel position for [level].
  ///
  /// Pass `clampAlongAxis: false` for a neighboring chunk's level, to resolve a
  /// point beyond this chunk's bounds without snapping it to the edge.
  SagaPoint pixelFor(SagaPoint point, {bool clampAlongAxis = true}) {
    return SagaMapCoordinates.levelToChunkPixel(
      point,
      chunkIndex,
      chunkSpanNormalized,
      chunkSize,
      pathAxis: layout.pathAxis,
      alongEdgeInsetFraction: alongEdgeInsetFraction,
      lateralBounds: lateralBounds,
      lateralPaddingPx: layout.cameraPadding,
      reverseAlongAxis: reverseAlongAxis,
      clampAlongAxis: clampAlongAxis,
    );
  }

  /// Pixel polyline for this chunk's path, in chunk-local coordinates.
  ///
  /// Bracketed by [leadingNeighbor] and [trailingNeighbor] where known, so the
  /// line runs past the chunk's edges and is clipped there rather than stopping
  /// short. Without them the path would visibly break at every chunk seam.
  List<SagaPoint> pathPoints() {
    return <SagaPoint>[
      for (final level in leadingNeighbors)
        pixelFor(level.position, clampAlongAxis: false),
      for (final level in levels) pixelFor(level.position),
      for (final level in trailingNeighbors)
        pixelFor(level.position, clampAlongAxis: false),
    ];
  }

  /// Cubic pieces for this chunk's path, honouring [pathCurvature].
  List<SagaPathSegment> pathSegments() {
    return buildSagaPathSegments(pathPoints(), curvature: pathCurvature);
  }

  /// Arc-length measurements over this chunk's path.
  ///
  /// Built lazily and held for the life of the context, which lasts one build:
  /// sampling the curve on every frame would defeat the purpose.
  late final SagaPathMetrics pathMetrics = SagaPathMetrics(pathSegments());

  /// Index into [pathPoints] for the level numbered [levelId].
  ///
  /// Returns `null` when the level is outside what this chunk can see, which
  /// includes its neighbours.
  int? pointIndexForLevel(int levelId) {
    if (levels.isEmpty) return null;
    final index = leadingNeighbors.length + (levelId - levels.first.id);
    final total = leadingNeighbors.length + levels.length +
        trailingNeighbors.length;
    return index >= 0 && index < total ? index : null;
  }

  /// Pose of something standing at [pathPosition], a fractional level index.
  ///
  /// `3.5` means halfway between levels 3 and 4 *by distance along the drawn
  /// path*, so a character crossing it moves at an even pace even where the
  /// curve is tight.
  ///
  /// Returns `null` when the position falls outside this chunk's reach. Callers
  /// use that to decide which chunk should draw the character.
  SagaPathPose? poseAtPathPosition(double pathPosition) {
    final segments = pathMetrics.segments;
    if (segments.isEmpty) return null;

    final baseLevel = pathPosition.floor();
    final index = pointIndexForLevel(baseLevel);
    if (index == null || index < 0 || index >= segments.length) return null;

    return pathMetrics.poseOnSegment(index, pathPosition - baseLevel);
  }

  /// The path split into the stretch already covered and the stretch ahead.
  ///
  /// The cut subdivides the cubic straddling the progress point, so the halves
  /// meet exactly; resampling instead would leave a visible notch where the
  /// colours change.
  ({List<SagaPathSegment> walked, List<SagaPathSegment> upcoming})
      splitPathAtProgress() {
    final segments = pathSegments();
    final progress = pathProgressPosition;
    if (progress == null || segments.isEmpty) {
      return (walked: const <SagaPathSegment>[], upcoming: segments);
    }

    final baseLevel = progress.floor();
    final index = pointIndexForLevel(baseLevel);

    if (index == null) {
      // Entirely behind this chunk, or entirely past it.
      final firstVisible = leadingNeighbors.isNotEmpty
          ? leadingNeighbors.first.id
          : levels.first.id;
      return progress < firstVisible
          ? (walked: const <SagaPathSegment>[], upcoming: segments)
          : (walked: segments, upcoming: const <SagaPathSegment>[]);
    }
    if (index >= segments.length) {
      return (walked: segments, upcoming: const <SagaPathSegment>[]);
    }

    final t = pathMetrics.tAtFraction(index, progress - baseLevel);
    final split = segments[index].splitAt(t);

    return (
      walked: <SagaPathSegment>[...segments.take(index), split.before],
      upcoming: <SagaPathSegment>[split.after, ...segments.skip(index + 1)],
    );
  }

  /// Anchor point for a decoration placed at [chunkFraction] of the chunk box.
  
  /// Anchor point for a decoration spanning the given [levelId].
  ///
  /// The point is centered on the lateral axis and aligned with the level on the path axis.
  /// Returns `null` if the level is not found in this chunk.
  SagaPoint? decorationPixelAtLevel(int levelId) {
    final level = levels.where((l) => l.id == levelId).firstOrNull;
    if (level == null) return null;
    
    final point = pixelFor(level.position);
    if (layout.pathAxis == SagaMapPathAxis.vertical) {
      return SagaPoint(chunkSize.width / 2, point.y);
    } else {
      return SagaPoint(point.x, chunkSize.height / 2);
    }
  }

  SagaPoint decorationPixelAtFraction(double fx, double fy) {
    return SagaPoint(fx * chunkSize.width, fy * chunkSize.height);
  }

  /// Anchor point for a decoration hugging the path at [pathPosition], pushed
  /// [lateralOffset] pixels along the lateral (cross) axis.
  ///
  /// Returns `null` when the position is beyond this chunk's reach.
  SagaPoint? decorationPixelBesidePath(
    double pathPosition,
    double lateralOffset,
  ) {
    final point = characterPixel(pathPosition);
    if (point == null) return null;
    // Lateral is x on a vertical map, y on a horizontal one — the axis the
    // path zig-zags across.
    return layout.pathAxis == SagaMapPathAxis.vertical
        ? SagaPoint(point.x + lateralOffset, point.y)
        : SagaPoint(point.x, point.y + lateralOffset);
  }

  /// Whether this chunk is the one responsible for drawing [pathPosition].
  ///
  /// A chunk can *resolve* positions inside its neighbours too, since it holds
  /// their levels to keep the path smooth across a seam. Without a single owner
  /// both chunks either side of a seam would draw the same character, so
  /// ownership is decided by this chunk's own levels alone.
  bool ownsPathPosition(double pathPosition) {
    if (levels.isEmpty) return false;
    final level = pathPosition.floor();
    return level >= levels.first.id && level <= levels.last.id;
  }

  /// Pixel position of something standing at [pathPosition].
  SagaPoint? characterPixel(double pathPosition) =>
      poseAtPathPosition(pathPosition)?.position;

  LevelProgress? resolveProgress(LevelData level) {
    return progressResolver?.call(level);
  }

  /// Returns a copy bound to a different chunk pixel box.
  SagaMapRenderContext withChunkSize(SagaSize size) {
    if (size == chunkSize) return this;
    return SagaMapRenderContext(
      levels: levels,
      chunkIndex: chunkIndex,
      chunkSize: size,
      chunkSpanNormalized: chunkSpanNormalized,
      layout: layout,
      progressResolver: progressResolver,
      lateralBounds: lateralBounds,
      reverseAlongAxis: reverseAlongAxis,
      alongEdgeInsetFraction: alongEdgeInsetFraction,
      leadingNeighbors: leadingNeighbors,
      trailingNeighbors: trailingNeighbors,
      pathCurvature: pathCurvature,
      pathProgressPosition: pathProgressPosition,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SagaMapRenderContext &&
        identical(other.levels, levels) &&
        other.chunkIndex == chunkIndex &&
        other.chunkSize == chunkSize &&
        other.chunkSpanNormalized == chunkSpanNormalized &&
        other.layout == layout &&
        other.progressResolver == progressResolver &&
        other.lateralBounds == lateralBounds &&
        other.reverseAlongAxis == reverseAlongAxis &&
        other.alongEdgeInsetFraction == alongEdgeInsetFraction &&
        other.pathCurvature == pathCurvature &&
        other.pathProgressPosition == pathProgressPosition &&
        _sameLevels(other.leadingNeighbors, leadingNeighbors) &&
        _sameLevels(other.trailingNeighbors, trailingNeighbors);
  }

  @override
  int get hashCode => Object.hash(
        identityHashCode(levels),
        chunkIndex,
        chunkSize,
        chunkSpanNormalized,
        layout,
        progressResolver,
        lateralBounds,
        reverseAlongAxis,
        alongEdgeInsetFraction,
        pathCurvature,
        pathProgressPosition,
        Object.hashAll(leadingNeighbors),
        Object.hashAll(trailingNeighbors),
      );

  static bool _sameLevels(List<LevelData> a, List<LevelData> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
