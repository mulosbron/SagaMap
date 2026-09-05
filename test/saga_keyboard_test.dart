import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Desktop keyboard support: nodes must be reachable by Tab and activatable
/// without a pointer. They previously had no focus handling at all.

const _levels = <LevelData>[
  LevelData(id: 1, position: SagaPoint(0.3, 0.0), biomeId: kBiomeIdForest),
  LevelData(id: 2, position: SagaPoint(0.7, 0.3), biomeId: kBiomeIdForest),
  LevelData(id: 3, position: SagaPoint(0.3, 0.6), biomeId: kBiomeIdForest),
];

const _progress = <int, LevelProgress>{
  1: LevelProgress(levelId: 1, state: LevelCompletionState.completed),
  2: LevelProgress(levelId: 2, state: LevelCompletionState.unlocked),
  3: LevelProgress(levelId: 3, state: LevelCompletionState.locked),
};

class _MockNoLongPressPolicy extends SagaNodeInteractionPolicy {
  const _MockNoLongPressPolicy();
  @override
  bool canTap(LevelData level, LevelProgress? progress) => true;
  @override
  bool canLongPress(LevelData level, LevelProgress? progress) => false;
}

void main() {
  Future<void> pumpMap(
    WidgetTester tester, {
    required List<int> tapped,
    List<(int, SagaNodeInteractionState)>? focusLog,
    bool withProgress = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            chunkContext: SagaChunkContext(
                chunkIndex: 0, levels: const [], progress: const {}),
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 700,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            progressResolver:
                withProgress ? (level) => _progress[level.id] : null,
            onLevelTap: (level) => tapped.add(level.id),
            interactionHandler: SagaNodeInteractionHandler(
              onNodeFocusChange: (level, state) =>
                  focusLog?.add((level.id, state)),
            ),
            nodeBuilder: (context, level, layout) => const DecoratedBox(
              decoration: BoxDecoration(color: Colors.indigo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressTab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }

  testWidgets('Tab reaches a node and Enter activates it', (tester) async {
    final tapped = <int>[];
    await pumpMap(tester, tapped: tapped);

    await pressTab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tapped, isNotEmpty);
  });

  testWidgets('Space also activates a focused node', (tester) async {
    final tapped = <int>[];
    await pumpMap(tester, tapped: tapped);

    await pressTab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(tapped, isNotEmpty);
  });

  testWidgets('Tab visits nodes in level order', (tester) async {
    final tapped = <int>[];
    // Without progress every node is tappable, so all three take part.
    await pumpMap(tester, tapped: tapped, withProgress: false);

    final visited = <int>[];
    for (var i = 0; i < 3; i++) {
      await pressTab(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      visited.add(tapped.last);
    }

    // Paint order would be arbitrary; NumericFocusOrder pins it to level order.
    expect(visited, [1, 2, 3]);
  });

  testWidgets('a locked node is skipped by Tab', (tester) async {
    final tapped = <int>[];
    await pumpMap(tester, tapped: tapped);

    // Level 3 is locked and the policy rejects taps on it, so focus must pass
    // it by rather than stranding a keyboard user on a dead node.
    for (var i = 0; i < 6; i++) {
      await pressTab(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    expect(tapped, isNotEmpty);
    expect(tapped, isNot(contains(3)));
  });

  testWidgets('keyboard focus reports the focused state', (tester) async {
    final tapped = <int>[];
    final focusLog = <(int, SagaNodeInteractionState)>[];
    await pumpMap(tester, tapped: tapped, focusLog: focusLog);

    await pressTab(tester);

    // A node builder needs this to draw a focus ring.
    expect(
      focusLog.any((entry) => entry.$2 == SagaNodeInteractionState.focused),
      isTrue,
      reason: 'focus log: $focusLog',
    );
  });

  testWidgets('Shift+F10 triggers long press callback', (tester) async {
    final tapped = <int>[];
    final longPressed = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            chunkContext: SagaChunkContext(
                chunkIndex: 0, levels: _levels, progress: const {}),
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 700,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            progressResolver: (level) => _progress[level.id],
            onLevelTap: (level) => tapped.add(level.id),
            interactionHandler: SagaNodeInteractionHandler(
              onNodeLongPress: (level) => longPressed.add(level.id),
            ),
            nodeBuilder: (context, level, layout) => const DecoratedBox(
              decoration: BoxDecoration(color: Colors.indigo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await pressTab(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();

    expect(longPressed, isNotEmpty);
    expect(tapped, isEmpty);
  });

  testWidgets('Context menu key triggers long press callback', (tester) async {
    final tapped = <int>[];
    final longPressed = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            chunkContext: SagaChunkContext(
                chunkIndex: 0, levels: _levels, progress: const {}),
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 700,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            progressResolver: (level) => _progress[level.id],
            onLevelTap: (level) => tapped.add(level.id),
            interactionHandler: SagaNodeInteractionHandler(
              onNodeLongPress: (level) => longPressed.add(level.id),
            ),
            nodeBuilder: (context, level, layout) => const DecoratedBox(
              decoration: BoxDecoration(color: Colors.indigo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await pressTab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    expect(longPressed, isNotEmpty);
    expect(tapped, isEmpty);
  });

  testWidgets('Shift+F10 does nothing if canLongPress is false',
      (tester) async {
    final tapped = <int>[];
    final longPressed = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            chunkContext: SagaChunkContext(
                chunkIndex: 0, levels: _levels, progress: const {}),
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 700,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            progressResolver: (level) => _progress[level.id],
            onLevelTap: (level) => tapped.add(level.id),
            interactionPolicy: const _MockNoLongPressPolicy(),
            interactionHandler: SagaNodeInteractionHandler(
              onNodeLongPress: (level) => longPressed.add(level.id),
            ),
            nodeBuilder: (context, level, layout) => const DecoratedBox(
              decoration: BoxDecoration(color: Colors.indigo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await pressTab(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();

    expect(longPressed, isEmpty);
  });
}
