import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/level_progress.dart';

/// Visual/interaction state used by node callbacks.
enum SagaNodeInteractionState {
  idle,
  hovered,

  /// Node holds keyboard focus. Emitted only when focus arrived by keyboard,
  /// so a node builder can draw a focus ring without it appearing on click.
  focused,
  pressed,
  selected,
  completed,
  locked,
}

/// Tap callback signature for level nodes.
typedef SagaNodeTapCallback = void Function(LevelData level);

/// Long-press callback signature for level nodes.
typedef SagaNodeLongPressCallback = void Function(LevelData level);

/// Hover callback signature for level nodes.
typedef SagaNodeHoverCallback = void Function(LevelData level, bool isHovered);

/// Focus-state callback signature for level nodes.
typedef SagaNodeFocusChangeCallback = void Function(
  LevelData level,
  SagaNodeInteractionState state,
);

/// Callback container used by map widgets for node interactions.
class SagaNodeInteractionHandler {
  final SagaNodeTapCallback? onNodeTap;
  final SagaNodeLongPressCallback? onNodeLongPress;
  final SagaNodeHoverCallback? onNodeHover;
  final SagaNodeFocusChangeCallback? onNodeFocusChange;

  const SagaNodeInteractionHandler({
    this.onNodeTap,
    this.onNodeLongPress,
    this.onNodeHover,
    this.onNodeFocusChange,
  });

  /// Resolves end-state presentation from [LevelProgress].
  SagaNodeInteractionState resolveTerminalState(LevelProgress? progress) {
    if (progress == null) return SagaNodeInteractionState.selected;
    switch (progress.state) {
      case LevelCompletionState.locked:
        return SagaNodeInteractionState.locked;
      case LevelCompletionState.completed:
        return SagaNodeInteractionState.completed;
      case LevelCompletionState.unlocked:
        return SagaNodeInteractionState.selected;
    }
  }
}
