import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;

/// Controller whose loader counts calls, so eviction and reload are observable.
({SagaInfiniteMapController controller, List<int> loads}) _controller({
  int? maxRetainedChunks,
  int initialChunkCount = 3,
}) {
  const generator = SagaMapLevelGenerator();
  final loads = <int>[];
  final controller = SagaInfiniteMapController(
    sectionsPerChunk: _levelsPerChunk,
    initialChunkCount: initialChunkCount,
    loadBatchSize: 1,
    maxRetainedChunks: maxRetainedChunks,
    chunkLoader: (chunkIndex, sectionsPerChunk) {
      loads.add(chunkIndex);
      return generator.generateLevels(
        globalSeed: 42,
        config: _config,
        startLevelId: chunkIndex * sectionsPerChunk,
        count: sectionsPerChunk,
      );
    },
  );
  return (controller: controller, loads: loads);
}

void main() {
  test('retains every chunk by default', () async {
    final harness = _controller(initialChunkCount: 6);
    addTearDown(harness.controller.dispose);

    await harness.controller.initialize();

    expect(harness.controller.loadedChunkCount, 6);
    expect(harness.controller.retainedChunkCount, 6);
  });

  test('evicts down to the retention budget', () async {
    final harness = _controller(maxRetainedChunks: 3, initialChunkCount: 6);
    addTearDown(harness.controller.dispose);

    await harness.controller.initialize();

    // Progress is unaffected; only the in-memory cache shrinks.
    expect(harness.controller.loadedChunkCount, 6);
    expect(harness.controller.retainedChunkCount, 3);
  });

  test('keeps the chunks nearest the one being read', () async {
    final harness = _controller(maxRetainedChunks: 3, initialChunkCount: 3);
    addTearDown(harness.controller.dispose);
    await harness.controller.initialize();

    // Reading chunk 5 makes it the anchor for the next eviction.
    harness.controller.chunkLevels(5);
    await harness.controller.loadMore(count: 3);

    expect(harness.controller.retainedChunkCount, 3);
    expect(harness.controller.chunkLevels(5), isNotEmpty);
    expect(harness.controller.chunkLevels(4), isNotEmpty);
  });

  testWidgets('an evicted chunk reloads when read again', (tester) async {
    final harness = _controller(maxRetainedChunks: 2, initialChunkCount: 5);
    addTearDown(harness.controller.dispose);

    await harness.controller.initialize();
    expect(harness.controller.retainedChunkCount, 2);

    final evicted = List<int>.generate(5, (i) => i)
        .firstWhere((i) => !harness.controller.chunkLevels(i).isNotEmpty);
    final loadsBefore = harness.loads.length;

    // A widget host is needed: reloads run post-frame, so that requesting a
    // chunk during build never notifies listeners mid-build.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: harness.controller,
            chunkExtent: 600,
            chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.loads.length, greaterThan(loadsBefore));
    expect(harness.controller.chunkLevels(evicted), isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a budget below the visible working set does not thrash',
      (tester) async {
    // Budget 1 is smaller than what the viewport shows. The working-set
    // protection must turn this into "budget exceeded" rather than an endless
    // evict-reload-evict loop, which would hang pumpAndSettle.
    final harness = _controller(maxRetainedChunks: 1, initialChunkCount: 6);
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: harness.controller,
            chunkExtent: 200,
            chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(harness.controller.retainedChunkCount, greaterThanOrEqualTo(1));
  });

  test('a reloaded chunk is identical to the evicted one', () async {
    final harness = _controller(initialChunkCount: 2);
    addTearDown(harness.controller.dispose);
    await harness.controller.initialize();

    final original = harness.controller.chunkLevels(1);
    harness.controller.reset();
    await harness.controller.initialize();

    // Deterministic loaders are what make eviction safe in the first place.
    expect(harness.controller.chunkLevels(1), equals(original));
  });

  test('never reloads a chunk that was never generated', () async {
    final harness = _controller(maxRetainedChunks: 2, initialChunkCount: 2);
    addTearDown(harness.controller.dispose);
    await harness.controller.initialize();

    final loadsBefore = harness.loads.length;
    expect(harness.controller.chunkLevels(99), isEmpty);

    await Future<void>.delayed(Duration.zero);
    expect(harness.loads.length, loadsBefore);
  });
}
