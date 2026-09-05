import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Arc-length parameterisation, the groundwork for a character that walks the
/// path at an even pace.

const _zigzag = <SagaPoint>[
  SagaPoint(100, 0),
  SagaPoint(300, 100),
  SagaPoint(100, 200),
  SagaPoint(300, 300),
  SagaPoint(100, 400),
];

double _distance(SagaPoint a, SagaPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Points compared with a tolerance: walking the length table and back through
/// the cubic loses the last bits, which is irrelevant at pixel scale.
void _expectPointCloseTo(SagaPoint actual, SagaPoint expected) {
  expect(actual.x, closeTo(expected.x, 1e-9));
  expect(actual.y, closeTo(expected.y, 1e-9));
}

SagaPathMetrics _metrics(double curvature) => SagaPathMetrics(
      buildSagaPathSegments(_zigzag, curvature: curvature),
    );

void main() {
  group('length', () {
    test('a straight segment measures its chord', () {
      final metrics = SagaPathMetrics(
        buildSagaPathSegments(
          const [SagaPoint(0, 0), SagaPoint(30, 40)],
          curvature: 0,
        ),
      );
      expect(metrics.totalLength, closeTo(50, 1e-9));
    });

    test('a curved path is longer than the polyline it interpolates', () {
      final straight = _metrics(0).totalLength;
      final curved = _metrics(1).totalLength;

      // Bending the line between fixed endpoints can only add length.
      expect(curved, greaterThan(straight));
    });

    test('total length is the sum of the segments', () {
      final metrics = _metrics(1);
      var sum = 0.0;
      for (var i = 0; i < metrics.segments.length; i++) {
        sum += metrics.lengthOfSegment(i);
      }
      expect(metrics.totalLength, closeTo(sum, 1e-9));
    });

    test('an empty path has no length and still answers', () {
      final metrics = SagaPathMetrics(const []);
      expect(metrics.totalLength, 0);
      expect(metrics.poseAtDistance(10).position, const SagaPoint(0, 0));
    });
  });

  group('even pace', () {
    test('equal distance steps cover equal ground on a curve', () {
      final metrics = _metrics(1);
      const steps = 40;

      final gaps = <double>[];
      var previous = metrics.poseAtDistance(0).position;
      for (var i = 1; i <= steps; i++) {
        final current =
            metrics.poseAtDistance(metrics.totalLength * i / steps).position;
        gaps.add(_distance(previous, current));
        previous = current;
      }

      // This is the test the naive `t` parameterisation fails: stepping t
      // evenly crawls through the tight parts of a curve and races the straight
      // parts.
      final shortest = gaps.reduce(math.min);
      final longest = gaps.reduce(math.max);
      expect(longest / shortest, lessThan(1.15), reason: 'gaps: $gaps');
    });

    test('stepping the raw parameter really is uneven', () {
      // Guards the premise: without arc length the spread is far worse, so the
      // test above is measuring something real.
      final segments = buildSagaPathSegments(_zigzag, curvature: 1);
      final segment = segments[1];
      const steps = 40;

      final gaps = <double>[];
      var previous = segment.pointAt(0);
      for (var i = 1; i <= steps; i++) {
        final current = segment.pointAt(i / steps);
        gaps.add(_distance(previous, current));
        previous = current;
      }

      final ratio = gaps.reduce(math.max) / gaps.reduce(math.min);
      expect(ratio, greaterThan(1.3), reason: 'gaps: $gaps');
    });

    test('a straight path needs no correction', () {
      final metrics = _metrics(0);
      // Straight segments skip the sample table entirely; t is the fraction.
      expect(metrics.tAtFraction(0, 0.25), closeTo(0.25, 1e-9));
      expect(metrics.tAtFraction(0, 0.5), closeTo(0.5, 1e-9));
    });
  });

  group('fraction to parameter', () {
    test('endpoints map to endpoints', () {
      final metrics = _metrics(1);
      expect(metrics.tAtFraction(0, 0), closeTo(0, 1e-9));
      expect(metrics.tAtFraction(0, 1), closeTo(1, 1e-9));
    });

    test('is monotonic', () {
      final metrics = _metrics(1);
      var previous = -1.0;
      for (var i = 0; i <= 20; i++) {
        final t = metrics.tAtFraction(1, i / 20);
        expect(t, greaterThanOrEqualTo(previous));
        previous = t;
      }
    });

    test('out-of-range fractions clamp', () {
      final metrics = _metrics(1);
      expect(metrics.tAtFraction(0, -5), closeTo(0, 1e-9));
      expect(metrics.tAtFraction(0, 5), closeTo(1, 1e-9));
    });

    test('a zero-length segment does not divide by zero', () {
      final metrics = SagaPathMetrics(
        buildSagaPathSegments(
          const [SagaPoint(5, 5), SagaPoint(5, 5), SagaPoint(50, 5)],
          curvature: 1,
        ),
      );
      final pose = metrics.poseOnSegment(0, 0.5);
      expect(pose.position.x.isFinite, isTrue);
      expect(pose.position.y.isFinite, isTrue);
    });
  });

  group('pose', () {
    test('segment ends sit exactly on the nodes', () {
      for (final curvature in const [0.0, 0.5, 1.0]) {
        final metrics = _metrics(curvature);
        for (var i = 0; i < metrics.segments.length; i++) {
          expect(metrics.poseOnSegment(i, 0).position, _zigzag[i]);
          expect(metrics.poseOnSegment(i, 1).position, _zigzag[i + 1]);
        }
      }
    });

    test('direction is a unit vector', () {
      final metrics = _metrics(1);
      for (var i = 0; i <= 10; i++) {
        final direction = metrics.poseOnSegment(1, i / 10).direction;
        final length = math.sqrt(
          direction.x * direction.x + direction.y * direction.y,
        );
        expect(length, closeTo(1, 1e-9));
      }
    });

    test('a straight segment still reports a heading at its ends', () {
      // A straight cubic carries its controls on the endpoints, so its raw
      // derivative is zero at t=0 and t=1 — a character would lose its facing
      // at every node without the chord fallback.
      final metrics = SagaPathMetrics(
        buildSagaPathSegments(
          const [SagaPoint(0, 0), SagaPoint(100, 0)],
          curvature: 0,
        ),
      );
      expect(metrics.poseOnSegment(0, 0).direction, const SagaPoint(1, 0));
      expect(metrics.poseOnSegment(0, 1).direction, const SagaPoint(1, 0));
    });

    test('heading points the way the path travels', () {
      final metrics = SagaPathMetrics(
        buildSagaPathSegments(
          const [SagaPoint(0, 0), SagaPoint(0, 100)],
          curvature: 0,
        ),
      );
      // Straight down the screen: heading is +pi/2 with y growing downwards.
      expect(
        metrics.poseOnSegment(0, 0.5).headingRadians,
        closeTo(math.pi / 2, 1e-9),
      );
    });

    test('distance walks the whole path end to end', () {
      final metrics = _metrics(1);
      _expectPointCloseTo(metrics.poseAtDistance(0).position, _zigzag.first);
      _expectPointCloseTo(
        metrics.poseAtDistance(metrics.totalLength).position,
        _zigzag.last,
      );
    });

    test('distance beyond the ends clamps', () {
      final metrics = _metrics(1);
      _expectPointCloseTo(metrics.poseAtDistance(-100).position, _zigzag.first);
      _expectPointCloseTo(
        metrics.poseAtDistance(metrics.totalLength * 3).position,
        _zigzag.last,
      );
    });
  });

  group('path position on a chunk', () {
    const config = SagaMapConfig.defaultConfig;
    const levelsPerChunk = 10;
    const generator = SagaMapLevelGenerator();

    List<LevelData> chunk(int index) => generator.generateLevels(
          globalSeed: 21,
          config: config,
          startLevelId: index * levelsPerChunk,
          count: levelsPerChunk,
        );

    SagaMapRenderContext context(int index, {double curvature = 1}) {
      final previous = index > 0 ? chunk(index - 1) : const <LevelData>[];
      final next = chunk(index + 1);
      return SagaMapRenderContext(
        levels: chunk(index),
        chunkIndex: index,
        chunkSize: const SagaSize(width: 400, height: 900),
        chunkSpanNormalized: config.spanForLevelCount(levelsPerChunk),
        layout: SagaResponsiveResolver(
          config: SagaMapResponsiveConfig.defaults.copyWith(
            cameraPaddingPolicy: const SagaMapValuePolicy.all(0),
          ),
        ).resolveForWidth(400),
        lateralBounds: config.lateralBounds,
        leadingNeighbors: previous.isEmpty
            ? const <LevelData>[]
            : previous.sublist(previous.length - kSagaPathNeighborCount),
        trailingNeighbors: next.sublist(0, kSagaPathNeighborCount),
        pathCurvature: curvature,
      );
    }

    test('a whole position lands exactly on its node', () {
      final ctx = context(1);
      for (final level in ctx.levels) {
        expect(
          ctx.characterPixel(level.id.toDouble()),
          ctx.pixelFor(level.position),
          reason: 'level ${level.id}',
        );
      }
    });

    test('a whole position lands on its node on a straight path too', () {
      final ctx = context(1, curvature: 0);
      final level = ctx.levels[4];
      expect(ctx.characterPixel(level.id.toDouble()), ctx.pixelFor(level.position));
    });

    test('a fractional position sits between its neighbours', () {
      final ctx = context(1);
      final first = ctx.levels[3];
      final second = ctx.levels[4];

      final midway = ctx.characterPixel(first.id + 0.5)!;
      final a = ctx.pixelFor(first.position);
      final b = ctx.pixelFor(second.position);

      expect(midway.y, greaterThan(math.min(a.y, b.y)));
      expect(midway.y, lessThan(math.max(a.y, b.y)));
    });

    test('positions outside the chunk return null', () {
      final ctx = context(1);
      // Well before the leading neighbours and well past the trailing ones.
      expect(ctx.characterPixel(-50), isNull);
      expect(ctx.characterPixel(999), isNull);
    });

    test('neighbouring chunks agree on a shared position', () {
      // The character walks across a seam; both chunks must place it in the
      // same spot, offset only by the chunk extent.
      const seamPosition = levelsPerChunk - 0.5;
      final fromChunk0 = context(0).characterPixel(seamPosition)!;
      final fromChunk1 = context(1).characterPixel(seamPosition)!;

      const extent = 900.0;
      expect(fromChunk1.y + extent, closeTo(fromChunk0.y, 1e-6));
      expect(fromChunk1.x, closeTo(fromChunk0.x, 1e-6));
    });

    test('the pose carries a usable heading', () {
      final ctx = context(1);
      final pose = ctx.poseAtPathPosition(ctx.levels.first.id + 0.5)!;
      final length = math.sqrt(
        pose.direction.x * pose.direction.x +
            pose.direction.y * pose.direction.y,
      );
      expect(length, closeTo(1, 1e-9));
    });

    test('metrics are built once per context', () {
      final ctx = context(1);
      expect(identical(ctx.pathMetrics, ctx.pathMetrics), isTrue);
    });

    test('an empty chunk has no positions', () {
      final ctx = SagaMapRenderContext(
        levels: const <LevelData>[],
        chunkIndex: 0,
        chunkSize: const SagaSize(width: 400, height: 900),
        chunkSpanNormalized: 1,
        layout: const SagaResponsiveResolver().resolveForWidth(400),
      );
      expect(ctx.characterPixel(0), isNull);
      expect(ctx.pointIndexForLevel(0), isNull);
    });
  });
}
