import 'package:flutter/material.dart';

import '../../core/domain/models/saga_geometry.dart';
import '../../core/domain/saga_dominant_biome.dart';
import '../contracts/saga_map_render_context.dart';
import '../theme/saga_biome_theme.dart';
import 'saga_path_geometry.dart';
import '../theme/saga_biome_theme_resolver.dart';

/// Paints one chunk's biome background and the path connecting its levels.
class MapChunkPainter extends CustomPainter {
  final SagaMapRenderContext renderContext;
  final SagaBiomeThemeResolver biomeThemeResolver;
  final bool paintBaseBackground;

  MapChunkPainter({
    required this.renderContext,
    required this.biomeThemeResolver,
    this.paintBaseBackground = true,
  });

  /// Resolved once per painter rather than per frame: scanning every level for
  /// the dominant biome does not depend on canvas size.
  late final SagaBiomeTheme _theme =
      biomeThemeResolver.resolve(getDominantBiomeId(renderContext.levels));

  @override
  void paint(Canvas canvas, Size size) {
    final levels = renderContext.levels;
    if (levels.isEmpty) return;

    final theme = _theme;
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);

    if (paintBaseBackground) {
      final backgroundPaint = Paint()..style = PaintingStyle.fill;
      if (theme.backgroundGradient != null) {
        backgroundPaint.shader = theme.backgroundGradient!.createShader(bounds);
      } else {
        backgroundPaint.color = theme.backgroundColor;
      }
      canvas.drawRect(bounds, backgroundPaint);
    }

    // Re-resolve against the actual canvas size: a host may paint this into a
    // box that differs from the one the context was built for.
    final ctx = renderContext.withChunkSize(
      SagaSize(width: size.width, height: size.height),
    );
    // Includes the neighbouring chunks' adjacent levels, so the line runs out
    // to the chunk edges and joins the next chunk's line there. The clip below
    // trims whatever falls outside.
    final split = ctx.splitPathAtProgress();
    if (split.walked.isEmpty && split.upcoming.isEmpty) {
      // A pathless chunk is still part of the biome, so it still gets the wash.
      _paintAmbientTint(canvas, bounds, theme);
      return;
    }

    final zoom = ctx.layout.zoom;

    canvas.save();
    canvas.clipRect(bounds);
    // Upcoming first: where the two meet, the covered stretch sits on top, so
    // the join reads as the player's progress rather than as a seam.
    _strokePath(
      canvas,
      split.upcoming,
      borderColor: theme.upcomingPathBorderColor ?? theme.pathBorderColor,
      fillColor: theme.upcomingPathFillColor ?? theme.pathFillColor,
      borderWidth: theme.pathBorderWidth * zoom,
      fillWidth: theme.pathInnerStrokeWidth * zoom,
    );
    _strokePath(
      canvas,
      split.walked,
      borderColor: theme.pathBorderColor,
      fillColor: theme.pathFillColor,
      borderWidth: theme.pathBorderWidth * zoom,
      fillWidth: theme.pathInnerStrokeWidth * zoom,
    );

    // The wash goes over background and path alike, still inside the clip.
    // Node widgets are drawn above this layer and stay untinted.
    _paintAmbientTint(canvas, bounds, theme);
    canvas.restore();
  }

  /// Paints [SagaBiomeTheme.ambientTint], if the biome sets one.
  void _paintAmbientTint(Canvas canvas, Rect bounds, SagaBiomeTheme theme) {
    final tint = theme.ambientTint;
    if (tint == null) return;
    canvas.drawRect(bounds, Paint()..color = tint);
  }

  void _strokePath(
    Canvas canvas,
    List<SagaPathSegment> segments, {
    required Color borderColor,
    required Color fillColor,
    required double borderWidth,
    required double fillWidth,
  }) {
    if (segments.isEmpty) return;

    final path = Path()..moveTo(segments.first.start.x, segments.first.start.y);
    for (final segment in segments) {
      // A zero-curvature segment carries its controls on the endpoints, so this
      // draws exactly the straight polyline.
      path.cubicTo(
        segment.control1.x,
        segment.control1.y,
        segment.control2.x,
        segment.control2.y,
        segment.end.x,
        segment.end.y,
      );
    }

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = borderWidth
      ..color = borderColor;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = fillWidth
      ..color = fillColor;

    canvas.drawPath(path, border);
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant MapChunkPainter oldDelegate) {
    return oldDelegate.renderContext != renderContext ||
        oldDelegate.biomeThemeResolver != biomeThemeResolver ||
        oldDelegate.paintBaseBackground != paintBaseBackground;
  }
}
