/// Named responsive breakpoints used by map layout policies.
enum SagaMapBreakpointName { mobile, tablet, desktop, ultra4k }

/// Which screen axis the level path advances along.
///
/// This is the single source of truth for map orientation: it drives coordinate
/// mapping, which viewport dimension is treated as lateral, and the scroll
/// direction of [SagaInfiniteMapView]. The orthogonal axis carries the lateral
/// zig-zag.
enum SagaMapPathAxis {
  /// Path advances down the screen; levels zig-zag across screen X.
  vertical,

  /// Path advances across the screen; levels zig-zag along screen Y.
  horizontal,
}

/// Numeric range bound to a breakpoint name.
class SagaMapBreakpoint {
  final double start;
  final double end;
  final SagaMapBreakpointName name;

  const SagaMapBreakpoint({
    required this.start,
    required this.end,
    required this.name,
  });

  /// Returns true when [width] is inside this breakpoint interval.
  bool contains(double width) => width >= start && width <= end;
}

/// Per-breakpoint numeric policy used for scale and spacing knobs.
class SagaMapValuePolicy {
  final double mobile;
  final double tablet;
  final double desktop;
  final double ultra4k;

  const SagaMapValuePolicy({
    required this.mobile,
    required this.tablet,
    required this.desktop,
    required this.ultra4k,
  });

  /// Uniform policy: the same value at every breakpoint.
  const SagaMapValuePolicy.all(double value)
      : mobile = value,
        tablet = value,
        desktop = value,
        ultra4k = value;

  /// Resolves value for a specific breakpoint.
  double resolve(SagaMapBreakpointName breakpoint) {
    switch (breakpoint) {
      case SagaMapBreakpointName.mobile:
        return mobile;
      case SagaMapBreakpointName.tablet:
        return tablet;
      case SagaMapBreakpointName.desktop:
        return desktop;
      case SagaMapBreakpointName.ultra4k:
        return ultra4k;
    }
  }
}

/// Complete responsive config used by [SagaResponsiveResolver].
///
/// Every policy here is read by the rendering layer. If a knob would have no
/// effect, it does not belong in this class.
class SagaMapResponsiveConfig {
  final List<SagaMapBreakpoint> breakpoints;

  /// Multiplies the visual size of each node.
  final SagaMapValuePolicy nodeSizePolicy;

  /// Multiplies the chunk's extent along the path axis, and with it the gap
  /// between consecutive nodes.
  final SagaMapValuePolicy nodeSpacingPolicy;

  /// Multiplies node size and path stroke widths together, as a single
  /// viewport-driven zoom level.
  final SagaMapValuePolicy zoomPolicy;

  /// Multiplies a node's touch target relative to its visual size. Values above
  /// `1` make nodes easier to hit without making them look bigger.
  final SagaMapValuePolicy interactionRadiusPolicy;

  /// Padding in pixels reserved at each end of the lateral axis, keeping nodes
  /// off the map's edges.
  final SagaMapValuePolicy cameraPaddingPolicy;

  /// Caps the map's extent along the *lateral* axis, in pixels.
  ///
  /// Vertical maps: content width. Horizontal maps: content height. Never
  /// constrains the path axis — a horizontal map is free to run as long as it
  /// needs to. `null` means unconstrained.
  final SagaMapValuePolicy? maxLateralExtentPolicy;

  /// Multiplies drag distance while scrolling the map.
  final SagaMapValuePolicy scrollSensitivityPolicy;

  final SagaMapPathAxis pathAxis;

  const SagaMapResponsiveConfig({
    required this.breakpoints,
    required this.nodeSizePolicy,
    required this.nodeSpacingPolicy,
    required this.zoomPolicy,
    required this.interactionRadiusPolicy,
    required this.cameraPaddingPolicy,
    required this.maxLateralExtentPolicy,
    required this.scrollSensitivityPolicy,
    required this.pathAxis,
  });

  /// Built-in defaults tuned for mobile-first map readability.
  static const SagaMapResponsiveConfig defaults = SagaMapResponsiveConfig(
    breakpoints: [
      SagaMapBreakpoint(start: 0, end: 450, name: SagaMapBreakpointName.mobile),
      SagaMapBreakpoint(
          start: 451, end: 900, name: SagaMapBreakpointName.tablet),
      SagaMapBreakpoint(
          start: 901, end: 1920, name: SagaMapBreakpointName.desktop),
      SagaMapBreakpoint(
          start: 1921,
          end: double.infinity,
          name: SagaMapBreakpointName.ultra4k),
    ],
    nodeSizePolicy: SagaMapValuePolicy(
        mobile: 1.15, tablet: 1.0, desktop: 0.95, ultra4k: 0.95),
    nodeSpacingPolicy: SagaMapValuePolicy(
        mobile: 0.9, tablet: 1.0, desktop: 1.15, ultra4k: 1.1),
    zoomPolicy: SagaMapValuePolicy(
        mobile: 1.05, tablet: 1.0, desktop: 0.95, ultra4k: 0.9),
    interactionRadiusPolicy: SagaMapValuePolicy(
        mobile: 1.2, tablet: 1.0, desktop: 0.9, ultra4k: 0.9),
    cameraPaddingPolicy:
        SagaMapValuePolicy(mobile: 12, tablet: 16, desktop: 24, ultra4k: 32),
    maxLateralExtentPolicy: SagaMapValuePolicy(
      mobile: double.infinity,
      tablet: double.infinity,
      desktop: 1366,
      ultra4k: 1600,
    ),
    scrollSensitivityPolicy: SagaMapValuePolicy(
        mobile: 0.85, tablet: 1.0, desktop: 1.1, ultra4k: 1.0),
    pathAxis: SagaMapPathAxis.vertical,
  );

  /// Returns a copy with updated policy values.
  ///
  /// [maxLateralExtentPolicy] is nullable — `null` means "unconstrained" — so
  /// it is passed as a getter rather than a value: omit it to keep the current
  /// policy, pass `() => null` to lift the constraint deliberately. Without
  /// that split, `null` meant "leave it alone" and the documented
  /// unconstrained state was unreachable once a policy had been set.
  SagaMapResponsiveConfig copyWith({
    List<SagaMapBreakpoint>? breakpoints,
    SagaMapValuePolicy? nodeSizePolicy,
    SagaMapValuePolicy? nodeSpacingPolicy,
    SagaMapValuePolicy? zoomPolicy,
    SagaMapValuePolicy? interactionRadiusPolicy,
    SagaMapValuePolicy? cameraPaddingPolicy,
    SagaMapValuePolicy? Function()? maxLateralExtentPolicy,
    SagaMapValuePolicy? scrollSensitivityPolicy,
    SagaMapPathAxis? pathAxis,
  }) {
    return SagaMapResponsiveConfig(
      breakpoints: breakpoints ?? this.breakpoints,
      nodeSizePolicy: nodeSizePolicy ?? this.nodeSizePolicy,
      nodeSpacingPolicy: nodeSpacingPolicy ?? this.nodeSpacingPolicy,
      zoomPolicy: zoomPolicy ?? this.zoomPolicy,
      interactionRadiusPolicy:
          interactionRadiusPolicy ?? this.interactionRadiusPolicy,
      cameraPaddingPolicy: cameraPaddingPolicy ?? this.cameraPaddingPolicy,
      maxLateralExtentPolicy: maxLateralExtentPolicy == null
          ? this.maxLateralExtentPolicy
          : maxLateralExtentPolicy(),
      scrollSensitivityPolicy:
          scrollSensitivityPolicy ?? this.scrollSensitivityPolicy,
      pathAxis: pathAxis ?? this.pathAxis,
    );
  }
}
