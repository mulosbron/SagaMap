import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 20;

SagaInfiniteMapController _controller({int? maxChunkCount}) {
  const generator = SagaMapLevelGenerator();
  return SagaInfiniteMapController(
    sectionsPerChunk: _levelsPerChunk,
    initialChunkCount: 3,
    loadBatchSize: 2,
    maxChunkCount: maxChunkCount,
    chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
      globalSeed: 42,
      config: _config,
      startLevelId: chunkIndex * sectionsPerChunk,
      count: sectionsPerChunk,
    ),
  );
}

Widget _app(
  SagaInfiniteMapController controller,
  SagaMapPathAxis pathAxis, {
  ValueChanged<LevelData>? onLevelTap,
  ValueChanged<LevelData>? onLevelLongPress,
  SagaNodeInteractionHandler? interactionHandler,
  LevelProgress? Function(LevelData)? progressResolver,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SagaInfiniteMapView(
        controller: controller,
        chunkExtent: _levelsPerChunk * 92,
        chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
        lateralBounds: _config.lateralBounds,
        biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
        onLevelTap: onLevelTap,
        onLevelLongPress: onLevelLongPress,
        interactionHandler:
            interactionHandler ?? const SagaNodeInteractionHandler(),
        progressResolver: progressResolver,
        // Spacing is neutralised so seam geometry can be measured against the
        // declared chunkExtent directly; it has dedicated tests elsewhere.
        responsiveResolver: SagaResponsiveResolver(
          config: SagaMapResponsiveConfig.defaults.copyWith(
            pathAxis: pathAxis,
            nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
          ),
        ),
        nodeBuilder: (context, level, layout) =>
            SizedBox.expand(key: ValueKey('node-${level.id}')),
      ),
    ),
  );
}

void main() {
  void useViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  for (final entry in {
    SagaMapPathAxis.horizontal: Axis.horizontal,
    SagaMapPathAxis.vertical: Axis.vertical,
  }.entries) {
    testWidgets('${entry.key.name} map renders and scrolls on ${entry.value}',
        (tester) async {
      useViewport(tester, const Size(390, 844));
      final controller = _controller();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(controller, entry.key));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(controller.loadedChunkCount, 3);

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.scrollDirection, entry.value);

      // The very first level of the map must be on screen at rest.
      expect(find.byKey(const ValueKey('node-0')), findsOneWidget);
    });
  }

  testWidgets('chunks tile end to end with no dead lane between them',
      (tester) async {
    // Wide enough to hold two whole chunks, so seam geometry is measured
    // directly rather than through scroll offsets.
    useViewport(tester, const Size(4000, 900));
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, SagaMapPathAxis.horizontal));
    await tester.pumpAndSettle();

    // Level 0 opens chunk 0, level 20 opens chunk 1: exactly one chunkExtent
    // apart. Any lateral capping applied to the path axis would shrink this.
    const chunkExtent = _levelsPerChunk * 92.0;
    final first = tester.getCenter(find.byKey(const ValueKey('node-0')));
    final next = tester.getCenter(find.byKey(const ValueKey('node-20')));
    expect(next.dx - first.dx, moreOrLessEquals(chunkExtent, epsilon: 0.5));
  });

  testWidgets('node spacing stays uniform across a chunk seam', (tester) async {
    useViewport(tester, const Size(4000, 900));
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, SagaMapPathAxis.horizontal));
    await tester.pumpAndSettle();

    double alongOf(int id) =>
        tester.getCenter(find.byKey(ValueKey('node-$id'))).dx;

    // The 19 -> 20 step crosses a chunk boundary; it must match an ordinary
    // within-chunk step. An end inset would make it visibly wider.
    final withinChunk = alongOf(19) - alongOf(18);
    final acrossSeam = alongOf(20) - alongOf(19);
    expect(acrossSeam, moreOrLessEquals(withinChunk, epsilon: 0.5));
  });

  testWidgets('lateral band does not drift across a chunk seam',
      (tester) async {
    useViewport(tester, const Size(4000, 900));
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, SagaMapPathAxis.horizontal));
    await tester.pumpAndSettle();

    double lateralOf(int id) =>
        tester.getCenter(find.byKey(ValueKey('node-$id'))).dy;

    // Generated levels alternate between two lateral targets, so equal parity
    // across a seam means equal lateral placement — within jitter amplitude.
    final beforeSeam = lateralOf(18);
    final afterSeam = lateralOf(20);
    expect((afterSeam - beforeSeam).abs(), lessThan(80));
  });

  testWidgets('respects maxChunkCount and reports the limit', (tester) async {
    useViewport(tester, const Size(390, 844));
    final controller = _controller(maxChunkCount: 2);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, SagaMapPathAxis.vertical));
    await tester.pumpAndSettle();

    expect(controller.loadedChunkCount, 2);
    expect(controller.hasReachedEnd, isTrue);
    await controller.loadMore();
    expect(controller.loadedChunkCount, 2);
  });

  testWidgets('surfaces a loader failure instead of rendering blank',
      (tester) async {
    useViewport(tester, const Size(390, 844));
    final controller = SagaInfiniteMapController(
      chunkLoader: (_, __) => throw StateError('boom'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller, SagaMapPathAxis.vertical));
    await tester.pumpAndSettle();

    expect(controller.lastError, isStateError);
    expect(find.textContaining('Failed to load chunks'), findsOneWidget);
  });

  test('reset returns the controller to its initial state', () async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.loadedChunkCount, 3);

    controller.reset();
    expect(controller.loadedChunkCount, 0);
    expect(controller.chunkLevels(0), isEmpty);

    await controller.initialize();
    expect(controller.loadedChunkCount, 3);
  });

  testWidgets('onLevelLongPress is fired on a long press event',
      (tester) async {
    useViewport(tester, const Size(390, 844));
    final controller = _controller();
    addTearDown(controller.dispose);

    LevelData? tapped;
    LevelData? longPressed;

    await tester.pumpWidget(_app(
      controller,
      SagaMapPathAxis.vertical,
      progressResolver: (l) =>
          LevelProgress(levelId: l.id, state: LevelCompletionState.unlocked),
      onLevelTap: (l) => tapped = l,
      onLevelLongPress: (l) => longPressed = l,
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(GestureDetector).first);
    expect(longPressed, isNotNull);
    expect(tapped, isNull);
  });

  testWidgets('interactionHandler.onNodeLongPress wins over onLevelLongPress',
      (tester) async {
    useViewport(tester, const Size(390, 844));
    final controller = _controller();
    addTearDown(controller.dispose);

    LevelData? viewLongPressed;
    LevelData? handlerLongPressed;

    await tester.pumpWidget(_app(
      controller,
      SagaMapPathAxis.vertical,
      progressResolver: (l) =>
          LevelProgress(levelId: l.id, state: LevelCompletionState.unlocked),
      interactionHandler: SagaNodeInteractionHandler(
        onNodeLongPress: (l) => handlerLongPressed = l,
      ),
      onLevelLongPress: (l) => viewLongPressed = l,
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(GestureDetector).first);
    expect(handlerLongPressed, isNotNull);
    expect(viewLongPressed, isNull);
  });

  testWidgets('onLevelLongPress blocked by canLongPress (locked node)',
      (tester) async {
    useViewport(tester, const Size(390, 844));
    final controller = _controller();
    addTearDown(controller.dispose);

    LevelData? longPressed;

    await tester.pumpWidget(_app(
      controller,
      SagaMapPathAxis.vertical,
      progressResolver: (l) =>
          LevelProgress(levelId: l.id, state: LevelCompletionState.locked),
      onLevelLongPress: (l) => longPressed = l,
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(GestureDetector).first);
    expect(longPressed, isNull);
  });
}
