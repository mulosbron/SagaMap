import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// One gate condition, three consumers: the node stops responding, the walk
/// stops short, and the successor stops unlocking. These tests cover the first
/// and the third; `saga_character_walk_test.dart` covers the walk.

const _level = LevelData(id: 7, position: SagaPoint(0, 0), biomeId: 'test');

/// A subclass that ignores [canTap] entirely, to show that a policy overriding
/// long-press still has to honour reachability itself.
class _AlwaysLongPressPolicy extends SagaNodeInteractionPolicy {
  const _AlwaysLongPressPolicy({super.isReachable});

  @override
  bool canLongPress(LevelData level, LevelProgress? progress) => true;
}

Widget _buildAdapter({
  required SagaNodeInteractionPolicy policy,
  required SagaNodeInteractionHandler handler,
  LevelCompletionState state = LevelCompletionState.unlocked,
}) {
  final renderContext = SagaMapRenderContext(
    layout: const ResolvedSagaLayout(
      breakpoint: SagaMapBreakpointName.desktop,
      pathAxis: SagaMapPathAxis.vertical,
      nodeSize: 1,
      nodeSpacing: 1,
      zoom: 1,
      interactionRadius: 1.0,
      cameraPadding: 0,
      scrollSensitivity: 1,
      maxLateralExtent: 100,
    ),
    levels: const [_level],
    progressResolver: (l) =>
        LevelProgress(levelId: l.id, state: state, stars: 0),
    chunkSpanNormalized: 1.0,
    chunkIndex: 0,
    chunkSize: const SagaSize(width: 100, height: 100),
  );

  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final adapter = WidgetRendererAdapter(
            context: context,
            nodeBuilder: (context, level, layout) =>
                const SizedBox(width: 44, height: 44),
            interactionHandler: handler,
            interactionPolicy: policy,
          );
          return Stack(children: adapter.render(renderContext));
        },
      ),
    ),
  );
}

void main() {
  group('SagaNodeInteractionPolicy.isReachable', () {
    const unlocked =
        LevelProgress(levelId: 7, state: LevelCompletionState.unlocked);

    test('a veto closes an otherwise tappable node', () {
      const policy = SagaNodeInteractionPolicy(isReachable: _never);
      expect(policy.canTap(_level, unlocked), isFalse);
    });

    test('the veto outranks every emitTapFor setting', () {
      // A node behind a closed gate is shut even when the host has opted into
      // tapping locked and completed nodes.
      const policy = SagaNodeInteractionPolicy(
        emitTapForLockedNode: true,
        emitTapForCompletedNode: true,
        isReachable: _never,
      );
      expect(
        policy.canTap(
          _level,
          const LevelProgress(levelId: 7, state: LevelCompletionState.locked),
        ),
        isFalse,
      );
      expect(
        policy.canTap(
          _level,
          const LevelProgress(
              levelId: 7, state: LevelCompletionState.completed),
        ),
        isFalse,
      );
      // And with no record at all, which is the "always true" branch in 1.x.
      expect(policy.canTap(_level, null), isFalse);
    });

    test('long press goes through the same veto', () {
      const policy = SagaNodeInteractionPolicy(isReachable: _never);
      expect(policy.canLongPress(_level, unlocked), isFalse);
    });

    test('a null isReachable is 1.x behaviour', () {
      const legacy = SagaNodeInteractionPolicy();
      const explicit = SagaNodeInteractionPolicy(isReachable: _always);

      for (final state in LevelCompletionState.values) {
        final progress = LevelProgress(levelId: 7, state: state);
        expect(
          legacy.canTap(_level, progress),
          explicit.canTap(_level, progress),
          reason: '$state',
        );
        expect(
          legacy.canLongPress(_level, progress),
          explicit.canLongPress(_level, progress),
          reason: '$state',
        );
      }
      expect(legacy.canTap(_level, null), isTrue);
    });

    test('the veto sees the level and its progress', () {
      LevelData? seenLevel;
      LevelProgress? seenProgress;
      final policy = SagaNodeInteractionPolicy(
        isReachable: (level, progress) {
          seenLevel = level;
          seenProgress = progress;
          return true;
        },
      );

      policy.canTap(_level, unlocked);
      expect(seenLevel, same(_level));
      expect(seenProgress, same(unlocked));
    });

    testWidgets('a vetoed node is disabled and advertises no tap',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildAdapter(
        policy: const SagaNodeInteractionPolicy(isReachable: _never),
        handler: const SagaNodeInteractionHandler(),
      ));

      expect(
        tester.getSemantics(find.bySemanticsLabel('Level 8, unlocked')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          isFocusable: false,
          // The node still reads as unlocked — the gate is why it cannot be
          // opened, not the progress state — but it offers no tap action.
          hasTapAction: false,
        ),
      );

      handle.dispose();
    });

    testWidgets('a vetoed node is skipped by Tab', (tester) async {
      await tester.pumpWidget(_buildAdapter(
        policy: const SagaNodeInteractionPolicy(isReachable: _never),
        handler: const SagaNodeInteractionHandler(),
      ));

      final detector = tester.widget<FocusableActionDetector>(
        find.byType(FocusableActionDetector),
      );
      expect(detector.enabled, isFalse);
    });

    testWidgets('tapping a vetoed node announces it as locked', (tester) async {
      var taps = 0;
      SagaNodeInteractionState? lastState;

      await tester.pumpWidget(_buildAdapter(
        policy: const SagaNodeInteractionPolicy(isReachable: _never),
        handler: SagaNodeInteractionHandler(
          onNodeTap: (_) => taps++,
          onNodeFocusChange: (_, state) => lastState = state,
        ),
      ));

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(taps, 0);
      expect(lastState, SagaNodeInteractionState.locked);
    });

    testWidgets('long-pressing a vetoed node is cut off too', (tester) async {
      var longPresses = 0;
      SagaNodeInteractionState? lastState;

      await tester.pumpWidget(_buildAdapter(
        policy: const SagaNodeInteractionPolicy(isReachable: _never),
        handler: SagaNodeInteractionHandler(
          onNodeLongPress: (_) => longPresses++,
          onNodeFocusChange: (_, state) => lastState = state,
        ),
      ));

      await tester.longPress(find.byType(GestureDetector));
      await tester.pump();

      expect(longPresses, 0);
      expect(lastState, SagaNodeInteractionState.locked);
    });

    testWidgets('an unvetoed node still taps normally', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_buildAdapter(
        policy: const SagaNodeInteractionPolicy(isReachable: _always),
        handler: SagaNodeInteractionHandler(onNodeTap: (_) => taps++),
      ));

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      expect(taps, 1);
    });

    test('a subclass overriding canLongPress bypasses the veto', () {
      // Documented consequence, pinned so it is a decision and not a surprise:
      // an override that does not call canTap does not inherit the gate.
      const policy = _AlwaysLongPressPolicy(isReachable: _never);
      expect(policy.canTap(_level, unlocked), isFalse);
      expect(policy.canLongPress(_level, unlocked), isTrue);
    });
  });

  group('CompleteLevelUseCase.canUnlock', () {
    final start = SagaProgress.initial();

    test('a veto completes the level but leaves the successor shut', () {
      const useCase = CompleteLevelUseCase(canUnlock: _neverUnlock);

      final result =
          useCase.execute(currentProgress: start, levelId: 0, globalSeed: 7);

      expect(
          result.nextProgress.levels[0]?.state, LevelCompletionState.completed);
      expect(result.nextProgress.levels.containsKey(1), isFalse);
    });

    test('a veto does not demote a successor that was already open', () {
      // A gate closing behind a player who already passed it would erase real
      // progress, so a veto only ever declines to open.
      const useCase = CompleteLevelUseCase(canUnlock: _neverUnlock);
      const passed = SagaProgress(
        currentMaxUnlockedLevelId: 3,
        levels: {
          0: LevelProgress(levelId: 0, state: LevelCompletionState.completed),
          1: LevelProgress(levelId: 1, state: LevelCompletionState.unlocked),
        },
      );

      final result =
          useCase.execute(currentProgress: passed, levelId: 0, globalSeed: 7);

      expect(
          result.nextProgress.levels[1]?.state, LevelCompletionState.unlocked);
    });

    test('a veto freezes currentMaxUnlockedLevelId', () {
      const useCase = CompleteLevelUseCase(canUnlock: _neverUnlock);

      final result =
          useCase.execute(currentProgress: start, levelId: 0, globalSeed: 7);

      expect(result.nextProgress.currentMaxUnlockedLevelId,
          start.currentMaxUnlockedLevelId);
    });

    test('a veto reports itself through unlockBlocked', () {
      const blocked = CompleteLevelUseCase(canUnlock: _neverUnlock);
      const open = CompleteLevelUseCase(canUnlock: _alwaysUnlock);

      expect(
        blocked
            .execute(currentProgress: start, levelId: 0, globalSeed: 7)
            .unlockBlocked,
        isTrue,
      );
      expect(
        open
            .execute(currentProgress: start, levelId: 0, globalSeed: 7)
            .unlockBlocked,
        isFalse,
      );
    });

    test('a boss reward still drops behind a closed gate', () {
      // The player did clear the level; withholding the reward would punish
      // them for the gate.
      const useCase = CompleteLevelUseCase(canUnlock: _neverUnlock);

      final result =
          useCase.execute(currentProgress: start, levelId: 14, globalSeed: 7);

      expect(result.reward, isNotNull);
      expect(result.unlockBlocked, isTrue);
    });

    test('the veto is asked about the level it would open', () {
      final asked = <int>[];
      final useCase = CompleteLevelUseCase(
        canUnlock: (levelId) {
          asked.add(levelId);
          return true;
        },
      );

      useCase.execute(currentProgress: start, levelId: 4, globalSeed: 7);
      expect(asked, [5]);
    });

    test('opening the gate and replaying unlocks the successor', () {
      var open = false;
      final useCase = CompleteLevelUseCase(canUnlock: (_) => open);

      final blocked =
          useCase.execute(currentProgress: start, levelId: 0, globalSeed: 7);
      expect(blocked.nextProgress.levels.containsKey(1), isFalse);

      open = true;
      final through = useCase.execute(
        currentProgress: blocked.nextProgress,
        levelId: 0,
        globalSeed: 7,
      );

      expect(
          through.nextProgress.levels[1]?.state, LevelCompletionState.unlocked);
      expect(through.nextProgress.currentMaxUnlockedLevelId, 1);
      expect(through.unlockBlocked, isFalse);
    });

    test('a null canUnlock is 1.x behaviour', () {
      const legacy = CompleteLevelUseCase();
      const explicit = CompleteLevelUseCase(canUnlock: _alwaysUnlock);

      for (var levelId = 0; levelId < 20; levelId++) {
        final a = legacy.execute(
          currentProgress: start,
          levelId: levelId,
          globalSeed: 7,
          now: DateTime.utc(2026),
        );
        final b = explicit.execute(
          currentProgress: start,
          levelId: levelId,
          globalSeed: 7,
          now: DateTime.utc(2026),
        );
        expect(a.nextProgress.toJson(), b.nextProgress.toJson(),
            reason: 'level $levelId');
        expect(a.unlockBlocked, isFalse);
        expect(b.unlockBlocked, isFalse);
        expect(a.outcome, CompleteLevelOutcome.applied);
        expect(b.outcome, CompleteLevelOutcome.applied);
      }
    });

    test('canUnlock and enforceUnlockOrder guard opposite directions', () {
      // enforceUnlockOrder looks backwards: it rejects the completion itself.
      // canUnlock looks forwards: the completion stands, the successor waits.
      const gated = CompleteLevelUseCase(canUnlock: _neverUnlock);

      final skipped = gated.execute(
        currentProgress: start,
        levelId: 50,
        globalSeed: 7,
        enforceUnlockOrder: true,
      );
      expect(skipped.nextProgress.levels.containsKey(50), isFalse);
      expect(skipped.unlockBlocked, isFalse);
      expect(skipped.outcome, CompleteLevelOutcome.rejectedUnreached);

      final reachable = gated.execute(
        currentProgress: start,
        levelId: 0,
        globalSeed: 7,
        enforceUnlockOrder: true,
      );
      expect(reachable.nextProgress.levels[0]?.state,
          LevelCompletionState.completed);
      expect(reachable.unlockBlocked, isTrue);
      expect(reachable.outcome, CompleteLevelOutcome.appliedUnlockBlocked);
    });
  });
}

bool _never(LevelData level, LevelProgress? progress) => false;

bool _always(LevelData level, LevelProgress? progress) => true;

bool _neverUnlock(int levelId) => false;

bool _alwaysUnlock(int levelId) => true;
