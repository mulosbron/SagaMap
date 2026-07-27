import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/level_progress.dart';

/// Interaction gating policy for map node gestures.
class SagaNodeInteractionPolicy {
  final bool enableHover;
  final bool emitTapForLockedNode;
  final bool emitTapForCompletedNode;

  const SagaNodeInteractionPolicy({
    this.enableHover = true,
    this.emitTapForLockedNode = false,
    this.emitTapForCompletedNode = true,
  });

  /// Returns true when node tap should be accepted.
  bool canTap(LevelData level, LevelProgress? progress) {
    if (progress == null) return true;
    switch (progress.state) {
      case LevelCompletionState.locked:
        return emitTapForLockedNode;
      case LevelCompletionState.completed:
        return emitTapForCompletedNode;
      case LevelCompletionState.unlocked:
        return true;
    }
  }
}
