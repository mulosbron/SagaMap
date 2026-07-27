import 'package:flutter/material.dart';

import '../contracts/saga_map_render_context.dart';
import '../contracts/saga_map_renderer.dart';
import '../painters/map_chunk_painter.dart';
import '../theme/saga_biome_theme_resolver.dart';

/// Renders a chunk's path and biome background as a [CustomPainter].
class PainterRendererAdapter implements SagaMapRenderer<CustomPainter> {
  final SagaBiomeThemeResolver biomeThemeResolver;
  final bool paintBaseBackground;

  const PainterRendererAdapter({
    required this.biomeThemeResolver,
    this.paintBaseBackground = true,
  });

  @override
  CustomPainter render(SagaMapRenderContext context) {
    return MapChunkPainter(
      renderContext: context,
      biomeThemeResolver: biomeThemeResolver,
      paintBaseBackground: paintBaseBackground,
    );
  }
}
