import 'models/saga_geometry.dart';
import 'responsive/saga_map_responsive_config.dart';

/// Coordinate conversion helpers for map rendering.
///
/// Level positions are stored axis-agnostically: [SagaPoint.y] advances *along*
/// the path and [SagaPoint.x] is the *lateral* zig-zag. [SagaMapPathAxis] then
/// decides which screen axis each one lands on. Nothing in this class assumes
/// the path runs vertically.
class SagaMapCoordinates {
  SagaMapCoordinates._();

  /// Default inset at each end of a chunk's path axis, as a fraction of the
  /// chunk's along-axis extent.
  ///
  /// Reserves room for the node radius so end nodes are not clipped. Note that
  /// a non-zero inset also opens a visible seam between consecutive chunks
  /// unless the renderer bridges it.
  static const double kDefaultAlongEdgeInsetFraction = 0.08;

  /// Hard cap on [kDefaultAlongEdgeInsetFraction]; beyond this the usable span
  /// collapses.
  static const double kMaxAlongEdgeInsetFraction = 0.24;

  /// Converts a normalized position (`0..1`) to pixel coordinates.
  static SagaPoint toPixel(SagaPoint normalized, SagaSize availableSize) {
    return SagaPoint(
      normalized.x * availableSize.width,
      normalized.y * availableSize.height,
    );
  }

  /// Normalized along-axis coordinate where [chunkIndex] begins.
  static double chunkAlongOrigin(int chunkIndex, double chunkSpanNormalized) {
    return chunkIndex * chunkSpanNormalized;
  }

  /// Position of [position] within its chunk, as a `0..1` fraction of the
  /// chunk's along-axis span. Values outside `0..1` sit in a neighboring chunk.
  static double relativeAlong(
    SagaPoint position,
    int chunkIndex,
    double chunkSpanNormalized,
  ) {
    assert(
      chunkSpanNormalized > 0,
      'chunkSpanNormalized must be greater than 0',
    );
    final origin = chunkAlongOrigin(chunkIndex, chunkSpanNormalized);
    return (position.y - origin) / chunkSpanNormalized;
  }

  /// Converts a global level position into chunk-local pixel coordinates.
  ///
  /// [lateralBounds] describes the band the generator produces levels within;
  /// the band is centered on the lateral axis using bounds alone, so every
  /// chunk resolves the same offset and the path stays aligned across chunk
  /// seams.
  ///
  /// [lateralPaddingPx] keeps the band clear of the lateral edges, so nodes at
  /// the extremes are not clipped by the chunk box.
  ///
  /// [reverseAlongAxis] mirrors the path axis, for right-to-left layouts.
  ///
  /// Set [clampAlongAxis] to `false` to let neighbor levels resolve outside the
  /// chunk — required when bridging the path across a chunk boundary.
  static SagaPoint levelToChunkPixel(
    SagaPoint position,
    int chunkIndex,
    double chunkSpanNormalized,
    SagaSize chunkSizePx, {
    SagaMapPathAxis pathAxis = SagaMapPathAxis.vertical,
    double alongEdgeInsetFraction = 0.0,
    SagaLateralBounds lateralBounds = SagaLateralBounds.unit,
    double lateralPaddingPx = 0.0,
    bool reverseAlongAxis = false,
    bool clampAlongAxis = true,
  }) {
    var relAlong = relativeAlong(position, chunkIndex, chunkSpanNormalized);
    assert(
      !clampAlongAxis || (relAlong >= -0.001 && relAlong <= 1.001),
      'Level at along-axis ${position.y} falls outside chunk $chunkIndex '
      '(span $chunkSpanNormalized, relative $relAlong) and will be clamped '
      'onto the chunk edge. chunkSpanNormalized must equal '
      'stepHeight * levelsPerChunk — see SagaMapConfig.spanForLevelCount().',
    );
    if (clampAlongAxis) {
      relAlong = relAlong.clamp(0.0, 1.0);
    }

    final lateral = position.x + lateralBounds.centeringOffset;
    final inset = alongEdgeInsetFraction.clamp(0.0, kMaxAlongEdgeInsetFraction);

    final alongExtent = pathAxis == SagaMapPathAxis.vertical
        ? chunkSizePx.height
        : chunkSizePx.width;
    final lateralExtent = pathAxis == SagaMapPathAxis.vertical
        ? chunkSizePx.width
        : chunkSizePx.height;

    final insetPx = inset * alongExtent;
    final forwardPx = insetPx + relAlong * (alongExtent - 2 * insetPx);
    // Mirrored for right-to-left horizontal maps: the chunk list already lays
    // chunks out right-to-left there, so a chunk whose interior still ran
    // left-to-right would jump backwards at every seam.
    final alongPx = reverseAlongAxis ? alongExtent - forwardPx : forwardPx;

    // Never let padding collapse the band; a padding wider than half the extent
    // would otherwise invert it.
    final pad = lateralPaddingPx.clamp(0.0, lateralExtent / 2);
    final lateralPx = pad + lateral * (lateralExtent - 2 * pad);

    return pathAxis == SagaMapPathAxis.vertical
        ? SagaPoint(lateralPx, alongPx)
        : SagaPoint(alongPx, lateralPx);
  }
}
