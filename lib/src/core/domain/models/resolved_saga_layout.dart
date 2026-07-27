import '../responsive/saga_map_responsive_config.dart';

/// Fully resolved responsive values for a concrete viewport.
///
/// All axis-dependent values are expressed in terms of the map's *path axis*
/// (the direction levels advance) and its *lateral axis* (the orthogonal
/// direction the path zig-zags across), never in terms of screen width or
/// height. Use [pathAxis] to map them back onto screen axes.
class ResolvedSagaLayout {
  final SagaMapBreakpointName breakpoint;
  final SagaMapPathAxis pathAxis;

  /// Multiplier on a node's visual size.
  final double nodeSize;

  /// Multiplier on the chunk's extent along the path axis, and therefore on the
  /// gap between consecutive nodes.
  final double nodeSpacing;

  /// Viewport-driven zoom applied to node size and path stroke widths.
  final double zoom;

  /// Multiplier on a node's touch target relative to its visual size.
  final double interactionRadius;

  /// Pixels reserved at each end of the lateral axis.
  final double cameraPadding;

  /// Multiplier on drag distance while scrolling.
  final double scrollSensitivity;

  /// Maximum extent of the map content along the *lateral* axis, in pixels.
  ///
  /// Vertical maps: content width. Horizontal maps: content height. Content is
  /// centered within the viewport when this is smaller than the viewport's
  /// lateral dimension.
  final double maxLateralExtent;

  const ResolvedSagaLayout({
    required this.breakpoint,
    required this.pathAxis,
    required this.nodeSize,
    required this.nodeSpacing,
    required this.zoom,
    required this.interactionRadius,
    required this.cameraPadding,
    required this.scrollSensitivity,
    required this.maxLateralExtent,
  });

  /// Returns a copy with selective field overrides.
  ResolvedSagaLayout copyWith({
    SagaMapBreakpointName? breakpoint,
    SagaMapPathAxis? pathAxis,
    double? nodeSize,
    double? nodeSpacing,
    double? zoom,
    double? interactionRadius,
    double? cameraPadding,
    double? scrollSensitivity,
    double? maxLateralExtent,
  }) {
    return ResolvedSagaLayout(
      breakpoint: breakpoint ?? this.breakpoint,
      pathAxis: pathAxis ?? this.pathAxis,
      nodeSize: nodeSize ?? this.nodeSize,
      nodeSpacing: nodeSpacing ?? this.nodeSpacing,
      zoom: zoom ?? this.zoom,
      interactionRadius: interactionRadius ?? this.interactionRadius,
      cameraPadding: cameraPadding ?? this.cameraPadding,
      scrollSensitivity: scrollSensitivity ?? this.scrollSensitivity,
      maxLateralExtent: maxLateralExtent ?? this.maxLateralExtent,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedSagaLayout &&
        other.breakpoint == breakpoint &&
        other.pathAxis == pathAxis &&
        other.nodeSize == nodeSize &&
        other.nodeSpacing == nodeSpacing &&
        other.zoom == zoom &&
        other.interactionRadius == interactionRadius &&
        other.cameraPadding == cameraPadding &&
        other.scrollSensitivity == scrollSensitivity &&
        other.maxLateralExtent == maxLateralExtent;
  }

  @override
  int get hashCode => Object.hash(
        breakpoint,
        pathAxis,
        nodeSize,
        nodeSpacing,
        zoom,
        interactionRadius,
        cameraPadding,
        scrollSensitivity,
        maxLateralExtent,
      );
}
