import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 20;
const _chunkExtentPx = 1840.0;
const _lateralExtentPx = 800.0;

const _generator = SagaMapLevelGenerator();

List<LevelData> _chunk(int chunkIndex) {
  return _generator.generateLevels(
    globalSeed: 42,
    config: _config,
    startLevelId: chunkIndex * _levelsPerChunk,
    count: _levelsPerChunk,
  );
}

ResolvedSagaLayout _layout(SagaMapPathAxis pathAxis) {
  return SagaResponsiveResolver(
    config: SagaMapResponsiveConfig.defaults.copyWith(pathAxis: pathAxis),
  ).resolveForWidth(1000);
}

SagaMapRenderContext _context(
  int chunkIndex, {
  required SagaMapPathAxis pathAxis,
  List<LevelData> leadingNeighbors = const <LevelData>[],
  List<LevelData> trailingNeighbors = const <LevelData>[],
}) {
  return SagaMapRenderContext(
    levels: _chunk(chunkIndex),
    chunkIndex: chunkIndex,
    chunkSize: pathAxis == SagaMapPathAxis.horizontal
        ? const SagaSize(width: _chunkExtentPx, height: _lateralExtentPx)
        : const SagaSize(width: _lateralExtentPx, height: _chunkExtentPx),
    chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
    layout: _layout(pathAxis),
    lateralBounds: _config.lateralBounds,
    leadingNeighbors: leadingNeighbors,
    trailingNeighbors: trailingNeighbors,
  );
}

/// Along-axis coordinate of [point] for the given orientation.
double _along(SagaPoint point, SagaMapPathAxis pathAxis) =>
    pathAxis == SagaMapPathAxis.horizontal ? point.x : point.y;

/// Lateral coordinate of [point] for the given orientation.
double _lateral(SagaPoint point, SagaMapPathAxis pathAxis) =>
    pathAxis == SagaMapPathAxis.horizontal ? point.y : point.x;

void main() {
  for (final pathAxis in SagaMapPathAxis.values) {
    group('${pathAxis.name} path', () {
      test('stops short of the chunk edge without a trailing neighbour', () {
        final points = _context(0, pathAxis: pathAxis).pathPoints();

        expect(points, hasLength(_levelsPerChunk));
        // The last level sits one step in from the edge; with nothing beyond
        // it, the drawn line ends there and the seam reads as a break.
        expect(
          _along(points.last, pathAxis),
          lessThan(_chunkExtentPx - 1),
        );
      });

      test('reaches the chunk edge when the next chunk is known', () {
        final next = _chunk(1);
        final points = _context(
          0,
          pathAxis: pathAxis,
          trailingNeighbors: [next.first],
        ).pathPoints();

        expect(points, hasLength(_levelsPerChunk + 1));
        expect(
          _along(points.last, pathAxis),
          moreOrLessEquals(_chunkExtentPx, epsilon: 0.001),
        );
      });

      test('joins the next chunk exactly at the shared edge', () {
        final first = _chunk(0);
        final next = _chunk(1);

        final endOfChunk0 = _context(
          0,
          pathAxis: pathAxis,
          trailingNeighbors: [next.first],
        ).pathPoints().last;

        final startOfChunk1 = _context(
          1,
          pathAxis: pathAxis,
          leadingNeighbors: [first.last],
        ).pathPoints().first;

        // Chunk 0 ends its line at its trailing edge; chunk 1 begins one step
        // before its leading edge. Together they cover the seam continuously.
        expect(_along(endOfChunk0, pathAxis),
            moreOrLessEquals(_chunkExtentPx, epsilon: 0.001));
        expect(_along(startOfChunk1, pathAxis), lessThan(0));

        // Same level, same lateral placement on both sides of the seam.
        final chunk1Start = _context(1, pathAxis: pathAxis).pathPoints().first;
        expect(
          _lateral(endOfChunk0, pathAxis),
          moreOrLessEquals(_lateral(chunk1Start, pathAxis), epsilon: 0.001),
        );
      });

      test('leading neighbour resolves outside the chunk instead of clamping',
          () {
        final first = _chunk(0);
        final points = _context(
          1,
          pathAxis: pathAxis,
          leadingNeighbors: [first.last],
        ).pathPoints();

        expect(points, hasLength(_levelsPerChunk + 1));
        // A clamped neighbour would land at exactly 0 and draw a spurious
        // segment along the chunk edge.
        expect(_along(points.first, pathAxis), lessThan(-1));
      });
    });
  }

  test('seam step matches an ordinary within-chunk step', () {
    const pathAxis = SagaMapPathAxis.horizontal;
    final chunk0 = _chunk(0);
    final points = _context(
      0,
      pathAxis: pathAxis,
      trailingNeighbors: [_chunk(1).first],
    ).pathPoints();

    final withinChunk = _along(points[chunk0.length - 1], pathAxis) -
        _along(points[chunk0.length - 2], pathAxis);
    final acrossSeam = _along(points.last, pathAxis) -
        _along(points[chunk0.length - 1], pathAxis);

    expect(acrossSeam, moreOrLessEquals(withinChunk, epsilon: 0.001));
  });
}
