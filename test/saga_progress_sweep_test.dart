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

  testWidgets('A-03 — replacing a chunk\'s levels refreshes its context '
      'even when progress is unchanged', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    // NOTE: this passes with the A-03 guard removed, and the reason belongs
    // here. Reaching the defect needs a chunk whose cached context survives
    // while its level list is replaced, and today nothing does that:
    // `_pruneEvictedContexts` drops the context first, and mid-scroll eviction
    // is itself latched off (see `saga_chunk_retention_test.dart`, A-08). The
    // guard is still right — it is the invariant the host's builders depend
    // on, it costs one identity comparison, and the sibling test below pins
    // that it does not rebuild contexts needlessly.
    //
    // Two worlds with the same ids, so every level's resolved progress is
    // identical across the swap. Only the LevelData differs — which is exactly
    // what the host's decoration builder reads.
    var seed = 5;
    final controller = SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 2,
      chunkLoader: (chunkIndex, sectionsPerChunk) => _generator.generateLevels(
        globalSeed: seed,
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
            // Constant across both worlds: the progress diff cannot fire.
            progressResolver: (level) => const LevelProgress(
              levelId: 0,
              state: LevelCompletionState.unlocked,
            ),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    MapChunkWidget firstChunk() =>
        tester.widgetList<MapChunkWidget>(find.byType(MapChunkWidget)).first;

    // `SagaChunkContext` copies its list into an unmodifiable view, so the two
    // are never the same object; what must match is the elements, which are
    // the `LevelData` the host's builders actually read.
    void expectContextDescribesItsChunk(String reason) {
      final chunk = firstChunk();
      expect(chunk.chunkContext!.levels.length, chunk.levels.length,
          reason: reason);
      for (var i = 0; i < chunk.levels.length; i++) {
        expect(identical(chunk.chunkContext!.levels[i], chunk.levels[i]),
            isTrue,
            reason: reason);
      }
    }

    expectContextDescribesItsChunk(
        'the context must start out describing the list beside it');

    seed = 99;
    controller.reset();
    await controller.initialize();
    await tester.pumpAndSettle();

    // The context the host's builders receive must describe the world on
    // screen. Before A-03 the refresh was gated on `progressChanged` alone, so
    // this context still carried the seed-5 list.
    expectContextDescribesItsChunk(
        "the context still carries the previous world's levels");
  });

  testWidgets('A-03 — an unchanged chunk keeps the context object it had',
      (tester) async {
    // A-03 must not undo T-18. The sweep gate already skips an unchanged chunk
    // entirely, so resolver calls cannot tell a good levels check from a bad
    // one; what a bad one costs is a *fresh context* on every sweep that does
    // run — a `List.unmodifiable` copy and a dominant-biome pass per chunk,
    // handed to the host's builders as if the world had changed.
    //
    // Comparing against `SagaChunkContext.levels` is the bad one: the context
    // copies its list, so that comparison is true forever. Comparing against
    // the raw source list the last sweep ran on is the good one. This test
    // tells them apart.
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

    Widget build() => MaterialApp(
          home: Scaffold(
            body: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 600,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              progressResolver: (level) => const LevelProgress(
                levelId: 0,
                state: LevelCompletionState.unlocked,
              ),
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

    final before = firstContext();

    // A host rebuild with a new widget instance: the epoch moves and the sweep
    // runs. But nothing it finds has changed — same levels, same progress — so
    // the context must be the object it already was.
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(
      identical(firstContext(), before),
      isTrue,
      reason: 'a sweep that found nothing changed rebuilt the context anyway',
    );
  });

  testWidgets('A-04 — a host that never rebuilds the widget still sees '
      'progress move', (tester) async {
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

    final notifier = ChangeNotifier();
    addTearDown(notifier.dispose);
    var state = LevelCompletionState.locked;

    // The performance-minded host: the view is built once and stored, so every
    // later rebuild hands Flutter the *same* instance and `didUpdateWidget`
    // never runs. Before A-04 the epoch only moved there, so this host never
    // saw progress refresh at all.
    final view = SagaInfiniteMapView(
      controller: controller,
      chunkExtent: 600,
      chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
      biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
      progressResolver: (level) => LevelProgress(levelId: level.id, state: state),
      progressListenable: notifier,
      nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Builder(builder: (_) => view))),
    );
    await tester.pumpAndSettle();

    SagaChunkContext firstContext() => tester
        .widgetList<MapChunkWidget>(find.byType(MapChunkWidget))
        .first
        .chunkContext!;

    expect(firstContext().progress[0]?.state, LevelCompletionState.locked);

    state = LevelCompletionState.completed;
    notifier.notifyListeners();
    await tester.pumpAndSettle();

    expect(firstContext().progress[0]?.state, LevelCompletionState.completed);
  });
}
