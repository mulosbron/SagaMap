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
  /// A width that lands in no interval resolves to the widest breakpoint it is
  /// past, not to a hard-coded default. The built-in bounds are inclusive
  /// integers (`0-450`, `451-900`, ...) while this takes a `double`, so `450.5`
  /// — split-screen, a resized web window, browser zoom, a device that is
  /// genuinely `411.42857142857144` wide — used to match nothing and fall
  /// through to `desktop`: the narrowest screen the app supports got desktop
  /// sizing, with touch targets a quarter smaller. Walking back to the last
  /// breakpoint the width has started closes every seam without asking hosts
  /// to restate their own bounds as half-open.
  ///
  /// A width below every breakpoint, or `NaN` (every comparison against which
  /// is false), resolves to the narrowest breakpoint: the more generous
  /// sizing is the safer wrong answer.
  SagaMapBreakpointName resolveBreakpoint(double width) {
    if (config.breakpoints.isEmpty) return SagaMapBreakpointName.desktop;

    SagaMapBreakpoint? narrowest;
    SagaMapBreakpoint? started;
    for (final bp in config.breakpoints) {
      if (bp.contains(width)) return bp.name;
      if (narrowest == null || bp.start < narrowest.start) narrowest = bp;
      if (width >= bp.start && (started == null || bp.start > started.start)) {
        started = bp;
      }
    }
    return (started ?? narrowest)!.name;
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
