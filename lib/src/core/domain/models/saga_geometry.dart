/// 2D point with normalized or pixel coordinates.
class SagaPoint {
  final double x;
  final double y;

  const SagaPoint(this.x, this.y);

  /// Componentwise sum.
  SagaPoint operator +(SagaPoint other) => SagaPoint(x + other.x, y + other.y);

  /// Componentwise difference.
  SagaPoint operator -(SagaPoint other) => SagaPoint(x - other.x, y - other.y);

  /// Scales both components by [factor].
  SagaPoint operator *(double factor) => SagaPoint(x * factor, y * factor);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaPoint && other.x == x && other.y == y);

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'SagaPoint($x, $y)';
}

/// Width/height pair used by map layout calculations.
class SagaSize {
  final double width;
  final double height;

  const SagaSize({
    required this.width,
    required this.height,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaSize && other.width == width && other.height == height);

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'SagaSize($width x $height)';
}

/// Normalized `0..1` band the level path zig-zags within, on the lateral axis.
///
/// Used to center the path band consistently across every chunk. Deriving the
/// band from generator configuration rather than from a chunk's own levels is
/// what keeps chunk N and chunk N+1 aligned — a chunk-local measurement drifts,
/// because each chunk's sampled levels have a slightly different spread.
class SagaLateralBounds {
  final double min;
  final double max;

  const SagaLateralBounds({required this.min, required this.max})
      : assert(min >= 0.0 && min <= 1.0, 'min must be within 0..1'),
        assert(max >= 0.0 && max <= 1.0, 'max must be within 0..1'),
        assert(min <= max, 'min must not exceed max');

  /// Full lateral range: the path may use the entire lateral extent.
  static const SagaLateralBounds unit = SagaLateralBounds(min: 0.0, max: 1.0);

  /// Normalized center of the band.
  double get center => (min + max) / 2;

  /// Normalized width of the band.
  double get span => max - min;

  /// Signed normalized offset that moves [center] onto `0.5`.
  ///
  /// Zero for any symmetric band, so the common case costs nothing.
  double get centeringOffset => 0.5 - center;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaLateralBounds && other.min == min && other.max == max);

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'SagaLateralBounds($min..$max)';
}
