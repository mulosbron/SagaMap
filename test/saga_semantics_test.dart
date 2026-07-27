import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

const _levels = <LevelData>[
  LevelData(id: 1, position: SagaPoint(0.3, 0.0), biomeId: kBiomeIdForest),
  LevelData(id: 2, position: SagaPoint(0.7, 0.4), biomeId: kBiomeIdForest),
  LevelData(id: 3, position: SagaPoint(0.3, 0.8), biomeId: kBiomeIdForest),
];

const _progress = <int, LevelProgress>{
  1: LevelProgress(
      levelId: 1, state: LevelCompletionState.completed, stars: 3),
  2: LevelProgress(levelId: 2, state: LevelCompletionState.unlocked),
  3: LevelProgress(levelId: 3, state: LevelCompletionState.locked),
};

void main() {
  Future<void> pumpMap(
    WidgetTester tester, {
    SagaNodeSemanticsLabelBuilder? labelBuilder,
    ValueChanged<LevelData>? onLevelTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 600,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            progressResolver: (level) => _progress[level.id],
            onLevelTap: onLevelTap,
            semanticsLabelBuilder:
                labelBuilder ?? defaultSagaNodeSemanticsLabel,
            nodeBuilder: (context, level, layout) => const DecoratedBox(
              decoration: BoxDecoration(color: Colors.indigo),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('every node is announced to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMap(tester);

    // Nodes previously had no semantics at all: a screen-reader user could not
    // discover the map's levels.
    expect(find.bySemanticsLabel('Level 1, completed, 3 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 2, unlocked'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 3, locked'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('a locked node is announced as disabled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMap(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Level 3, locked')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        // The interaction policy rejects taps on locked nodes, so the node must
        // not advertise a tap action either.
        hasTapAction: false,
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Level 2, unlocked')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('a semantic tap reaches the tap handler', (tester) async {
    final handle = tester.ensureSemantics();
    final tapped = <int>[];
    await pumpMap(tester, onLevelTap: (level) => tapped.add(level.id));

    tester.semantics.performAction(
      find.semantics.byLabel('Level 2, unlocked'),
      SemanticsAction.tap,
    );
    await tester.pump();

    expect(tapped, [2]);
    handle.dispose();
  });

  testWidgets('the label builder can be replaced for localisation',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMap(
      tester,
      labelBuilder: (level, progress) => 'Bölüm ${level.id}',
    );

    expect(find.bySemanticsLabel('Bölüm 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 1, completed, 3 stars'), findsNothing);

    handle.dispose();
  });

  test('the default label singularises one star', () {
    const level =
        LevelData(id: 9, position: SagaPoint(0.5, 0.0), biomeId: kBiomeIdForest);
    const oneStar = LevelProgress(
        levelId: 9, state: LevelCompletionState.completed, stars: 1);
    const noStars = LevelProgress(
        levelId: 9, state: LevelCompletionState.completed, stars: 0);

    expect(defaultSagaNodeSemanticsLabel(level, oneStar),
        'Level 9, completed, 1 star');
    expect(defaultSagaNodeSemanticsLabel(level, noStars), 'Level 9, completed');
    expect(defaultSagaNodeSemanticsLabel(level, null), 'Level 9');
  });
}
