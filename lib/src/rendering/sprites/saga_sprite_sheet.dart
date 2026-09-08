import 'dart:ui' show Rect, Size;

/// How frames are arranged inside a sprite sheet image.
enum SagaSpriteLayout {
  /// One row, frames side by side. A sheet of three 60x60 frames is 180x60.
  horizontal,

  /// One column, frames stacked. A sheet of three 60x60 frames is 60x180.
  vertical,

  /// Several rows, filled left to right then top to bottom. Needs
  /// [SagaSpriteSheet.columns]; use it once a single strip would be
  /// impractically long.
  grid,
}

/// How a clip behaves once it reaches its last frame.
enum SagaSpriteLoop {
  /// Restart from the first frame.
  loop,

  /// Hold the last frame.
  once,

  /// Play forwards, then backwards, forever.
  pingPong,
}

/// Describes how to cut an image into equally sized frames.
///
/// Pure geometry — no image, no playback. Dimensions are in the image's own
/// pixels at 1x; [SagaSpriteAnimation] applies the resolved asset scale, so
/// `2.0x` and `3.0x` asset variants work without changing these numbers.
/// Names the field that is actually wrong when a sheet resolves to no columns.
///
/// Split out so it is testable: in a debug build the constructor's asserts
/// refuse a degenerate sheet before [SagaSpriteSheet.resolvedColumns] can
/// report on it, so the message this produces is otherwise reachable only in
/// release. The old message said "must have at least one column" whatever the
/// layout — but a horizontal sheet has one column per frame and never reads
/// `columns`, so it sent hosts to inspect a field that layout ignores.
String describeDegenerateSheet({
  required SagaSpriteLayout layout,
  required int frameCount,
  required int? columns,
}) {
  return switch (layout) {
    SagaSpriteLayout.horizontal =>
      'SagaSpriteSheet frameCount must be greater than 0 (got $frameCount); '
          'a horizontal sheet has one column per frame',
    SagaSpriteLayout.vertical =>
      'SagaSpriteSheet frameCount must be greater than 0 (got $frameCount)',
    SagaSpriteLayout.grid =>
      'SagaSpriteSheet grid columns must be greater than 0 (got $columns)',
  };
}

class SagaSpriteSheet {
  /// Width of one frame.
  final double frameWidth;

  /// Height of one frame.
  final double frameHeight;

  /// Total number of frames in the sheet.
  final int frameCount;

  final SagaSpriteLayout layout;

  /// Frames per row, for [SagaSpriteLayout.grid].
  ///
  /// Ignored by the strip layouts, which have one row or one column by
  /// definition.
  final int? columns;

  /// Gap between neighbouring frames, as packed atlases often have.
  final double spacing;

  /// Border around the whole sheet.
  final double margin;

  const SagaSpriteSheet({
    required this.frameWidth,
    required this.frameHeight,
    required this.frameCount,
    this.layout = SagaSpriteLayout.horizontal,
    this.columns,
    this.spacing = 0,
    this.margin = 0,
  })  : assert(frameWidth > 0, 'frameWidth must be greater than 0'),
        assert(frameHeight > 0, 'frameHeight must be greater than 0'),
        assert(frameCount > 0, 'frameCount must be greater than 0'),
        assert(spacing >= 0, 'spacing must not be negative'),
        assert(margin >= 0, 'margin must not be negative'),
        assert(
          layout != SagaSpriteLayout.grid || (columns != null && columns > 0),
          'a grid layout needs a positive columns value',
        );

  /// Frames per row for the configured layout.
  int get resolvedColumns {
    final int result = switch (layout) {
      SagaSpriteLayout.horizontal => frameCount,
      SagaSpriteLayout.vertical => 1,
      // The constructor can only assert; in release a grid with missing or
      // non-positive columns would otherwise divide by zero in [frameRect].
      SagaSpriteLayout.grid => switch (columns) {
          final int c when c > 0 => c,
          _ => throw StateError(
              'SagaSpriteSheet grid layout requires columns > 0',
            ),
        },
    };
    // `resolvedColumns` is the divisor in `frameRect` and `rows`. Degenerate
    // dimensions must fail here rather than as an integer division-by-zero
    // deep in the painter — and must name the field that is actually wrong.
    // For a horizontal sheet the column count *is* `frameCount`, so the old
    // "must have at least one column" sent a host looking at `columns`, which
    // that layout does not even read.
    if (result <= 0) {
      throw StateError(describeDegenerateSheet(
        layout: layout,
        frameCount: frameCount,
        columns: columns,
      ));
    }
    return result;
  }

  /// Number of rows the frames occupy. The last row may be partly empty.
  int get rows => (frameCount / resolvedColumns).ceil();

  /// Size the source image is expected to be.
  ///
  /// Handy for asserting a sheet against the artwork it was written for; a
  /// mismatch usually means the frame size or count is wrong.
  Size get sheetSize {
    final columnCount = resolvedColumns;
    return Size(
      margin * 2 + columnCount * frameWidth + (columnCount - 1) * spacing,
      margin * 2 + rows * frameHeight + (rows - 1) * spacing,
    );
  }

  /// Source rectangle of frame [index] within the image.
  Rect frameRect(int index) {
    assert(
      index >= 0 && index < frameCount,
      'frame $index is outside 0..${frameCount - 1}',
    );
    final columnCount = resolvedColumns;
    final column = index % columnCount;
    final row = index ~/ columnCount;
    return Rect.fromLTWH(
      margin + column * (frameWidth + spacing),
      margin + row * (frameHeight + spacing),
      frameWidth,
      frameHeight,
    );
  }

  /// Returns a copy with selective overrides.
  SagaSpriteSheet copyWith({
    double? frameWidth,
    double? frameHeight,
    int? frameCount,
    SagaSpriteLayout? layout,
    int? columns,
    double? spacing,
    double? margin,
  }) {
    return SagaSpriteSheet(
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
      frameCount: frameCount ?? this.frameCount,
      layout: layout ?? this.layout,
      columns: columns ?? this.columns,
      spacing: spacing ?? this.spacing,
      margin: margin ?? this.margin,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaSpriteSheet &&
          other.frameWidth == frameWidth &&
          other.frameHeight == frameHeight &&
          other.frameCount == frameCount &&
          other.layout == layout &&
          other.columns == columns &&
          other.spacing == spacing &&
          other.margin == margin);

  @override
  int get hashCode => Object.hash(
        frameWidth,
        frameHeight,
        frameCount,
        layout,
        columns,
        spacing,
        margin,
      );
}

/// A run of frames played at a fixed rate.
///
/// One sheet usually holds several animations — idle, walk, hop — so a clip
/// names the slice it plays rather than assuming the whole sheet is one
/// animation.
class SagaSpriteClip {
  /// Index of the first frame in the sheet.
  final int from;

  /// How many frames the clip covers.
  final int count;

  /// Frames per second.
  final double fps;

  final SagaSpriteLoop loop;

  const SagaSpriteClip({
    this.from = 0,
    required this.count,
    this.fps = 12,
    this.loop = SagaSpriteLoop.loop,
  })  : assert(from >= 0, 'from must not be negative'),
        assert(count > 0, 'count must be greater than 0'),
        assert(fps > 0, 'fps must be greater than 0');

  /// Plays every frame of [sheet] in order.
  SagaSpriteClip.wholeSheet(
    SagaSpriteSheet sheet, {
    this.fps = 12,
    this.loop = SagaSpriteLoop.loop,
  })  : from = 0,
        count = sheet.frameCount;

  /// How long one pass through the clip takes.
  Duration get passDuration => Duration(
        microseconds: (count / fps * Duration.microsecondsPerSecond).round(),
      );

  /// Sheet frame index to show after [elapsed] of playback.
  ///
  /// Pure, so playback can be verified without running a ticker.
  int frameAt(Duration elapsed) {
    if (count == 1) return from;

    final ticks = elapsed.isNegative
        ? 0
        : (elapsed.inMicroseconds * fps / Duration.microsecondsPerSecond)
            .floor();

    switch (loop) {
      case SagaSpriteLoop.loop:
        return from + ticks % count;
      case SagaSpriteLoop.once:
        return from + (ticks >= count ? count - 1 : ticks);
      case SagaSpriteLoop.pingPong:
        // Both end frames are held for a single tick, so the turnaround does
        // not stutter: 0,1,2,1,0,1,2...
        final period = 2 * count - 2;
        final phase = ticks % period;
        return from + (phase < count ? phase : period - phase);
    }
  }

  /// Whether a [SagaSpriteLoop.once] clip has reached its final frame.
  bool isFinished(Duration elapsed) {
    if (loop != SagaSpriteLoop.once) return false;
    return elapsed >= passDuration;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaSpriteClip &&
          other.from == from &&
          other.count == count &&
          other.fps == fps &&
          other.loop == loop);

  @override
  int get hashCode => Object.hash(from, count, fps, loop);
}
