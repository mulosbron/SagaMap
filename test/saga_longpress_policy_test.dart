import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

class _MockCustomPolicy extends SagaNodeInteractionPolicy {
  const _MockCustomPolicy();
  @override
  bool canTap(LevelData level, LevelProgress? progress) => false;
  @override
  bool canLongPress(LevelData level, LevelProgress? progress) => true;
}

void main() {
  group('SagaNodeInteractionPolicy long press', () {
    test('default emits tap logic (emitTapForLockedNode: false)', () {
      const policy = SagaNodeInteractionPolicy(emitTapForLockedNode: false);
      final level =
          const LevelData(id: 0, position: SagaPoint(0, 0), biomeId: 'test');
      final progress =
          const LevelProgress(levelId: 0, state: LevelCompletionState.locked);
      expect(policy.canLongPress(level, progress), isFalse);
    });

    test('default emits tap logic (emitTapForLockedNode: true)', () {
      const policy = SagaNodeInteractionPolicy(emitTapForLockedNode: true);
      final level =
          const LevelData(id: 0, position: SagaPoint(0, 0), biomeId: 'test');
      final progress =
          const LevelProgress(levelId: 0, state: LevelCompletionState.locked);
      expect(policy.canLongPress(level, progress), isTrue);
    });

    test('completed node blocked when emitTapForCompletedNode is false', () {
      const policy = SagaNodeInteractionPolicy(emitTapForCompletedNode: false);
      final level =
          const LevelData(id: 0, position: SagaPoint(0, 0), biomeId: 'test');
      final progress = const LevelProgress(
          levelId: 0, state: LevelCompletionState.completed, stars: 1);
      expect(policy.canLongPress(level, progress), isFalse);
    });

    test('unlocked is true', () {
      const policy = SagaNodeInteractionPolicy();
      final level =
          const LevelData(id: 0, position: SagaPoint(0, 0), biomeId: 'test');
      final progress =
          const LevelProgress(levelId: 0, state: LevelCompletionState.unlocked);
      expect(policy.canLongPress(level, progress), isTrue);
    });
  });

  group('Saga long press gesture', () {
    Widget buildAdapter({
      required SagaNodeInteractionPolicy policy,
      required SagaNodeInteractionHandler handler,
      LevelCompletionState state = LevelCompletionState.locked,
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
            maxLateralExtent: 100),
        levels: [
          const LevelData(id: 0, position: SagaPoint(0, 0), biomeId: 'test')
        ],
        progressResolver: (l) =>
            LevelProgress(levelId: 0, state: state, stars: 1),
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
              return Stack(
                children: adapter.render(renderContext),
              );
            },
          ),
        ),
      );
    }

    testWidgets(
        'emitTapForLockedNode: false + locked node -> no long press callback',
        (tester) async {
      int longPressCount = 0;
      int focusChangeCount = 0;
      SagaNodeInteractionState? lastFocusState;

      await tester.pumpWidget(buildAdapter(
        policy: const SagaNodeInteractionPolicy(emitTapForLockedNode: false),
        handler: SagaNodeInteractionHandler(
          onNodeLongPress: (level) => longPressCount++,
          onNodeFocusChange: (level, state) {
            focusChangeCount++;
            lastFocusState = state;
          },
        ),
        state: LevelCompletionState.locked,
      ));

      await tester.longPress(find.byType(GestureDetector));
      expect(longPressCount, 0);
      expect(focusChangeCount, greaterThan(0));
      expect(lastFocusState, SagaNodeInteractionState.locked);
    });

    testWidgets('emitTapForLockedNode: true + locked node -> callback fires',
        (tester) async {
      int longPressCount = 0;

      await tester.pumpWidget(buildAdapter(
        policy: const SagaNodeInteractionPolicy(emitTapForLockedNode: true),
        handler: SagaNodeInteractionHandler(
          onNodeLongPress: (level) => longPressCount++,
        ),
        state: LevelCompletionState.locked,
      ));

      await tester.longPress(find.byType(GestureDetector));
      expect(longPressCount, 1);
    });

    testWidgets('unlocked node -> callback fires', (tester) async {
      int longPressCount = 0;

      await tester.pumpWidget(buildAdapter(
        policy: const SagaNodeInteractionPolicy(),
        handler: SagaNodeInteractionHandler(
          onNodeLongPress: (level) => longPressCount++,
        ),
        state: LevelCompletionState.unlocked,
      ));

      await tester.longPress(find.byType(GestureDetector));
      expect(longPressCount, 1);
    });

    testWidgets(
        'emitTapForCompletedNode: false + completed node -> no callback',
        (tester) async {
      int longPressCount = 0;

      await tester.pumpWidget(buildAdapter(
        policy: const SagaNodeInteractionPolicy(emitTapForCompletedNode: false),
        handler: SagaNodeInteractionHandler(
          onNodeLongPress: (level) => longPressCount++,
        ),
        state: LevelCompletionState.completed,
      ));

      await tester.longPress(find.byType(GestureDetector));
      expect(longPressCount, 0);
    });

    testWidgets('custom policy can allow long press even if tap is false',
        (tester) async {
      int longPressCount = 0;

      await tester.pumpWidget(buildAdapter(
        policy: const _MockCustomPolicy(),
        handler: SagaNodeInteractionHandler(
          onNodeLongPress: (level) => longPressCount++,
        ),
        state: LevelCompletionState.locked,
      ));

      await tester.longPress(find.byType(GestureDetector));
      expect(longPressCount, 1);
    });
  });
}
