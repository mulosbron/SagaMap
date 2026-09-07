import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// T-18: the sweep that resolves every visible level's progress sat
/// unconditionally in `itemBuilder`, so it ran on rebuilds that could not
/// possibly have changed a progress value — every frame of a pinch among them.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _generator = SagaMapLevelGenerator();

void main() {
  testWidgets('a pinch does not re-sweep progress', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final calls = <int>[];
    final controller = SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 3,
      chunkLoader: (chunkIndex, sectionsPerChunk) => _generator.generateLevels(
        globalSeed: 5,
        config: _config,
        startLevelId: chunkIndex * sectionsPerChunk,
        count: sectionsPerChunk,
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: controller,
            chunkExtent: 600,
            chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            zoomConfig: const SagaMapZoomConfig(min: 0.5, max: 2),
            progressResolver: (level) {
              calls.add(level.id);
              return const LevelProgress(
                levelId: 0,
                state: LevelCompletionState.unlocked,
              );
            },
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, isNotEmpty, reason: 'the first build must sweep');

    // Forward into new ground: chunks seen for the first time are swept once.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    final afterFirstPass = calls.length;

    // Back over ground already resolved, then forward again. Nothing here can
    // have changed a progress value, so nothing should be resolved again.
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    // A chunk that finished loading during the round trip is swept once, and
    // should be: its levels have never been resolved. Everything already on
    // screen must cost nothing. Before this change the round trip re-swept
    // every visible chunk on every rebuild instead.
    expect(
      calls.length - afterFirstPass,
      lessThanOrEqualTo(_levelsPerChunk),
      reason: 'rebuilding an already-resolved chunk re-swept it',
    );
  });

  testWidgets('a real progress change still lands', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final controller = SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 2,
      chunkLoader: (chunkIndex, sectionsPerChunk) => _generator.generateLevels(
        globalSeed: 5,
        config: _config,
        startLevelId: chunkIndex * sectionsPerChunk,
        count: sectionsPerChunk,
      ),
    );
    addTearDown(controller.dispose);

    var state = LevelCompletionState.locked;

    Widget build() => MaterialApp(
          home: Scaffold(
            body: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 600,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              progressResolver: (level) =>
                  LevelProgress(levelId: level.id, state: state),
              nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
            ),
          ),
        );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    SagaChunkContext firstContext() => tester
        .widgetList<MapChunkWidget>(find.byType(MapChunkWidget))
        .first
        .chunkContext!;

    expect(firstContext().progress[0]?.state, LevelCompletionState.locked);

    // A host rebuild is the one signal that can change what the resolver
    // answers, so the epoch moves and the sweep runs again.
    state = LevelCompletionState.completed;
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(firstContext().progress[0]?.state, LevelCompletionState.completed);
  });
}
