/// Collaborators pulled out of `_SagaInfiniteMapViewState`.
///
/// The State had grown eight independent reasons to change — scroll and
/// load-more, camera follow, gate lifecycle, pinch math, parallax, chunk
/// events, opening-scroll sequencing — and each new feature added another
/// branch rather than another name. These are the two that carry state of
/// their own, which is what makes them worth separating: the rest is
/// orchestration that belongs where the widget lives.
///
/// Neither touches a `BuildContext`, a `State`, or `setState`. They are given
/// numbers and return decisions, so they can be reasoned about — and tested —
/// without a widget tree.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/domain/models/level_data.dart';
import '../contracts/saga_chunk_context.dart';
import '../interaction/saga_map_zoom.dart';

/// Remembers which chunk and which level the host has already been told about.
///
/// Both events are edge-triggered: "you entered chunk 4" must fire once, not on
/// every scroll frame while chunk 4 is still the dominant one.
class SagaChunkEventTracker {
  SagaChunkEventTracker({
    required this.contextFor,
    required this.levelsFor,
  });

  /// The chunk context to hand the host, or `null` when the chunk holds no
  /// levels yet. Resolved lazily so a chunk nobody enters is never built.
  final SagaChunkContext? Function(int chunkIndex) contextFor;

  /// Levels of a chunk, empty when it is evicted or still loading.
  final List<LevelData> Function(int chunkIndex) levelsFor;

  int? _lastBroadcastChunkIndex;
  int? _highestReachedLevel;

  /// The chunk index last announced, for tests and diagnostics.
  int? get lastBroadcastChunkIndex => _lastBroadcastChunkIndex;

  /// The highest level index reached so far, for tests and diagnostics.
  int? get highestReachedLevel => _highestReachedLevel;

  /// Forgets what has been announced, for a new world on the same view.
  ///
  /// Both fields are "furthest so far" marks, and both are meaningless across
  /// a controller swap: the new controller's chunk 3 is not the old one's, and
  /// its level 40 was never reached. Left standing, `onLevelReached` stays
  /// silent for every level the *previous* world had already passed, and
  /// `onChunkEnter` decides against a stale last value.
  void reset() {
    _lastBroadcastChunkIndex = null;
    _highestReachedLevel = null;
  }

  /// Announces the chunk under the middle of the viewport, once per entry.
  ///
  /// [centerOffset] is the scroll offset of the viewport's centre and
  /// [chunkExtent] the along-axis size of one chunk, both already zoomed.
  /// Reports the chunk under the viewport's centre.
  ///
  /// [episodeHeaderExtent] must be the same value the view lays its headers
  /// out with. A list item is `header + chunk`, so chunk `c` begins at
  /// `c * (chunkExtent + episodeHeaderExtent)`; dividing by the chunk extent
  /// alone drifts one full chunk every `chunkExtent / episodeHeaderExtent`
  /// chunks, and `onChunkEnter` then names the wrong chunk for the rest of the
  /// scroll.
  void checkDominantChunk({
    required double centerOffset,
    required double chunkExtent,
    required void Function(SagaChunkContext chunk)? onChunkEnter,
    double episodeHeaderExtent = 0,
  }) {
    if (onChunkEnter == null) return;
    if (chunkExtent <= 0) return;

    final stride = chunkExtent + episodeHeaderExtent;
    if (stride <= 0) return;
    final dominantIndex = (centerOffset / stride).floor();
    if (dominantIndex < 0) return;
    if (_lastBroadcastChunkIndex == dominantIndex) return;

    _lastBroadcastChunkIndex = dominantIndex;
    final chunk = contextFor(dominantIndex);
    if (chunk != null && chunk.levels.isNotEmpty) onChunkEnter(chunk);
  }

  /// Announces a level the character has newly walked onto.
  ///
  /// The first observation only records where the character starts: opening a
  /// map at level 30 is not the player reaching level 30.
  void checkLevelReached({
    required double? pathPosition,
    required int sectionsPerChunk,
    required void Function(LevelData level)? onLevelReached,
  }) {
    if (onLevelReached == null) return;
    if (pathPosition == null) return;

    final currentLevelIdx = pathPosition.floor();
    if (_highestReachedLevel == null) {
      _highestReachedLevel = currentLevelIdx;
      return;
    }
    if (currentLevelIdx <= _highestReachedLevel!) return;

    _highestReachedLevel = currentLevelIdx;
    if (sectionsPerChunk <= 0) return;

    final levels = levelsFor(currentLevelIdx ~/ sectionsPerChunk);
    final chunkLevelIndex = currentLevelIdx % sectionsPerChunk;
    if (chunkLevelIndex < levels.length) {
      onLevelReached(levels[chunkLevelIndex]);
    }
    // Otherwise the chunk is evicted or still loading and the callback is
    // dropped for this level — see `SagaInfiniteMapView.onLevelReached`. The
    // reload that request just scheduled will not re-fire it, because the
    // reached mark has already moved past it.
  }
}

/// What one pinch frame decided.
class SagaZoomGestureUpdate {
  const SagaZoomGestureUpdate({
    required this.zoom,
    required this.lateralPan,
    required this.targetScrollOffset,
  });

  final double zoom;
  final double lateralPan;

  /// Where the scroll offset must land to keep the focal point still.
  final double targetScrollOffset;
}

/// Pinch-to-zoom arithmetic, and the zoom and pan it produces.
///
/// Holds no widget, so the awkward part — keeping whatever sat under the
/// fingers under the fingers while the content grows — can be read on its own.
/// The range rule [SagaZoomGestureController.validate] enforces, over plain
/// numbers.
///
/// Split out so it can be tested at all. A debug build cannot construct an
/// invalid [SagaMapZoomConfig] to hand to the validator — the constructor's
/// asserts refuse it first, and for a `const` expression the compiler does —
/// so a test written against the config could only ever exercise the happy
/// path, which is the shape of test A-07 was about. Over raw numbers the
/// release-mode rule is checkable in debug.
void validateZoomRange({
  required double min,
  required double max,
  required double initial,
}) {
  if (!(min > 0)) {
    throw ArgumentError.value(
      min,
      'SagaMapZoomConfig.min',
      'must be greater than 0',
    );
  }
  if (max < min) {
    throw ArgumentError.value(
      max,
      'SagaMapZoomConfig.max',
      'must not be below min ($min)',
    );
  }
  if (initial < min || initial > max) {
    throw ArgumentError.value(
      initial,
      'SagaMapZoomConfig.initial',
      'must lie within min..max ($min..$max)',
    );
  }
}

class SagaZoomGestureController {
  SagaZoomGestureController({double initialZoom = 1.0}) : _zoom = initialZoom;

  /// Rejects a config that cannot describe a range, in release as in debug.
  ///
  /// [SagaMapZoomConfig]'s own constructor asserts this, and an assert is
  /// stripped from release builds — so a `min` above `max` used to survive all
  /// the way to `clamp`, which is reached from a paint. The host then saw a
  /// `StateError` from a pinch, a frame away from the line that built the
  /// config.
  ///
  /// Checked here, where the view first *accepts* the config, so a bad one
  /// fails while the widget is being set up. The config keeps its `const`
  /// constructor, which is worth more than moving the throw two frames
  /// earlier: hosts write `const SagaMapZoomConfig(...)` inside otherwise
  /// const subtrees, and a validating constructor cannot be `const`.
  static void validate(SagaMapZoomConfig? config) {
    if (config == null) return;
    validateZoomRange(
      min: config.min,
      max: config.max,
      initial: config.initial,
    );
  }

  double _zoom;
  double _lateralPan = 0;

  // Captured when a pinch begins, so every update is measured against the
  // gesture's origin rather than accumulating rounding from frame to frame.
  double _zoomAtGestureStart = 1;
  double _panAtGestureStart = 0;
  double _scrollAtGestureStart = 0;
  Offset _focalAtGestureStart = Offset.zero;

  /// Current user zoom, multiplied onto the responsive layout's own.
  double get zoom => _zoom;

  /// Current lateral pan, in logical pixels.
  double get lateralPan => _lateralPan;

  /// Re-clamps to a changed config, resetting the pan if the zoom moved.
  ///
  /// Returns true when anything changed, so the caller can decide whether a
  /// rebuild is warranted.
  bool applyConfig(SagaMapZoomConfig? config) {
    validate(config);
    final next = config == null ? 1.0 : config.clamp(_zoom);
    if (next == _zoom) return false;
    _zoom = next;
    _lateralPan = 0;
    return true;
  }

  void start({required double scrollOffset, required Offset focalPoint}) {
    _zoomAtGestureStart = _zoom;
    _panAtGestureStart = _lateralPan;
    _scrollAtGestureStart = scrollOffset;
    _focalAtGestureStart = focalPoint;
  }

  /// Applies one pinch frame. Returns `null` when the gesture is not a pinch.
  SagaZoomGestureUpdate? update({
    required SagaMapZoomConfig? config,
    required ScaleUpdateDetails details,
    required bool isVertical,
  }) {
    if (config == null || details.pointerCount < 2) return null;

    final next = config.clamp(_zoomAtGestureStart * details.scale);
    final ratio = next / _zoomAtGestureStart;

    final focalAlong =
        isVertical ? _focalAtGestureStart.dy : _focalAtGestureStart.dx;
    final focalLateral =
        isVertical ? _focalAtGestureStart.dx : _focalAtGestureStart.dy;
    final currentLateral =
        isVertical ? details.localFocalPoint.dx : details.localFocalPoint.dy;

    // Whatever sat under the fingers stays under them: the content grows about
    // the focal point, so the scroll offset has to grow with it.
    final targetOffset =
        (_scrollAtGestureStart + focalAlong) * ratio - focalAlong;

    _zoom = next;
    _lateralPan = _panAtGestureStart * ratio + (currentLateral - focalLateral);

    return SagaZoomGestureUpdate(
      zoom: _zoom,
      lateralPan: _lateralPan,
      targetScrollOffset: targetOffset,
    );
  }
}
