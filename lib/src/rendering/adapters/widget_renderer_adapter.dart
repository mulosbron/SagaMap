import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/level_progress.dart';
import '../../core/domain/models/resolved_saga_layout.dart';
import '../contracts/saga_map_render_context.dart';
import '../contracts/saga_map_renderer.dart';
import '../interaction/saga_node_interaction_handler.dart';
import '../interaction/saga_node_interaction_policy.dart';

/// Builds the visual for one level node.
typedef SagaNodeBuilder = Widget Function(
  BuildContext context,
  LevelData level,
  ResolvedSagaLayout layout,
);

/// Builds the screen-reader label for one level node.
///
/// Supply your own to localise; the built-in default is English.
/// The `level.id` you receive is zero-based.
typedef SagaNodeSemanticsLabelBuilder = String Function(
  LevelData level,
  LevelProgress? progress,
);

/// Default logical size of a node before responsive scaling.
const double kSagaDefaultNodeSize = 44.0;

/// Smallest touch target a node is allowed to expose, per platform
/// accessibility guidance.
const double kSagaMinTouchTarget = 44.0;

/// Default English screen-reader label: level number plus its state.
/// Shows `id + 1`.
String defaultSagaNodeSemanticsLabel(LevelData level, LevelProgress? progress) {
  // Ids are zero-based; players count from one. The announced number must match the number drawn on the node.
  final buffer = StringBuffer('Level ${level.id + 1}');
  switch (progress?.state) {
    case LevelCompletionState.locked:
      buffer.write(', locked');
    case LevelCompletionState.completed:
      buffer.write(', completed');
      if (progress!.stars > 0) {
        buffer.write(', ${progress.stars} '
            '${progress.stars == 1 ? 'star' : 'stars'}');
      }
    case LevelCompletionState.unlocked:
      buffer.write(', unlocked');
    case null:
      break;
  }
  return buffer.toString();
}

/// Renders a chunk's levels as positioned, interactive widgets.
///
/// Emits [Positioned] children in the chunk's own coordinate space; the caller
/// is responsible for placing that space within the viewport.
class WidgetRendererAdapter implements SagaMapRenderer<List<Widget>> {
  final BuildContext context;
  final SagaNodeBuilder nodeBuilder;
  final SagaNodeInteractionHandler interactionHandler;
  final SagaNodeInteractionPolicy interactionPolicy;

  /// Logical node size before [ResolvedSagaLayout.nodeSize] and zoom scaling.
  final double baseNodeSize;

  /// Floor on the gesture area, independent of visual size.
  final double minTouchTarget;

  /// Screen-reader label for each node.
  final SagaNodeSemanticsLabelBuilder semanticsLabelBuilder;

  const WidgetRendererAdapter({
    required this.context,
    required this.nodeBuilder,
    required this.interactionHandler,
    required this.interactionPolicy,
    this.baseNodeSize = kSagaDefaultNodeSize,
    this.minTouchTarget = kSagaMinTouchTarget,
    this.semanticsLabelBuilder = defaultSagaNodeSemanticsLabel,
  });

  @override
  List<Widget> render(SagaMapRenderContext contextData) {
    final layout = contextData.layout;

    // Visual size and hit area are computed separately on purpose. Clamping the
    // visual size up to the touch minimum would silently discard every
    // shrinking node policy — desktop and 4K both scale below 1.
    final visualSize = baseNodeSize * layout.nodeSize * layout.zoom;
    final touchSize =
        math.max(visualSize * layout.interactionRadius, minTouchTarget);

    return contextData.levels.map((level) {
      final pixel = contextData.pixelFor(level);
      final progress = contextData.resolveProgress(level);

      void emitTap() {
        if (interactionPolicy.canTap(level, progress)) {
          interactionHandler.onNodeTap?.call(level);
          interactionHandler.onNodeFocusChange?.call(
            level,
            interactionHandler.resolveTerminalState(progress),
          );
        } else {
          interactionHandler.onNodeFocusChange?.call(
            level,
            SagaNodeInteractionState.locked,
          );
        }
      }

      final canTap = interactionPolicy.canTap(level, progress);

      return Positioned(
        left: pixel.x - touchSize / 2,
        top: pixel.y - touchSize / 2,
        // Tab order follows level order rather than screen position, which is
        // what a progression map means by "next". Stack children would
        // otherwise be traversed in paint order, and in a right-to-left or
        // horizontal map that is not the order the player advances in.
        child: FocusTraversalOrder(
          order: NumericFocusOrder(level.id.toDouble()),
          child: Semantics(
            button: true,
            enabled: canTap,
            focusable: canTap,
            label: semanticsLabelBuilder(level, progress),
            onTap: canTap ? emitTap : null,
            // The node visual is decorative; the label already describes it.
            excludeSemantics: true,
            child: FocusableActionDetector(
              // Locked nodes are skipped by Tab, matching the tap policy.
              enabled: canTap,
              mouseCursor:
                  canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => emitTap(),
                ),
                ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
                  onInvoke: (_) => emitTap(),
                ),
              },
              onShowFocusHighlight: (isFocused) {
                interactionHandler.onNodeFocusChange?.call(
                  level,
                  isFocused
                      ? SagaNodeInteractionState.focused
                      : SagaNodeInteractionState.idle,
                );
              },
              child: MouseRegion(
                onEnter: (_) {
                  if (interactionPolicy.enableHover) {
                    interactionHandler.onNodeHover?.call(level, true);
                    interactionHandler.onNodeFocusChange?.call(
                      level,
                      SagaNodeInteractionState.hovered,
                    );
                  }
                },
                onExit: (_) {
                  if (interactionPolicy.enableHover) {
                    interactionHandler.onNodeHover?.call(level, false);
                    interactionHandler.onNodeFocusChange?.call(
                      level,
                      SagaNodeInteractionState.idle,
                    );
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => interactionHandler.onNodeFocusChange?.call(
                    level,
                    SagaNodeInteractionState.pressed,
                  ),
                  onTap: emitTap,
                  onLongPress: interactionHandler.onNodeLongPress == null
                      ? null
                      : () => interactionHandler.onNodeLongPress?.call(level),
                  // Gesture area is touchSize; the visual sits centred in it.
                  child: SizedBox(
                    width: touchSize,
                    height: touchSize,
                    child: Center(
                      child: SizedBox(
                        width: visualSize,
                        height: visualSize,
                        child: nodeBuilder(context, level, layout),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList(growable: false);
  }
}
