import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 5;
const _chunkExtent = 400.0;

SagaInfiniteMapController _controller() {
  const generator = SagaMapLevelGenerator();
  return SagaInfiniteMapController(
    sectionsPerChunk: _levelsPerChunk,
    initialChunkCount: 3,
    chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
      globalSeed: 1,
      config: _config,
      startLevelId: chunkIndex * sectionsPerChunk,
      count: sectionsPerChunk,
    ),
  );
}

void main() {
  Future<void> pumpMap(
    WidgetTester tester,
    SagaInfiniteMapController controller,
    TextDirection direction,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: _chunkExtent,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              lateralBounds: _config.lateralBounds,
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              responsiveResolver: SagaResponsiveResolver(
                config: SagaMapResponsiveConfig.defaults.copyWith(
                  pathAxis: SagaMapPathAxis.horizontal,
                  nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
                ),
              ),
              nodeBuilder: (context, level, layout) =>
                  SizedBox.expand(key: ValueKey('node-${level.id}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double alongOf(WidgetTester tester, int id) =>
      tester.getCenter(find.byKey(ValueKey('node-$id'))).dx;

  testWidgets('a right-to-left horizontal map advances leftwards',
      (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await pumpMap(tester, controller, TextDirection.rtl);

    // Later levels must sit further left, matching the chunk list's own
    // right-to-left ordering.
    expect(alongOf(tester, 1), lessThan(alongOf(tester, 0)));
    expect(alongOf(tester, 4), lessThan(alongOf(tester, 1)));
  });

  testWidgets('a right-to-left seam keeps uniform spacing', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await pumpMap(tester, controller, TextDirection.rtl);

    // Level 4 ends chunk 0 and level 5 opens chunk 1. Before the mirroring fix
    // this step jumped the full width of a chunk backwards.
    final withinChunk = alongOf(tester, 3) - alongOf(tester, 4);
    final acrossSeam = alongOf(tester, 4) - alongOf(tester, 5);

    expect(acrossSeam, moreOrLessEquals(withinChunk, epsilon: 0.5));
    expect(acrossSeam, greaterThan(0));
  });

  testWidgets('left-to-right is the exact mirror of right-to-left',
      (tester) async {
    final ltrController = _controller();
    addTearDown(ltrController.dispose);
    await pumpMap(tester, ltrController, TextDirection.ltr);
    final ltrStep = alongOf(tester, 5) - alongOf(tester, 4);

    final rtlController = _controller();
    addTearDown(rtlController.dispose);
    await pumpMap(tester, rtlController, TextDirection.rtl);
    final rtlStep = alongOf(tester, 5) - alongOf(tester, 4);

    expect(rtlStep, moreOrLessEquals(-ltrStep, epsilon: 0.5));
  });

  testWidgets('a vertical map is unaffected by text direction',
      (tester) async {
    Future<double> firstNodeY(TextDirection direction) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(600, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: SagaInfiniteMapView(
                controller: controller,
                chunkExtent: _chunkExtent,
                chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
                lateralBounds: _config.lateralBounds,
                biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                nodeBuilder: (context, level, layout) =>
                    SizedBox.expand(key: ValueKey('node-${level.id}')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getCenter(find.byKey(const ValueKey('node-1'))).dy;
    }

    // Chunks stack downwards either way, so mirroring must not apply here.
    expect(await firstNodeY(TextDirection.rtl),
        moreOrLessEquals(await firstNodeY(TextDirection.ltr), epsilon: 0.5));
  });
}
