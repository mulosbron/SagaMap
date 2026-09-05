import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Path roundness: `0` must reproduce the straight polyline exactly, and higher
/// values must bend the line between nodes without moving the nodes.

const _zigzag = <SagaPoint>[
  SagaPoint(100, 0),
  SagaPoint(300, 100),
  SagaPoint(100, 200),
  SagaPoint(300, 300),
  SagaPoint(100, 400),
];

double _distance(SagaPoint a, SagaPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Samples a whole path, endpoints included.
List<SagaPoint> _sample(List<SagaPathSegment> segments, {int per = 24}) {
  return [
    for (final segment in segments)
      for (var i = 0; i <= per; i++) segment.pointAt(i / per),
  ];
}

/// Shortest distance from [point] to the polyline through [points].
double _distanceToPolyline(SagaPoint point, List<SagaPoint> points) {
  var best = double.infinity;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;
    var t = 0.0;
    if (lengthSquared > 0) {
      t = (((point.x - a.x) * dx) + ((point.y - a.y) * dy)) / lengthSquared;
      t = t.clamp(0.0, 1.0);
    }
    final closest = SagaPoint(a.x + dx * t, a.y + dy * t);
    best = math.min(best, _distance(point, closest));
  }
  return best;
}

void main() {
  group('degenerate input', () {
    test('no points produce no segments', () {
      expect(buildSagaPathSegments(const [], curvature: 1), isEmpty);
    });

    test('a single point produces no segments', () {
      expect(
        buildSagaPathSegments(const [SagaPoint(0, 0)], curvature: 1),
        isEmpty,
      );
    });

    test('two points make one segment', () {
      final segments = buildSagaPathSegments(
        const [SagaPoint(0, 0), SagaPoint(10, 10)],
        curvature: 1,
      );
      expect(segments, hasLength(1));
      expect(segments.single.start, const SagaPoint(0, 0));
      expect(segments.single.end, const SagaPoint(10, 10));
    });

    test('two points stay straight: there is nothing to curve towards', () {
      final segments = buildSagaPathSegments(
        const [SagaPoint(0, 0), SagaPoint(10, 10)],
        curvature: 1,
      );
      // Both neighbours clamp to the endpoints, so the handles lie on the
      // chord and the segment cannot bow.
      for (final point in _sample(segments)) {
        expect(
          _distanceToPolyline(
              point, const [SagaPoint(0, 0), SagaPoint(10, 10)]),
          lessThan(1e-9),
        );
      }
    });

    test('coincident points do not produce NaN coordinates', () {
      final segments = buildSagaPathSegments(
        const [
          SagaPoint(0, 0),
          SagaPoint(50, 50),
          SagaPoint(50, 50),
          SagaPoint(100, 0),
        ],
        curvature: 1,
      );

      for (final point in _sample(segments)) {
        expect(point.x.isFinite, isTrue);
        expect(point.y.isFinite, isTrue);
      }
    });

    test('an all-identical run stays put', () {
      final segments = buildSagaPathSegments(
        const [SagaPoint(7, 7), SagaPoint(7, 7), SagaPoint(7, 7)],
        curvature: 1,
      );
      // Bézier weights sum to one only up to rounding, so compare with a
      // tolerance rather than for exact equality.
      for (final point in _sample(segments)) {
        expect(point.x, closeTo(7, 1e-9));
        expect(point.y, closeTo(7, 1e-9));
      }
    });
  });

  group('curvature zero', () {
    test('collapses every control onto its endpoint', () {
      final segments = buildSagaPathSegments(_zigzag, curvature: 0);
      expect(segments, hasLength(_zigzag.length - 1));
      for (final segment in segments) {
        expect(segment.isStraight, isTrue);
      }
    });

    test('reproduces the straight polyline exactly', () {
      final segments = buildSagaPathSegments(_zigzag, curvature: 0);
      for (final point in _sample(segments)) {
        expect(_distanceToPolyline(point, _zigzag), lessThan(1e-9));
      }
    });

    test('a negative value is treated as zero', () {
      expect(
        buildSagaPathSegments(_zigzag, curvature: -5),
        equals(buildSagaPathSegments(_zigzag, curvature: 0)),
      );
    });
  });

  group('curvature above zero', () {
    test('bends the line away from the straight polyline', () {
      final segments = buildSagaPathSegments(_zigzag, curvature: 1);
      final maxDeviation = _sample(segments)
          .map((point) => _distanceToPolyline(point, _zigzag))
          .reduce(math.max);

      expect(maxDeviation, greaterThan(5));
    });

    test('roundness grows monotonically with the value', () {
      double deviationAt(double curvature) {
        final segments = buildSagaPathSegments(_zigzag, curvature: curvature);
        return _sample(segments)
            .map((point) => _distanceToPolyline(point, _zigzag))
            .reduce(math.max);
      }

      final deviations = [0.0, 0.25, 0.5, 0.75, 1.0].map(deviationAt).toList();
      for (var i = 1; i < deviations.length; i++) {
        expect(
          deviations[i],
          greaterThan(deviations[i - 1]),
          reason: 'deviations: $deviations',
        );
      }
    });

    test('values above one are clamped', () {
      expect(
        buildSagaPathSegments(_zigzag, curvature: 4),
        equals(buildSagaPathSegments(_zigzag, curvature: 1)),
      );
      expect(
        buildSagaPathSegments(_zigzag, curvature: double.infinity),
        equals(buildSagaPathSegments(_zigzag, curvature: 1)),
      );
    });

    test('the nodes themselves never move', () {
      for (final curvature in const [0.0, 0.3, 0.7, 1.0]) {
        final segments = buildSagaPathSegments(_zigzag, curvature: curvature);
        for (var i = 0; i < segments.length; i++) {
          expect(segments[i].start, _zigzag[i]);
          expect(segments[i].end, _zigzag[i + 1]);
          // Interpolating spline: the ends are exactly the input nodes.
          expect(segments[i].pointAt(0), _zigzag[i]);
          expect(segments[i].pointAt(1), _zigzag[i + 1]);
        }
      }
    });

    test('collinear points stay on their line', () {
      const straightRun = [
        SagaPoint(0, 0),
        SagaPoint(50, 0),
        SagaPoint(100, 0),
        SagaPoint(150, 0),
      ];
      final segments = buildSagaPathSegments(straightRun, curvature: 1);
      for (final point in _sample(segments)) {
        expect(point.y, closeTo(0, 1e-9));
      }
    });

    test('never doubles back along a segment', () {
      // The handle cap at half the chord is what rules out a cusp; without it
      // a control would overshoot the far endpoint and fold the curve.
      final segments = buildSagaPathSegments(_zigzag, curvature: 1);
      for (final segment in segments) {
        var previous = segment.pointAt(0);
        var travelled = 0.0;
        for (var i = 1; i <= 64; i++) {
          final current = segment.pointAt(i / 64);
          travelled += _distance(previous, current);
          previous = current;
        }
        // A cusp makes the traced length balloon past the chord.
        expect(
            travelled, lessThan(_distance(segment.start, segment.end) * 1.6));
      }
    });

    test('stays within a bounded envelope of the polyline', () {
      final segments = buildSagaPathSegments(_zigzag, curvature: 1);
      final longestChord = [
        for (var i = 0; i < _zigzag.length - 1; i++)
          _distance(_zigzag[i], _zigzag[i + 1]),
      ].reduce(math.max);

      for (final point in _sample(segments)) {
        expect(_distanceToPolyline(point, _zigzag), lessThan(longestChord / 2));
      }
    });
  });

  group('symmetry and determinism', () {
    test('mirroring the input mirrors the output', () {
      final normal = buildSagaPathSegments(_zigzag, curvature: 1);
      final mirrored = buildSagaPathSegments(
        [for (final point in _zigzag) SagaPoint(-point.x, point.y)],
        curvature: 1,
      );

      for (var i = 0; i < normal.length; i++) {
        expect(mirrored[i].control1.x, closeTo(-normal[i].control1.x, 1e-9));
        expect(mirrored[i].control1.y, closeTo(normal[i].control1.y, 1e-9));
      }
    });

    test('the same input always gives the same curve', () {
      expect(
        buildSagaPathSegments(_zigzag, curvature: 0.6),
        equals(buildSagaPathSegments(_zigzag, curvature: 0.6)),
      );
    });

    test('a long path is handled without blowing up', () {
      final points = <SagaPoint>[
        for (var i = 0; i < 5000; i++)
          SagaPoint(i.isEven ? 100 : 300, i * 20.0),
      ];
      final segments = buildSagaPathSegments(points, curvature: 1);
      expect(segments, hasLength(4999));
      expect(segments.last.end, points.last);
    });
  });

  group('segment value semantics', () {
    test('pointAt walks from start to end', () {
      const segment = SagaPathSegment(
        start: SagaPoint(0, 0),
        control1: SagaPoint(0, 10),
        control2: SagaPoint(10, 10),
        end: SagaPoint(10, 0),
      );
      expect(segment.pointAt(0), const SagaPoint(0, 0));
      expect(segment.pointAt(1), const SagaPoint(10, 0));
      expect(segment.pointAt(0.5).y, greaterThan(0));
    });

    test('isStraight only holds when both controls sit on the endpoints', () {
      const straight = SagaPathSegment(
        start: SagaPoint(0, 0),
        control1: SagaPoint(0, 0),
        control2: SagaPoint(10, 0),
        end: SagaPoint(10, 0),
      );
      const bent = SagaPathSegment(
        start: SagaPoint(0, 0),
        control1: SagaPoint(2, 3),
        control2: SagaPoint(10, 0),
        end: SagaPoint(10, 0),
      );
      expect(straight.isStraight, isTrue);
      expect(bent.isStraight, isFalse);
    });

    test('segments compare by value', () {
      const a = SagaPathSegment(
        start: SagaPoint(0, 0),
        control1: SagaPoint(1, 1),
        control2: SagaPoint(2, 2),
        end: SagaPoint(3, 3),
      );
      const b = SagaPathSegment(
        start: SagaPoint(0, 0),
        control1: SagaPoint(1, 1),
        control2: SagaPoint(2, 2),
        end: SagaPoint(3, 3),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('chunk seams', () {
    const config = SagaMapConfig.defaultConfig;
    const levelsPerChunk = 10;
    const generator = SagaMapLevelGenerator();

    List<LevelData> chunk(int index) => generator.generateLevels(
          globalSeed: 11,
          config: config,
          startLevelId: index * levelsPerChunk,
          count: levelsPerChunk,
        );

    SagaMapRenderContext context(int index, double curvature) {
      final previous = index > 0 ? chunk(index - 1) : const <LevelData>[];
      final next = chunk(index + 1);
      return SagaMapRenderContext(
        levels: chunk(index),
        chunkIndex: index,
        chunkSize: const SagaSize(width: 920, height: 400),
        chunkSpanNormalized: config.spanForLevelCount(levelsPerChunk),
        layout: SagaResponsiveResolver(
          config: SagaMapResponsiveConfig.defaults.copyWith(
            pathAxis: SagaMapPathAxis.horizontal,
            cameraPaddingPolicy: const SagaMapValuePolicy.all(0),
          ),
        ).resolveForWidth(1000),
        lateralBounds: config.lateralBounds,
        leadingNeighbors: previous.isEmpty
            ? const <LevelData>[]
            : previous.sublist(previous.length - kSagaPathNeighborCount),
        trailingNeighbors: next.sublist(0, kSagaPathNeighborCount),
        pathCurvature: curvature,
      );
    }

    test('two neighbours per side are enough to agree on the shared segment',
        () {
      // Chunk 0 draws the segment leaving its last level; chunk 1 draws the
      // same segment arriving at its first. With fewer neighbours each would
      // guess a different tangent and the join would kink.
      final fromChunk0 = context(0, 1).pathSegments();
      final fromChunk1 = context(1, 1).pathSegments();

      // The shared segment is the last one chunk 0 draws inside its own box.
      final chunk0Seam = fromChunk0[levelsPerChunk - 1];
      final chunk1Seam = fromChunk1[kSagaPathNeighborCount - 1];

      // Chunk 1's copy is offset by one chunk extent along the path axis.
      const extent = 920.0;
      expect(chunk1Seam.start.x + extent, closeTo(chunk0Seam.start.x, 1e-6));
      expect(chunk1Seam.start.y, closeTo(chunk0Seam.start.y, 1e-6));
      expect(
        chunk1Seam.control1.x + extent,
        closeTo(chunk0Seam.control1.x, 1e-6),
      );
      expect(chunk1Seam.control1.y, closeTo(chunk0Seam.control1.y, 1e-6));
      expect(
        chunk1Seam.control2.x + extent,
        closeTo(chunk0Seam.control2.x, 1e-6),
      );
      expect(chunk1Seam.control2.y, closeTo(chunk0Seam.control2.y, 1e-6));
    });

    test('a straight path still meets exactly at the seam', () {
      final fromChunk0 = context(0, 0).pathSegments();
      final fromChunk1 = context(1, 0).pathSegments();
      expect(fromChunk0.every((segment) => segment.isStraight), isTrue);
      expect(fromChunk1.every((segment) => segment.isStraight), isTrue);
    });
  });

  group('widget integration', () {
    Future<void> pump(WidgetTester tester, double curvature) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapChunkWidget(
              chunkContext: SagaChunkContext(
                  chunkIndex: 0, levels: const [], progress: const {}),
              levels: const [
                LevelData(
                    id: 0,
                    position: SagaPoint(0.2, 0.0),
                    biomeId: kBiomeIdForest),
                LevelData(
                    id: 1,
                    position: SagaPoint(0.8, 0.5),
                    biomeId: kBiomeIdForest),
              ],
              chunkIndex: 0,
              chunkExtent: 600,
              chunkSpanNormalized: 1.0,
              pathCurvature: curvature,
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              nodeBuilder: (context, level, layout) =>
                  SizedBox.expand(key: ValueKey('node-${level.id}')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('curvature does not move the nodes', (tester) async {
      await pump(tester, 0);
      final straight = tester.getCenter(find.byKey(const ValueKey('node-1')));

      await pump(tester, 1);
      final curved = tester.getCenter(find.byKey(const ValueKey('node-1')));

      expect(curved.dx, moreOrLessEquals(straight.dx, epsilon: 0.01));
      expect(curved.dy, moreOrLessEquals(straight.dy, epsilon: 0.01));
    });

    testWidgets('an out-of-range value renders without complaint',
        (tester) async {
      await pump(tester, 99);
      expect(tester.takeException(), isNull);
    });
  });
}
