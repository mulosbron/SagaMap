import 'dart:math' as math;

import '../../core/domain/models/saga_geometry.dart';
import 'saga_path_geometry.dart';

/// Where something sits on the path, and which way it is heading.
class SagaPathPose {
  /// Pixel position, in the same chunk-local space the nodes use.
  final SagaPoint position;

  /// Direction of travel as a unit vector.
  final SagaPoint direction;

  const SagaPathPose({required this.position, required this.direction});

  /// Heading in radians, measured from the positive x axis.
  double get headingRadians => math.atan2(direction.y, direction.x);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaPathPose &&
          other.position == position &&
          other.direction == direction);

  @override
  int get hashCode => Object.hash(position, direction);

  @override
  String toString() => 'SagaPathPose($position, heading $headingRadians)';
}

/// Arc-length measurements over a path, so something can travel it at an even
/// pace.
///
/// A cubic's parameter `t` is not proportional to distance: stepping `t` evenly
/// makes a walker crawl through the tight parts of a curve and race down the
/// straight parts. Visible, and it reads as cheap. This class samples each
/// piece once, builds a cumulative length table, and inverts it so callers can
/// ask for a distance instead.
///
/// Build it once per path shape and reuse it; sampling on every frame would
/// undo the point of it.
class SagaPathMetrics {
  /// Samples taken per curved piece when building the length table.
  ///
  /// Straight pieces are not sampled at all — their length is the chord and
  /// `t` already is the distance fraction, which makes the common
  /// zero-curvature path free.
  static const int kDefaultSamplesPerSegment = 24;

  final List<SagaPathSegment> segments;
  final int samplesPerSegment;

  /// Cumulative arc length at each sample, per segment. Empty for a straight
  /// segment.
  final List<List<double>> _tables;
  final List<double> _segmentLengths;
  final List<double> _cumulativeLengths;

  SagaPathMetrics._(
    this.segments,
    this.samplesPerSegment,
    this._tables,
    this._segmentLengths,
    this._cumulativeLengths,
  );

  factory SagaPathMetrics(
    List<SagaPathSegment> segments, {
    int samplesPerSegment = kDefaultSamplesPerSegment,
  }) {
    assert(samplesPerSegment >= 2, 'samplesPerSegment must be at least 2');

    final tables = <List<double>>[];
    final lengths = <double>[];
    final cumulative = <double>[0];

    for (final segment in segments) {
      if (segment.isStraight) {
        tables.add(const <double>[]);
        lengths.add(_distance(segment.start, segment.end));
      } else {
        final table = <double>[0];
        var previous = segment.pointAt(0);
        var running = 0.0;
        for (var i = 1; i <= samplesPerSegment; i++) {
          final current = segment.pointAt(i / samplesPerSegment);
          running += _distance(previous, current);
          table.add(running);
          previous = current;
        }
        tables.add(table);
        lengths.add(running);
      }
      cumulative.add(cumulative.last + lengths.last);
    }

    return SagaPathMetrics._(
      List<SagaPathSegment>.unmodifiable(segments),
      samplesPerSegment,
      tables,
      lengths,
      cumulative,
    );
  }

  /// Total arc length of the whole path.
  double get totalLength => _cumulativeLengths.last;

  /// Arc length of one segment.
  double lengthOfSegment(int index) => _segmentLengths[index];

  /// Parameter `t` that lies [fraction] of the way along [index] by distance.
  ///
  /// This is the inverse of the length table: [fraction] `0.5` returns the `t`
  /// at the halfway *point*, not the halfway *parameter*.
  double tAtFraction(int index, double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    final table = _tables[index];
    if (table.isEmpty) return clamped; // straight: t is already the fraction

    final total = table.last;
    if (total == 0) return clamped;

    final target = total * clamped;
    // Table is monotonic, so a binary search finds the bracketing samples.
    var low = 0;
    var high = table.length - 1;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (table[middle] <= target) {
        low = middle;
      } else {
        high = middle;
      }
    }

    final spanLength = table[high] - table[low];
    final within = spanLength == 0 ? 0.0 : (target - table[low]) / spanLength;
    return (low + within) / samplesPerSegment;
  }

  /// Pose [fraction] of the way along segment [index], measured by distance.
  SagaPathPose poseOnSegment(int index, double fraction) {
    final segment = segments[index];
    final t = tAtFraction(index, fraction);
    return SagaPathPose(
      position: segment.pointAt(t),
      direction: _normalise(segment.tangentAt(t)),
    );
  }

  /// Pose at [distance] measured from the start of the whole path.
  SagaPathPose poseAtDistance(double distance) {
    if (segments.isEmpty) {
      return const SagaPathPose(
        position: SagaPoint(0, 0),
        direction: SagaPoint(1, 0),
      );
    }
    final clamped = distance.clamp(0.0, totalLength);
    for (var i = 0; i < segments.length; i++) {
      final end = _cumulativeLengths[i + 1];
      if (clamped <= end || i == segments.length - 1) {
        final within = clamped - _cumulativeLengths[i];
        final length = _segmentLengths[i];
        return poseOnSegment(i, length == 0 ? 0 : within / length);
      }
    }
    return poseOnSegment(segments.length - 1, 1);
  }
}

double _distance(SagaPoint a, SagaPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy);
}

SagaPoint _normalise(SagaPoint vector) {
  final length = math.sqrt(vector.x * vector.x + vector.y * vector.y);
  if (length == 0 || !length.isFinite) return const SagaPoint(1, 0);
  return SagaPoint(vector.x / length, vector.y / length);
}
