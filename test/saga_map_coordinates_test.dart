import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Direct tests for the coordinate core. It was only ever exercised through
/// widgets, which made it hard to tell a layout bug from a maths bug.

const _chunk = SagaSize(width: 1000, height: 500);

SagaPoint _pixel(
  SagaPoint position, {
  int chunkIndex = 0,
  double span = 1.0,
  SagaMapPathAxis pathAxis = SagaMapPathAxis.vertical,
  double alongEdgeInsetFraction = 0.0,
  SagaLateralBounds lateralBounds = SagaLateralBounds.unit,
  double lateralPaddingPx = 0.0,
  bool reverseAlongAxis = false,
  bool clampAlongAxis = true,
}) {
  return SagaMapCoordinates.levelToChunkPixel(
    position,
    chunkIndex,
    span,
    _chunk,
    pathAxis: pathAxis,
    alongEdgeInsetFraction: alongEdgeInsetFraction,
    lateralBounds: lateralBounds,
    lateralPaddingPx: lateralPaddingPx,
    reverseAlongAxis: reverseAlongAxis,
    clampAlongAxis: clampAlongAxis,
  );
}

void main() {
  test('toPixel scales a normalized point onto a box', () {
    final point = SagaMapCoordinates.toPixel(
      const SagaPoint(0.25, 0.5),
      _chunk,
    );
    expect(point.x, 250);
    expect(point.y, 250);
  });

  group('chunk arithmetic', () {
    test('origin is the chunk index times its span', () {
      expect(SagaMapCoordinates.chunkAlongOrigin(0, 1.6), 0);
      expect(SagaMapCoordinates.chunkAlongOrigin(3, 1.6), closeTo(4.8, 1e-12));
    });

    test('relativeAlong reports positions outside the chunk', () {
      expect(
        SagaMapCoordinates.relativeAlong(const SagaPoint(0, 1.6), 1, 1.6),
        closeTo(0.0, 1e-12),
      );
      expect(
        SagaMapCoordinates.relativeAlong(const SagaPoint(0, 3.2), 1, 1.6),
        closeTo(1.0, 1e-12),
      );
      // One step before the chunk starts: a leading neighbour.
      expect(
        SagaMapCoordinates.relativeAlong(const SagaPoint(0, 1.52), 1, 1.6),
        lessThan(0),
      );
    });
  });

  group('vertical path', () {
    test('lateral lands on width, along on height', () {
      final point = _pixel(const SagaPoint(0.25, 0.5));
      expect(point.x, 250);
      expect(point.y, 250);
    });

    test('an edge inset shrinks the usable along span symmetrically', () {
      final start = _pixel(const SagaPoint(0.5, 0.0),
          alongEdgeInsetFraction:
              SagaMapCoordinates.kDefaultAlongEdgeInsetFraction);
      final end = _pixel(const SagaPoint(0.5, 1.0),
          alongEdgeInsetFraction:
              SagaMapCoordinates.kDefaultAlongEdgeInsetFraction);

      expect(start.y, closeTo(0.08 * 500, 1e-9));
      expect(end.y, closeTo(500 - 0.08 * 500, 1e-9));
    });

    test('the inset is capped so the span cannot collapse', () {
      final start =
          _pixel(const SagaPoint(0.5, 0.0), alongEdgeInsetFraction: 0.9);
      expect(
        start.y,
        closeTo(SagaMapCoordinates.kMaxAlongEdgeInsetFraction * 500, 1e-9),
      );
    });
  });

  group('horizontal path', () {
    test('along lands on width, lateral on height', () {
      final point = _pixel(
        const SagaPoint(0.25, 0.5),
        pathAxis: SagaMapPathAxis.horizontal,
      );
      expect(point.x, 500);
      expect(point.y, 125);
    });

    test('reversing mirrors the along axis only', () {
      const position = SagaPoint(0.25, 0.2);
      final forward = _pixel(position, pathAxis: SagaMapPathAxis.horizontal);
      final reversed = _pixel(
        position,
        pathAxis: SagaMapPathAxis.horizontal,
        reverseAlongAxis: true,
      );

      expect(reversed.x, closeTo(_chunk.width - forward.x, 1e-9));
      expect(reversed.y, closeTo(forward.y, 1e-9));
    });
  });

  group('lateral bounds', () {
    test('a symmetric band needs no correction', () {
      const bounds = SagaLateralBounds(min: 0.2, max: 0.8);
      expect(bounds.center, 0.5);
      expect(bounds.centeringOffset, 0);
      expect(bounds.span, closeTo(0.6, 1e-12));

      final point = _pixel(const SagaPoint(0.2, 0.0), lateralBounds: bounds);
      expect(point.x, closeTo(200, 1e-9));
    });

    test('an off-centre band is shifted onto the middle', () {
      const bounds = SagaLateralBounds(min: 0.2, max: 0.6);
      expect(bounds.centeringOffset, closeTo(0.1, 1e-12));

      // Band edges land symmetrically about the chunk centre.
      final low = _pixel(const SagaPoint(0.2, 0.0), lateralBounds: bounds);
      final high = _pixel(const SagaPoint(0.6, 0.0), lateralBounds: bounds);
      expect((low.x + high.x) / 2, closeTo(_chunk.width / 2, 1e-9));
    });

    test('the offset does not depend on the chunk index', () {
      const bounds = SagaLateralBounds(min: 0.2, max: 0.6);
      final inChunk0 =
          _pixel(const SagaPoint(0.2, 0.0), lateralBounds: bounds, span: 1.0);
      final inChunk7 = _pixel(
        const SagaPoint(0.2, 7.0),
        chunkIndex: 7,
        span: 1.0,
        lateralBounds: bounds,
      );
      expect(inChunk7.x, closeTo(inChunk0.x, 1e-9));
    });
  });

  group('lateral padding', () {
    test('keeps the band off both edges', () {
      final low = _pixel(const SagaPoint(0.0, 0.0), lateralPaddingPx: 40);
      final high = _pixel(const SagaPoint(1.0, 0.0), lateralPaddingPx: 40);
      expect(low.x, closeTo(40, 1e-9));
      expect(high.x, closeTo(_chunk.width - 40, 1e-9));
    });

    test('cannot invert the band', () {
      // Padding wider than half the extent would otherwise fold it inside out.
      final low = _pixel(const SagaPoint(0.0, 0.0), lateralPaddingPx: 4000);
      final high = _pixel(const SagaPoint(1.0, 0.0), lateralPaddingPx: 4000);
      expect(low.x, closeTo(_chunk.width / 2, 1e-9));
      expect(high.x, closeTo(_chunk.width / 2, 1e-9));
    });
  });

  test('an unclamped neighbour resolves outside the chunk', () {
    final point = _pixel(
      const SagaPoint(0.5, -0.1),
      clampAlongAxis: false,
    );
    expect(point.y, lessThan(0));
  });
}
