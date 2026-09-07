import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:saga_map/src/rendering/widgets/saga_map_view_internals.dart';

/// T-21: the point of pulling these out of the State is that they can be
/// reasoned about without a widget tree — so here they are, reasoned about
/// without a widget tree.

const _levels = <LevelData>[
  LevelData(id: 0, position: SagaPoint(0.5, 0.0), biomeId: 'forest'),
  LevelData(id: 1, position: SagaPoint(0.5, 0.5), biomeId: 'forest'),
];

SagaChunkContext _contextFor(int index) => SagaChunkContext(
      chunkIndex: index,
      levels: _levels,
      progress: const {},
    );

void main() {
  group('SagaChunkEventTracker', () {
    test('announces a chunk once per entry, not once per frame', () {
      final seen = <int>[];
      final tracker = SagaChunkEventTracker(
        contextFor: _contextFor,
        levelsFor: (_) => _levels,
      );

      void scrollTo(double centerOffset) => tracker.checkDominantChunk(
            centerOffset: centerOffset,
            chunkExtent: 600,
            onChunkEnter: (chunk) => seen.add(chunk.chunkIndex),
          );

      scrollTo(100); // chunk 0
      scrollTo(300); // still chunk 0
      scrollTo(599); // still chunk 0
      scrollTo(700); // chunk 1
      scrollTo(100); // back to chunk 0

      expect(seen, [0, 1, 0]);
    });

    test('A-05 — headers shift the chunk boundaries the centre is measured '
        'against', () {
      // A list item is `header + chunk`, so with a 600px chunk and an 80px
      // header chunk `c` starts at `c * 680`, not `c * 600`. Dividing by the
      // chunk extent alone slid one whole chunk every 600/80 chunks, so deep
      // in the map `onChunkEnter` announced a chunk the player was nowhere
      // near — and this half of the header fix was never applied at all.
      const chunkExtent = 600.0;
      const headerExtent = 80.0;

      final seen = <int>[];
      final tracker = SagaChunkEventTracker(
        contextFor: _contextFor,
        levelsFor: (_) => _levels,
      );

      // The centre of chunk 8's body: 8 * 680 + 80 + 300.
      const centreOfChunk8 = 8 * (chunkExtent + headerExtent) + headerExtent + 300;

      tracker.checkDominantChunk(
        centerOffset: centreOfChunk8,
        chunkExtent: chunkExtent,
        episodeHeaderExtent: headerExtent,
        onChunkEnter: (chunk) => seen.add(chunk.chunkIndex),
      );

      expect(seen, [8]);
      // Without the header term this is `(5820 / 600).floor()` == 9.
      expect((centreOfChunk8 / chunkExtent).floor(), 9,
          reason: 'the drift this test exists for must actually be one chunk');
    });

    test('A-05 — a map with no headers is unaffected', () {
      final seen = <int>[];
      final tracker = SagaChunkEventTracker(
        contextFor: _contextFor,
        levelsFor: (_) => _levels,
      );

      tracker.checkDominantChunk(
        centerOffset: 1500,
        chunkExtent: 600,
        onChunkEnter: (chunk) => seen.add(chunk.chunkIndex),
      );

      expect(seen, [2]);
    });

    test('says nothing without a listener, or before the map has a size', () {
      final tracker = SagaChunkEventTracker(
        contextFor: _contextFor,
        levelsFor: (_) => _levels,
      );

      tracker.checkDominantChunk(
        centerOffset: 100,
        chunkExtent: 600,
        onChunkEnter: null,
      );
      expect(tracker.lastBroadcastChunkIndex, isNull);

      var fired = false;
      // A zero extent is the first frame, before layout.
      tracker.checkDominantChunk(
        centerOffset: 100,
        chunkExtent: 0,
        onChunkEnter: (_) => fired = true,
      );
      // And a negative offset is an overscroll bounce past the top.
      tracker.checkDominantChunk(
        centerOffset: -50,
        chunkExtent: 600,
        onChunkEnter: (_) => fired = true,
      );
      expect(fired, isFalse);
    });

    test('an empty chunk is not announced', () {
      var fired = false;
      final tracker = SagaChunkEventTracker(
        contextFor: (_) => null,
        levelsFor: (_) => const [],
      );

      tracker.checkDominantChunk(
        centerOffset: 100,
        chunkExtent: 600,
        onChunkEnter: (_) => fired = true,
      );

      expect(fired, isFalse);
    });

    test('opening at level 30 is not reaching level 30', () {
      final reached = <int>[];
      final tracker = SagaChunkEventTracker(
        contextFor: _contextFor,
        levelsFor: (_) => _levels,
      );

      void walkTo(double position) => tracker.checkLevelReached(
            pathPosition: position,
            sectionsPerChunk: 2,
            onLevelReached: (level) => reached.add(level.id),
          );

      walkTo(30); // the opening position: recorded, not announced
      expect(reached, isEmpty);

      walkTo(30.5); // same level, still nothing
      expect(reached, isEmpty);

      walkTo(31); // a level crossed
      expect(reached, hasLength(1));

      walkTo(30); // walking back does not re-announce
      expect(reached, hasLength(1));
    });
  });

  group('SagaZoomGestureController', () {
    const config = SagaMapZoomConfig(min: 0.5, max: 2, initial: 1);

    ScaleUpdateDetails pinch(double scale, Offset focal) => ScaleUpdateDetails(
          scale: scale,
          localFocalPoint: focal,
          focalPoint: focal,
          pointerCount: 2,
        );

    test('keeps what was under the fingers under the fingers', () {
      final zoom = SagaZoomGestureController(initialZoom: 1);
      zoom.start(scrollOffset: 600, focalPoint: const Offset(200, 400));

      final update = zoom.update(
        config: config,
        details: pinch(2, const Offset(200, 400)),
        isVertical: true,
      )!;

      expect(update.zoom, 2);
      // The content doubled about the focal point, so the offset of what sat
      // there doubles with it: (600 + 400) * 2 - 400.
      expect(update.targetScrollOffset, 1600);
    });

    test('a one-finger drag is not a pinch', () {
      final zoom = SagaZoomGestureController(initialZoom: 1);
      zoom.start(scrollOffset: 0, focalPoint: Offset.zero);

      expect(
        zoom.update(
          config: config,
          details: ScaleUpdateDetails(scale: 2, pointerCount: 1),
          isVertical: true,
        ),
        isNull,
      );
      expect(zoom.zoom, 1);
    });

    test('zoom stays inside the configured range', () {
      final zoom = SagaZoomGestureController(initialZoom: 1);
      zoom.start(scrollOffset: 0, focalPoint: Offset.zero);

      zoom.update(
          config: config, details: pinch(100, Offset.zero), isVertical: true);
      expect(zoom.zoom, 2);

      zoom.start(scrollOffset: 0, focalPoint: Offset.zero);
      zoom.update(
          config: config, details: pinch(0.001, Offset.zero), isVertical: true);
      expect(zoom.zoom, 0.5);
    });

    test('a new config re-clamps the zoom and resets the pan', () {
      final zoom = SagaZoomGestureController(initialZoom: 1);
      zoom.start(scrollOffset: 0, focalPoint: const Offset(100, 100));
      zoom.update(
          config: config,
          details: pinch(2, const Offset(150, 100)),
          isVertical: true);
      expect(zoom.zoom, 2);
      expect(zoom.lateralPan, isNot(0));

      expect(
        zoom.applyConfig(const SagaMapZoomConfig(min: 0.5, max: 1.2)),
        isTrue,
      );
      expect(zoom.zoom, 1.2);
      expect(zoom.lateralPan, 0);

      // Nothing to do the second time.
      expect(
        zoom.applyConfig(const SagaMapZoomConfig(min: 0.5, max: 1.2)),
        isFalse,
      );
    });

    test('removing the config returns to 1', () {
      final zoom = SagaZoomGestureController(initialZoom: 1.75);
      expect(zoom.applyConfig(null), isTrue);
      expect(zoom.zoom, 1);
    });
  });
}
