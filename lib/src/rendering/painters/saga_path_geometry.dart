import 'dart:math' as math;

import '../../core/domain/models/saga_geometry.dart';

/// How many levels beyond each end of a chunk the renderer needs in order to
/// curve the path identically on both sides of a seam.
///
/// A curved segment's shape depends on the level before it and the level after
/// it, so the segment that straddles a chunk boundary needs two levels of
/// context on each side. With fewer, the two chunks would each draw their own
/// slightly different version of the same segment and the join would kink.
const int kSagaPathNeighborCount = 2;

/// One cubic Bézier piece of the rendered path.
///
/// A straight run is still expressed as a cubic, with both control points
/// collapsed onto the endpoints — see [isStraight].
class SagaPathSegment {
  final SagaPoint start;
  final SagaPoint control1;
  final SagaPoint control2;
  final SagaPoint end;

  const SagaPathSegment({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  /// True when the piece is a plain line: both controls sit on the endpoints.
  bool get isStraight => control1 == start && control2 == end;

  /// Point at parameter [t] along the piece, `t` in `0..1`.
  SagaPoint pointAt(double t) {
    final u = 1 - t;
    final a = u * u * u;
    final b = 3 * u * u * t;
    final c = 3 * u * t * t;
    final d = t * t * t;
    return SagaPoint(
      a * start.x + b * control1.x + c * control2.x + d * end.x,
      a * start.y + b * control1.y + c * control2.y + d * end.y,
    );
  }

  /// Direction of travel at parameter [t], as a non-normalised vector.
  ///
  /// Falls back to the chord when the derivative vanishes. That is not an
  /// exotic case: a straight piece carries its controls on the endpoints, and
  /// its derivative is exactly zero at both ends — reading the raw derivative
  /// there would leave a walking character with no heading at every node.
  SagaPoint tangentAt(double t) {
    final u = 1 - t;
    final derivative = (control1 - start) * (3 * u * u) +
        (control2 - control1) * (6 * u * t) +
        (end - control2) * (3 * t * t);
    if (derivative.x.abs() > 1e-9 || derivative.y.abs() > 1e-9) {
      return derivative;
    }
    return end - start;
  }

  /// Splits the piece at parameter [t] into two that trace the same curve.
  ///
  /// De Casteljau subdivision, so the halves are geometrically identical to the
  /// original — no resampling, no drift where they meet. Used to paint the
  /// walked part of the path differently from the part still ahead.
  ({SagaPathSegment before, SagaPathSegment after}) splitAt(double t) {
    final clamped = t.clamp(0.0, 1.0);
    SagaPoint lerp(SagaPoint a, SagaPoint b) => a + (b - a) * clamped;

    final p01 = lerp(start, control1);
    final p12 = lerp(control1, control2);
    final p23 = lerp(control2, end);
    final p012 = lerp(p01, p12);
    final p123 = lerp(p12, p23);
    final split = lerp(p012, p123);

    return (
      before: SagaPathSegment(
        start: start,
        control1: p01,
        control2: p012,
        end: split,
      ),
      after: SagaPathSegment(
        start: split,
        control1: p123,
        control2: p23,
        end: end,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaPathSegment &&
          other.start == start &&
          other.control1 == control1 &&
          other.control2 == control2 &&
          other.end == end);

  @override
  int get hashCode => Object.hash(start, control1, control2, end);

  @override
  String toString() =>
      'SagaPathSegment($start -> $control1 -> $control2 -> $end)';
}

/// Builds the path connecting [points] as a list of cubic pieces.
///
/// [curvature] runs from `0` for straight lines to `1` for the roundest curve
/// the spline can draw without doubling back. Values outside that range are
/// clamped.
///
/// The spline interpolates: every input point lies exactly on the curve, so
/// raising the curvature bends the line between nodes without moving the nodes
/// themselves. At `0` the control points collapse onto the endpoints and the
/// result is bit-for-bit the straight polyline.
///
/// Each control handle points along the direction from the previous node to the
/// next — so the curve enters and leaves a node on a single smooth tangent —
/// and its length is capped at half the segment it belongs to. That cap is what
/// makes `1` safe: a longer handle would push the control past the far endpoint
/// and fold the segment into a cusp.
List<SagaPathSegment> buildSagaPathSegments(
  List<SagaPoint> points, {
  required double curvature,
}) {
  assert(!curvature.isNaN, 'curvature must be a number');

  if (points.length < 2) return const <SagaPathSegment>[];

  final tension = curvature.isNaN ? 0.0 : curvature.clamp(0.0, 1.0);
  final segments = <SagaPathSegment>[];

  SagaPathSegment straight(SagaPoint start, SagaPoint end) => SagaPathSegment(
        start: start,
        control1: start,
        control2: end,
        end: end,
      );

  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];

    if (tension == 0) {
      segments.add(straight(start, end));
      continue;
    }

    final chord = end - start;
    final chordLength = math.sqrt(chord.x * chord.x + chord.y * chord.y);
    if (chordLength == 0) {
      // Coincident nodes: there is no direction to curve along.
      segments.add(straight(start, end));
      continue;
    }

    // Clamped ends: with no node beyond the terminus, treat the terminus as its
    // own neighbour, which leaves the tangent along the segment itself.
    final before = i > 0 ? points[i - 1] : start;
    final after = i + 2 < points.length ? points[i + 2] : end;

    final handle = tension * 0.5 * chordLength;
    segments.add(
      SagaPathSegment(
        start: start,
        control1: start + _unit(end - before) * handle,
        control2: end - _unit(after - start) * handle,
        end: end,
      ),
    );
  }

  return List<SagaPathSegment>.unmodifiable(segments);
}

/// Unit vector along [vector], or the zero vector when it has no length.
///
/// A zero result collapses the control onto its endpoint, which degrades that
/// side of the segment to straight rather than producing NaN coordinates.
SagaPoint _unit(SagaPoint vector) {
  final length = math.sqrt(vector.x * vector.x + vector.y * vector.y);
  if (length == 0 || !length.isFinite) return const SagaPoint(0, 0);
  return SagaPoint(vector.x / length, vector.y / length);
}
