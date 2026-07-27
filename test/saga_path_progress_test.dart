import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Painting the covered stretch of path differently from the stretch ahead.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _generator = SagaMapLevelGenerator();

List<LevelData> _chunk(int index) => _generator.generateLevels(
      globalSeed: 5,
      config: _config,
      startLevelId: index * _levelsPerChunk,
      count: _levelsPerChunk,
    );

SagaMapRenderContext _context({
  int chunkIndex = 0,
  double? progress,
  double curvature = 1,
}) {
  final previous = chunkIndex > 0 ? _chunk(chunkIndex - 1) : const <LevelData>[];
  final next = _chunk(chunkIndex + 1);
  return SagaMapRenderContext(
    levels: _chunk(chunkIndex),
    chunkIndex: chunkIndex,
    chunkSize: const SagaSize(width: 400, height: 900),
    chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
    layout: const SagaResponsiveResolver().resolveForWidth(400),
    lateralBounds: _config.lateralBounds,
    leadingNeighbors: previous.isEmpty
        ? const <LevelData>[]
        : previous.sublist(previous.length - kSagaPathNeighborCount),
    trailingNeighbors: next.sublist(0, kSagaPathNeighborCount),
    pathCurvature: curvature,
    pathProgressPosition: progress,
  );
}

double _distance(SagaPoint a, SagaPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

void main() {
  group('subdivision', () {
    const segment = SagaPathSegment(
      start: SagaPoint(0, 0),
      control1: SagaPoint(0, 100),
      control2: SagaPoint(100, 100),
      end: SagaPoint(100, 0),
    );

    test('the halves meet exactly where they were cut', () {
      final split = segment.splitAt(0.4);
      expect(split.before.end, split.after.start);
      expect(split.before.start, segment.start);
      expect(split.after.end, segment.end);
    });

    test('the halves trace the original curve', () {
      // De Casteljau is exact, so sampling either half must land on the
      // original — resampling instead would leave a notch at the colour change.
      final split = segment.splitAt(0.4);
      for (var i = 0; i <= 10; i++) {
        final u = i / 10;
        expect(
          _distance(split.before.pointAt(u), segment.pointAt(u * 0.4)),
          lessThan(1e-9),
        );
        expect(
          _distance(
            split.after.pointAt(u),
            segment.pointAt(0.4 + u * 0.6),
          ),
          lessThan(1e-9),
        );
      }
    });

    test('splitting at the ends yields a degenerate half', () {
      final atStart = segment.splitAt(0);
      expect(atStart.before.start, segment.start);
      expect(atStart.before.end, segment.start);
      expect(atStart.after.end, segment.end);

      final atEnd = segment.splitAt(1);
      expect(atEnd.after.start, segment.end);
      expect(atEnd.after.end, segment.end);
    });

    test('out-of-range parameters clamp', () {
      expect(segment.splitAt(-5), segment.splitAt(0));
      expect(segment.splitAt(9), segment.splitAt(1));
    });

    test('a straight segment splits into straight halves', () {
      const line = SagaPathSegment(
        start: SagaPoint(0, 0),
        control1: SagaPoint(0, 0),
        control2: SagaPoint(100, 0),
        end: SagaPoint(100, 0),
      );
      final split = line.splitAt(0.5);
      expect(split.before.end, const SagaPoint(50, 0));
      expect(split.after.start, const SagaPoint(50, 0));
    });
  });

  group('splitting a chunk', () {
    test('no progress leaves the whole path upcoming', () {
      final split = _context().splitPathAtProgress();
      expect(split.walked, isEmpty);
      expect(split.upcoming, isNotEmpty);
    });

    test('progress in the middle divides the path', () {
      final split = _context(progress: 5).splitPathAtProgress();
      expect(split.walked, isNotEmpty);
      expect(split.upcoming, isNotEmpty);
      // Nothing is lost or duplicated in the cut.
      expect(
        split.walked.length + split.upcoming.length,
        _context(progress: 5).pathSegments().length + 1,
      );
    });

    test('the two halves join without a gap', () {
      final split = _context(progress: 5.4).splitPathAtProgress();
      expect(split.walked.last.end, split.upcoming.first.start);
    });

    test('a chunk entirely behind the player is fully walked', () {
      // Chunk 0 holds levels 0-9; a player at 25 has covered all of it.
      final split = _context(progress: 25).splitPathAtProgress();
      expect(split.upcoming, isEmpty);
      expect(split.walked, isNotEmpty);
    });

    test('a chunk entirely ahead of the player is untouched', () {
      final split =
          _context(chunkIndex: 2, progress: 3).splitPathAtProgress();
      expect(split.walked, isEmpty);
      expect(split.upcoming, isNotEmpty);
    });

    test('progress on a node splits there', () {
      final split = _context(progress: 4).splitPathAtProgress();
      final nodePixel = _context(progress: 4).characterPixel(4)!;
      expect(_distance(split.walked.last.end, nodePixel), lessThan(1e-6));
    });

    test('a straight path splits too', () {
      final split =
          _context(progress: 5.5, curvature: 0).splitPathAtProgress();
      expect(split.walked, isNotEmpty);
      expect(split.upcoming, isNotEmpty);
      expect(split.walked.last.end, split.upcoming.first.start);
    });

    test('the split point sits where the character would stand', () {
      // Both read the same arc-length parameterisation, so the colour change
      // lands exactly under the character's feet.
      final context = _context(progress: 6.3);
      final split = context.splitPathAtProgress();
      final characterAt = context.characterPixel(6.3)!;
      expect(_distance(split.walked.last.end, characterAt), lessThan(1e-6));
    });

    test('an empty chunk splits into nothing', () {
      final empty = SagaMapRenderContext(
        levels: const <LevelData>[],
        chunkIndex: 0,
        chunkSize: const SagaSize(width: 400, height: 900),
        chunkSpanNormalized: 1,
        layout: const SagaResponsiveResolver().resolveForWidth(400),
        pathProgressPosition: 3,
      );
      final split = empty.splitPathAtProgress();
      expect(split.walked, isEmpty);
      expect(split.upcoming, isEmpty);
    });
  });

  group('theme', () {
    test('upcoming colours default to the walked ones', () {
      const theme = SagaBiomeTheme(
        backgroundColor: Color(0xFF000000),
        pathFillColor: Color(0xFF112233),
        pathBorderColor: Color(0xFF445566),
        shadowColor: Color(0x40000000),
      );
      // Null means a map that tracks no progress looks exactly as before.
      expect(theme.upcomingPathFillColor, isNull);
      expect(theme.upcomingPathBorderColor, isNull);
    });

    test('upcoming colours can be set apart', () {
      const theme = SagaBiomeTheme(
        backgroundColor: Color(0xFF000000),
        pathFillColor: Color(0xFF112233),
        pathBorderColor: Color(0xFF445566),
        upcomingPathFillColor: Color(0xFF778899),
        upcomingPathBorderColor: Color(0xFFAABBCC),
        shadowColor: Color(0x40000000),
      );
      expect(theme.upcomingPathFillColor, const Color(0xFF778899));
      expect(theme.upcomingPathBorderColor, const Color(0xFFAABBCC));
    });
  });
}
