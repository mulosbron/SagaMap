import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/level_progress.dart';

/// Decides whether a node can be reached at all, independently of the progress
/// recorded for it.
///
/// A closed gate, an unbought ticket, a friend-gated chapter: conditions the
/// package cannot know, so it asks.
typedef SagaNodeReachability = bool Function(
  LevelData level,
  LevelProgress? progress,
);

/// Interaction gating policy for map node gestures.
class SagaNodeInteractionPolicy {
  final bool enableHover;
  final bool emitTapForLockedNode;
  final bool emitTapForCompletedNode;

  /// Host veto on reaching a node at all — a closed gate, a ticket, a purchase.
  ///
  /// Consulted before anything else: returning `false` makes the node
  /// unreachable regardless of its recorded progress state, and no
  /// [emitTapForLockedNode] or [emitTapForCompletedNode] setting overrides it.
  ///
  /// A vetoed node is rendered as `Semantics.enabled: false`, skipped in the
  /// Tab order, cursored as non-interactive, and announces
  /// [SagaNodeInteractionState.locked] when tapped — the same treatment a
  /// locked node gets, because to the player it is the same situation.
  ///
  /// `null`, the default, is 1.x behaviour: reachability is decided entirely
  /// by [LevelProgress.state].
  ///
  /// Pair it with `CompleteLevelUseCase.canUnlock` so the two cannot disagree.
  /// One gate condition, two consumers — the node stops responding and the
  /// successor stops unlocking:
  ///
  /// ```dart
  /// bool gateOpen(int levelId) => levelId <= 14 || boughtChapterTwo;
  ///
  /// final policy = SagaNodeInteractionPolicy(
  ///   isReachable: (level, progress) => gateOpen(level.id),
  /// );
  /// final useCase = CompleteLevelUseCase(canUnlock: gateOpen);
  /// ```
  ///
  /// Deriving both from one predicate is the point: a node that can be tapped
  /// but whose successor never unlocks reads as a broken map.
  final SagaNodeReachability? isReachable;

  const SagaNodeInteractionPolicy({
    this.enableHover = true,
    this.emitTapForLockedNode = false,
    this.emitTapForCompletedNode = true,
    this.isReachable,
  });

  /// Returns true when node tap should be accepted.
  ///
  /// A node with **no progress record is treated as locked**: an unrecorded
  /// level must not become tappable just because the host never wrote a record
  /// for it — that would be an arbitrary progression skip with no tampering at
  /// all. Treating "no record" and "locked" as the same thing also keeps the
  /// tap gate, the a11y tree and the Tab order in agreement: all three see the
  /// same node as closed.
  bool canTap(LevelData level, LevelProgress? progress) {
    // Reachability first: a gate closes a node whatever its progress says.
    if (isReachable != null && !isReachable!(level, progress)) return false;
    final state = progress?.state ?? LevelCompletionState.locked;
    switch (state) {
      case LevelCompletionState.locked:
        return emitTapForLockedNode;
      case LevelCompletionState.completed:
        return emitTapForCompletedNode;
      case LevelCompletionState.unlocked:
        return true;
    }
  }

  /// Defaults to [canTap]: a node you cannot open is a node you cannot open a context menu on either.
  ///
  /// Can be overridden to allow long-pressing locked nodes, for example to show a "how to unlock?" hint.
  /// An override still has to honour [isReachable] itself — a subclass that
  /// bypasses [canTap] bypasses the gate with it.
  bool canLongPress(LevelData level, LevelProgress? progress) =>
      canTap(level, progress);
}
