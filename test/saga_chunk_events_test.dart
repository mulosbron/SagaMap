import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 5;

SagaInfiniteMapController _controller() {
  const generator = SagaMapLevelGenerator();
  return SagaInfiniteMapController(
    sectionsPerChunk: _levelsPerChunk,
    initialChunkCount: 3,
    loadBatchSize: 2,
    chunkLoader: (chunkIndex, sectionsPerChunk) async =>
        generator.generateLevels(
      globalSeed: 42,
      config: _config,
      startLevelId: chunkIndex * sectionsPerChunk,
      count: sectionsPerChunk,
    ),
  );
}

void main() {
  testWidgets('onChunkEnter is called correctly when scrolling across 3 chunks',
      (tester) async {
    final controller = _controller();
    final enteredChunks = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 500,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              nodeBuilder: (context, level, layout) =>
                  const SizedBox(width: 50, height: 50),
              onChunkEnter: (chunk) {
                enteredChunks.add(chunk.chunkIndex);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(enteredChunks, [0]);

    // Scroll to the middle of chunk 1
    await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(enteredChunks, [0, 1]);

    // Scroll to the middle of chunk 2
    await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(enteredChunks, [0, 1, 2]);
  });

  testWidgets('onChunkEnter does not repeat on boundary hysteresis',
      (tester) async {
    final controller = _controller();
    final enteredChunks = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 500,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              nodeBuilder: (context, level, layout) =>
                  const SizedBox(width: 50, height: 50),
              onChunkEnter: (chunk) {
                enteredChunks.add(chunk.chunkIndex);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(enteredChunks, [0]);

    await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(enteredChunks, [0, 1]);

    await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, 10));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, -10));
    await tester.pumpAndSettle();

    expect(enteredChunks, [0, 1]);

    await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(enteredChunks, [0, 1, 0]);
  });

  testWidgets('onLevelReached fires only on forward transition',
      (tester) async {
    final controller = _controller();
    final reachedLevels = <int>[];

    final charController = SagaCharacterController(vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 500,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              nodeBuilder: (context, level, layout) =>
                  const SizedBox(width: 50, height: 50),
              character: SagaCharacter(
                controller: charController,
                builder: (context, state) =>
                    const SizedBox(width: 20, height: 20),
              ),
              onLevelReached: (level) {
                reachedLevels.add(level.id);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    charController.jumpTo(0.0);
    await tester.pumpAndSettle();
    expect(reachedLevels, isEmpty);

    charController.jumpTo(1.2);
    await tester.pumpAndSettle();
    expect(reachedLevels, [1]);

    charController.jumpTo(0.5);
    await tester.pumpAndSettle();
    expect(reachedLevels, [1]);

    charController.jumpTo(3.8);
    await tester.pumpAndSettle();
    expect(reachedLevels, [1, 3]);
  });

  testWidgets('Callbacks are not invoked after dispose', (tester) async {
    final controller = _controller();
    bool entered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 500,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              nodeBuilder: (context, level, layout) =>
                  const SizedBox(width: 50, height: 50),
              onChunkEnter: (chunk) {
                entered = true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(entered, true);

    entered = false;

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(entered, false);
  });

  testWidgets('didUpdateWidget properly respects new callbacks',
      (tester) async {
    final controller = _controller();
    int oldCalls = 0;
    int newCalls = 0;

    Widget buildMap({required bool useNew}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 500,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              nodeBuilder: (context, level, layout) =>
                  const SizedBox(width: 50, height: 50),
              onChunkEnter:
                  useNew ? (chunk) => newCalls++ : (chunk) => oldCalls++,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildMap(useNew: false));
    await tester.pumpAndSettle();
    expect(oldCalls, 1);
    expect(newCalls, 0);

    await tester.pumpWidget(buildMap(useNew: true));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(oldCalls, 1);
    expect(newCalls, 1);
  });


  testWidgets('A-09 — onChunkEnter costs no extra progress resolution',
      (tester) async {
    // Before A-09 there were two sweeps: one inline in `itemBuilder` and one
    // behind `onChunkEnter`. The callback handed the host a context built by
    // the second, so entering a chunk ran the host's `progressResolver` over
    // that whole chunk again — the exact cost T-18 was written to avoid — and
    // the two implementations had already begun to drift apart.
    //
    // Measured as a difference, because the view is not the only resolver
    // caller: `MapChunkWidget` resolves for its own nodes too. What must be
    // zero is what *installing the callback* adds.
    Future<int> resolverCalls({required bool withCallback}) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      var calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: SagaInfiniteMapView(
                controller: controller,
                chunkExtent: 500,
                chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
                biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                nodeBuilder: (context, level, layout) =>
                    const SizedBox(width: 50, height: 50),
                progressResolver: (level) {
                  calls++;
                  return LevelProgress(
                    levelId: level.id,
                    state: LevelCompletionState.unlocked,
                  );
                },
                onChunkEnter: withCallback ? (_) {} : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();
      return calls;
    }

    final without = await resolverCalls(withCallback: false);
    final with_ = await resolverCalls(withCallback: true);

    expect(
      with_,
      without,
      reason: 'onChunkEnter is resolving the chunk a second time',
    );
  });

  testWidgets('A-09 — onChunkEnter is handed the context the builders drew',
      (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final entered = <SagaChunkContext>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 500,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              nodeBuilder: (context, level, layout) =>
                  const SizedBox(width: 50, height: 50),
              progressResolver: (level) => LevelProgress(
                levelId: level.id,
                state: LevelCompletionState.unlocked,
              ),
              onChunkEnter: entered.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(entered, isNotEmpty, reason: 'the drag must enter a chunk');

    // One sweep, one context: the object the host is handed is the very object
    // the chunk widget was built with, so the two can no longer drift.
    var compared = 0;
    for (final context in entered) {
      for (final chunk
          in tester.widgetList<MapChunkWidget>(find.byType(MapChunkWidget))) {
        if (chunk.chunkIndex != context.chunkIndex) continue;
        expect(
          identical(chunk.chunkContext, context),
          isTrue,
          reason: 'onChunkEnter got a context the builders never saw',
        );
        compared++;
      }
    }
    expect(compared, greaterThan(0),
        reason: 'no entered chunk was still on screen to compare');
  });
}
