import 'dart:math' as math;

import '../models/resolved_saga_layout.dart';
import '../models/saga_geometry.dart';
import 'saga_map_responsive_config.dart';

/// Resolves responsive map layout values from the viewport.
class SagaResponsiveResolver {
  final SagaMapResponsiveConfig config;

  const SagaResponsiveResolver(
      {this.config = SagaMapResponsiveConfig.defaults});

  /// Resolves the named breakpoint for a viewport [width].
  ///
  /// Breakpoints always key off viewport *width*, on both orientations — width
  /// is what indicates the device class. A horizontal map on a phone is still a
  /// phone, and must not resolve desktop sizing just because its content lane
  /// is long.
  SagaMapBreakpointName resolveBreakpoint(double width) {
    for (final bp in config.breakpoints) {
      if (bp.contains(width)) {
        return bp.name;
      }
    }
    return SagaMapBreakpointName.desktop;
  }

  /// Resolves a layout profile from viewport [width] alone.
  ///
  /// [ResolvedSagaLayout.maxLateralExtent] carries the raw policy value here,
  /// unclamped. Prefer [resolveForViewport] for rendering, which clamps it to
  /// the viewport's actual lateral dimension.
  ResolvedSagaLayout resolveForWidth(double width) {
    final breakpoint = resolveBreakpoint(width);

    return ResolvedSagaLayout(
      breakpoint: breakpoint,
      pathAxis: config.pathAxis,
      nodeSize: config.nodeSizePolicy.resolve(breakpoint),
      nodeSpacing: config.nodeSpacingPolicy.resolve(breakpoint),
      zoom: config.zoomPolicy.resolve(breakpoint),
      interactionRadius: config.interactionRadiusPolicy.resolve(breakpoint),
      cameraPadding: config.cameraPaddingPolicy.resolve(breakpoint),
      scrollSensitivity: config.scrollSensitivityPolicy.resolve(breakpoint),
      maxLateralExtent:
          config.maxLateralExtentPolicy?.resolve(breakpoint) ?? double.infinity,
    );
  }

  /// Resolves a layout profile for a full [viewport].
  ///
  /// The lateral cap is applied to the axis orthogonal to
  /// [SagaMapResponsiveConfig.pathAxis] — width for vertical maps, height for
  /// horizontal ones — so it never shortens the direction the path travels in.
  ResolvedSagaLayout resolveForViewport(SagaSize viewport) {
    final layout = resolveForWidth(viewport.width);
    final lateralViewport = lateralExtentOf(viewport);
    return layout.copyWith(
      maxLateralExtent: layout.maxLateralExtent.isFinite
          ? math.min(lateralViewport, layout.maxLateralExtent)
          : lateralViewport,
    );
  }

  /// Viewport dimension that lies on the lateral axis.
  double lateralExtentOf(SagaSize viewport) {
    switch (config.pathAxis) {
      case SagaMapPathAxis.vertical:
        return viewport.width;
      case SagaMapPathAxis.horizontal:
        return viewport.height;
    }
  }
}
