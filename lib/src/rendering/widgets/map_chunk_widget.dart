import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/saga_geometry.dart';
import '../../core/domain/responsive/saga_map_responsive_config.dart';
import '../../core/domain/responsive/saga_responsive_resolver.dart';
import '../adapters/painter_renderer_adapter.dart';
import '../character/saga_character.dart';
import '../decoration/saga_map_decoration.dart';
import '../adapters/widget_renderer_adapter.dart';
import '../background/saga_map_background.dart';
import '../contracts/saga_chunk_context.dart';
import '../contracts/saga_map_render_context.dart';
import '../interaction/saga_node_interaction_handler.dart';
import '../interaction/saga_node_interaction_policy.dart';
import '../theme/saga_biome_theme_resolver.dart';

/// Renders one map chunk: biome background, connecting path, and interactive
/// level nodes.
///
/// The chunk is laid out along the path axis of
/// [SagaMapResponsiveConfig.pathAxis]. [chunkExtent] always measures that axis
/// — height for vertical maps, width for horizontal ones — and the orthogonal
/// (lateral) axis fills the available space, capped by
/// [ResolvedSagaLayout.maxLateralExtent] and centered within it.
class MapChunkWidget extends StatelessWidget {
  final List<LevelData> levels;
  final int chunkIndex;

  /// Base chunk size in pixels along the path axis.
  ///
  /// Scaled by [ResolvedSagaLayout.nodeSpacing], so the gap between consecutive
  /// nodes follows the breakpoint. Every chunk scales identically, so chunks
  /// still tile exactly.
  final double chunkExtent;

  /// Normalized span this chunk covers along the path axis.
  ///
  /// Must equal `stepHeight * levelsPerChunk` for the generating config; see
  /// [SagaMapConfig.spanForLevelCount]. A mismatch pushes out-of-range levels
  /// onto the chunk edge (asserts in debug builds).
  final double chunkSpanNormalized;

  final SagaBiomeThemeResolver biomeThemeResolver;
  final SagaResponsiveResolver responsiveResolver;
  final SagaNodeBuilder nodeBuilder;
  final SagaNodeProgressResolver? progressResolver;
  final ValueChanged<LevelData>? onLevelTap;

  /// Convenience shortcut, mirroring [onLevelTap]. Ignored when interactionHandler.onNodeLongPress is set.
  final ValueChanged<LevelData>? onLevelLongPress;
  final SagaNodeInteractionHandler interactionHandler;
  final SagaNodeInteractionPolicy interactionPolicy;
  final SagaMapBackgroundConfig backgroundConfig;

  /// Lateral band the levels were generated within.
  ///
  /// Pass [SagaMapConfig.lateralBounds] so the band is centered identically in
  /// every chunk. Defaults to the full range, which applies no re-centering.
  final SagaLateralBounds lateralBounds;

  /// Inset at each end of the path axis, as a fraction of [chunkExtent].
  ///
  /// Defaults to `0`, which keeps node spacing uniform across chunk seams. A
  /// non-zero value pulls end nodes inward and widens the seam.
  final double alongEdgeInsetFraction;

  /// Levels immediately before this chunk, in path order.
  final List<LevelData> leadingNeighbors;

  /// Levels immediately after this chunk, in path order.
  ///
  /// Supply these to draw the path all the way to the chunk's trailing edge;
  /// without them the line stops at the last level and the seam reads as a
  /// break. A curved path needs [kSagaPathNeighborCount] on each side for the
  /// join to stay smooth. [SagaInfiniteMapView] wires them automatically.
  final List<LevelData> trailingNeighbors;

  /// Path roundness: `0` draws straight lines between nodes, `1` a fully
  /// rounded spline. Nodes stay put either way — only the line between them
  /// bends. Values outside `0..1` are clamped.
  final double pathCurvature;

  /// How far the player has reached, as a fractional level index.
  ///
  /// The path is painted in the walked colours up to here and in the theme's
  /// upcoming colours beyond. `null` paints it all one way. Feeding a live
  /// character position repaints the path every frame; the usual value is the
  /// highest level reached, which changes rarely.
  final double? pathProgressPosition;

  /// Logical node size before responsive scaling.
  final double baseNodeSize;

  /// Floor on a node's gesture area, independent of its visual size.
  final double minTouchTarget;

  /// Screen-reader label for each node. Override to localise.
  final SagaNodeSemanticsLabelBuilder semanticsLabelBuilder;

  /// User-driven zoom, multiplied into every dimension of the chunk.
  ///
  /// Applied to the layout rather than as a paint transform: the chunk really
  /// becomes larger, so the enclosing list keeps a correct scroll extent, hit
  /// testing needs no inverse mapping, and the path is rasterised at the final
  /// size instead of being magnified.
  final double userZoom;

  /// Lateral shift in pixels, for panning a chunk that is wider than the
  /// viewport because [userZoom] pushed it past the edges.
  final double lateralPanOffset;

  /// Character standing on the path.
  ///
  /// Every chunk is handed the same character; only the one that owns its
  /// position draws it, so it is never drawn twice near a seam.
  final SagaCharacter? character;

  /// Context handed to [decorationBuilder]. Optional: when omitted it is
  /// derived from [levels], [chunkIndex] and [progressResolver], so hosts that
  /// used this widget before 1.1.0 keep compiling unchanged.
  final SagaChunkContext? chunkContext;
  final SagaMapDecorationBuilder? decorationBuilder;
  final SagaMapLegacyDecorationBuilder? legacyDecorationBuilder;

  /// Identity for the character's widget across chunk hand-offs.
  ///
  /// Ownership moves to the next chunk when the character crosses a seam. A
  /// global key carries the element across, so a running sprite or Rive
  /// animation keeps playing instead of restarting from frame zero.
  final GlobalKey? characterKey;

  const MapChunkWidget({
    super.key,
    required this.levels,
    required this.chunkIndex,
    required this.chunkExtent,
    required this.chunkSpanNormalized,
    required this.biomeThemeResolver,
    this.responsiveResolver = const SagaResponsiveResolver(),
    required this.nodeBuilder,
    this.progressResolver,
    this.onLevelTap,
    this.onLevelLongPress,
    this.interactionHandler = const SagaNodeInteractionHandler(),
    this.interactionPolicy = const SagaNodeInteractionPolicy(),
    this.backgroundConfig = const SagaMapBackgroundConfig.none(),
    this.lateralBounds = SagaLateralBounds.unit,
    this.alongEdgeInsetFraction = 0.0,
    this.leadingNeighbors = const <LevelData>[],
    this.trailingNeighbors = const <LevelData>[],
    this.pathCurvature = 0.0,
    this.pathProgressPosition,
    this.baseNodeSize = kSagaDefaultNodeSize,
    this.minTouchTarget = kSagaMinTouchTarget,
    this.semanticsLabelBuilder = defaultSagaNodeSemanticsLabel,
    this.userZoom = 1.0,
    this.lateralPanOffset = 0.0,
    this.character,
    this.characterKey,
    this.chunkContext,
    this.decorationBuilder,
    this.legacyDecorationBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Resolve responsiveness from the real viewport, never from the chunk's
        // own box: a long horizontal lane must not read as a large device.
        final viewport = MediaQuery.sizeOf(context);
        final resolved = responsiveResolver.resolveForViewport(
          SagaSize(width: viewport.width, height: viewport.height),
        );
        // Folding zoom into the layout scales node size, stroke width and the
        // gap between nodes in one place, so every part of the map grows
        // together instead of drifting out of proportion.
        final layout = userZoom == 1.0
            ? resolved
            : resolved.copyWith(
                zoom: resolved.zoom * userZoom,
                nodeSpacing: resolved.nodeSpacing * userZoom,
              );
        final isVertical = layout.pathAxis == SagaMapPathAxis.vertical;

        // A horizontal chunk list is laid out right-to-left under RTL, so each
        // chunk's interior has to run the same way or the path breaks at the
        // seams. Vertical maps are unaffected by text direction.
        final reverseAlongAxis = !isVertical &&
            Directionality.maybeOf(context) == TextDirection.rtl;

        final availableLateral = _availableLateral(
          constraints: constraints,
          viewport: viewport,
          isVertical: isVertical,
        );
        // Zooming in pushes the content past the viewport laterally; the inset
        // then goes negative, which centres the overflow and lets
        // [lateralPanOffset] slide it.
        final lateralExtent =
            math.min(availableLateral, layout.maxLateralExtent) * userZoom;
        final lateralInset =
            (availableLateral - lateralExtent) / 2 + lateralPanOffset;

        // Spacing scales the path axis only. Applying it uniformly keeps every
        // chunk the same size, so they still tile without seams.
        //
        // Rounded to a whole logical pixel: a fractional extent puts every
        // chunk boundary on a fractional offset, and adjacent chunk backgrounds
        // then antialias against each other into a visible hairline seam.
        final alongExtent = (chunkExtent * layout.nodeSpacing).roundToDouble();

        final chunkSize = isVertical
            ? SagaSize(width: lateralExtent, height: alongExtent)
            : SagaSize(width: alongExtent, height: lateralExtent);

        final renderContext = SagaMapRenderContext(
          levels: levels,
          chunkIndex: chunkIndex,
          chunkSize: chunkSize,
          chunkSpanNormalized: chunkSpanNormalized,
          layout: layout,
          progressResolver: progressResolver,
          lateralBounds: lateralBounds,
          reverseAlongAxis: reverseAlongAxis,
          alongEdgeInsetFraction: alongEdgeInsetFraction,
          leadingNeighbors: leadingNeighbors,
          trailingNeighbors: trailingNeighbors,
          pathCurvature: pathCurvature,
          pathProgressPosition: pathProgressPosition,
        );

        final chunkPainter = PainterRendererAdapter(
          biomeThemeResolver: biomeThemeResolver,
          paintBaseBackground:
              backgroundConfig.kind == SagaMapBackgroundKind.none,
        ).render(renderContext);

        final nodeWidgets = WidgetRendererAdapter(
          context: context,
          nodeBuilder: nodeBuilder,
          interactionHandler: _effectiveInteractionHandler(),
          interactionPolicy: interactionPolicy,
          baseNodeSize: baseNodeSize,
          minTouchTarget: minTouchTarget,
          semanticsLabelBuilder: semanticsLabelBuilder,
        ).render(renderContext);

        // Everything below lives in the content box's coordinate space, so the
        // lateral centering offset is applied exactly once, here.
        //
        // The traversal group makes Tab follow the NumericFocusOrder each node
        // carries — level order — rather than the Stack's paint order.
        final content = FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: SizedBox(
            width: chunkSize.width,
            height: chunkSize.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: backgroundConfig.buildBackgroundWidget(
                    chunkIndex: chunkIndex,
                  ),
                ),
                ..._buildDecorations(context, renderContext),
                Positioned.fill(
                  child: CustomPaint(painter: chunkPainter),
                ),
                ...nodeWidgets,
                if (character != null)
                  Positioned.fill(
                    child: _SagaCharacterLayer(
                      character: character!,
                      renderContext: renderContext,
                      characterKey: characterKey,
                    ),
                  ),
              ],
            ),
          ),
        );

        return SizedBox(
          width: isVertical ? availableLateral : alongExtent,
          height: isVertical ? alongExtent : availableLateral,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: isVertical ? lateralInset : 0,
                top: isVertical ? 0 : lateralInset,
                width: chunkSize.width,
                height: chunkSize.height,
                child: content,
              ),
            ],
          ),
        );
      },
    );
  }

  double _availableLateral({
    required BoxConstraints constraints,
    required Size viewport,
    required bool isVertical,
  }) {
    final bounded = isVertical
        ? constraints.hasBoundedWidth && constraints.maxWidth.isFinite
        : constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
    if (bounded) {
      final value = isVertical ? constraints.maxWidth : constraints.maxHeight;
      if (value > 1) return value;
    }
    return isVertical ? viewport.width : viewport.height;
  }

  /// Scenery for this chunk, positioned but drawn by the host.
  List<Widget> _buildDecorations(
    BuildContext context,
    SagaMapRenderContext renderContext,
  ) {
    List<SagaMapDecoration>? list;
    if (decorationBuilder != null) {
      final chunk = chunkContext ??
          SagaChunkContext(
            chunkIndex: chunkIndex,
            levels: levels,
            progress: {
              for (final level in levels)
                if (progressResolver?.call(level) case final p?) level.id: p,
            },
          );
      list = decorationBuilder!(context, chunk);
    } else if (legacyDecorationBuilder != null) {
      list = legacyDecorationBuilder!(context, chunkIndex);
    }
    if (list == null) return const <Widget>[];

    final decorations = [...list]
      ..sort((a, b) => a.z.compareTo(b.z));

    final widgets = <Widget>[];
    for (final decoration in decorations) {
      // Three placement modes: a free chunk fraction, pinned to a level
      // (`atLevel`), or hugging the path at an explicit position.
      final SagaPoint? point;
      if (decoration.chunkFraction != null) {
        point = renderContext.decorationPixelAtFraction(
          decoration.chunkFraction!.dx,
          decoration.chunkFraction!.dy,
        );
      } else if (decoration.levelId != null) {
        point = renderContext.decorationPixelBesidePath(
          decoration.levelId!.toDouble(),
          decoration.lateralOffset,
        );
      } else {
        point = renderContext.decorationPixelBesidePath(
          decoration.pathPosition!,
          decoration.lateralOffset,
        );
      }
      // Beside-path scenery whose level is beyond this chunk simply is not
      // drawn here; the chunk that owns that level draws it.
      if (point == null) continue;

      final scale =
          decoration.scaleWithZoom ? renderContext.layout.zoom : 1.0;
      // `atLevel` decorations carry a fixed `height` instead of a `size`; give
      // them a square box so they render rather than collapsing to zero.
      final baseSize = decoration.levelId != null && decoration.height != null
          ? Size(decoration.height!, decoration.height!)
          : decoration.size;
      final size = Size(
        baseSize.width * scale,
        baseSize.height * scale,
      );
      final topLeft = decoration.topLeftFor(point, size);
      widgets.add(
        Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          // Scenery never intercepts taps meant for a level.
          child: IgnorePointer(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: decoration.builder(context),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// Lets the convenience callbacks stand in when the handler has none
  /// of its own.
  SagaNodeInteractionHandler _effectiveInteractionHandler() {
    final effectiveTap = interactionHandler.onNodeTap ?? onLevelTap;
    final effectiveLongPress =
        interactionHandler.onNodeLongPress ?? onLevelLongPress;

    if (effectiveTap == interactionHandler.onNodeTap &&
        effectiveLongPress == interactionHandler.onNodeLongPress) {
      return interactionHandler;
    }

    return SagaNodeInteractionHandler(
      onNodeTap: effectiveTap,
      onNodeLongPress: effectiveLongPress,
      onNodeHover: interactionHandler.onNodeHover,
      onNodeFocusChange: interactionHandler.onNodeFocusChange,
    );
  }
}

/// Draws the character, rebuilding only itself while it moves.
///
/// Kept apart from the chunk so a journey does not rebuild the path, the
/// background and every node once per frame.
class _SagaCharacterLayer extends StatelessWidget {
  final SagaCharacter character;
  final SagaMapRenderContext renderContext;
  final GlobalKey? characterKey;

  const _SagaCharacterLayer({
    required this.character,
    required this.renderContext,
    this.characterKey,
  });

  @override
  Widget build(BuildContext context) {
    final controller = character.controller;
    if (controller == null) return _paint(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _paint(context),
    );
  }

  Widget _paint(BuildContext context) {
    final position = character.effectivePathPosition;
    if (!renderContext.ownsPathPosition(position)) {
      return const SizedBox.shrink();
    }
    final pose = renderContext.poseAtPathPosition(position);
    if (pose == null) return const SizedBox.shrink();

    final layout = renderContext.layout;
    final scale = character.scaleWithZoom ? layout.zoom : 1.0;
    final size = Size(
      character.size.width * scale,
      character.size.height * scale,
    );
    final topLeft = character.topLeftFor(pose.position, size);

    final state = SagaCharacterState(
      pathPosition: position,
      nearestLevelId: position.round(),
      motion: character.effectiveMotion,
      facing: character.effectiveFacing,
      direction: pose.direction,
      headingRadians: pose.headingRadians,
      layout: layout,
    );

    Widget child = SizedBox(
      key: characterKey,
      width: size.width,
      height: size.height,
      child: character.builder(context, state),
    );

    final label = character.semanticsLabel;
    if (label != null) {
      // Announced, but deliberately not focusable: the character is not a
      // control, and putting it in the tab order would sit it between level
      // buttons for no gain.
      child = Semantics(label: label, excludeSemantics: true, child: child);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          // The hop arc lifts the art off the path and sets it back down on
          // each node, so the landing still lands.
          left: topLeft.dx,
          top: topLeft.dy + character.hopOffset * scale,
          // Art large enough to overlap its node would otherwise swallow the
          // tap that opens that level.
          child: IgnorePointer(child: child),
        ),
      ],
    );
  }
}
