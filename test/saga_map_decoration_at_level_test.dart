import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _generator = SagaMapLevelGenerator();

List<LevelData> _chunk(int index) => _generator.generateLevels(
      globalSeed: 5,
      config: _config,
      startLevelId: index * _levelsPerChunk,
      count: _levelsPerChunk,
    );

void main() {
  test('SagaMapDecoration.atLevel creates proper instance', () {
    final dec = SagaMapDecoration.atLevel(
      levelId: 10,
      height: 100,
      builder: (context) => const SizedBox(),
    );
    expect(dec.levelId, 10);
    expect(dec.height, 100);
    expect(dec.chunkFraction, isNull);
    expect(dec.pathPosition, isNull);
  });

  // Regression: atLevel decorations were never handled by the chunk renderer,
  // so a host that used one crashed with a null-check on pathPosition, and the
  // box collapsed to zero even after that. Render one and assert it lands on
  // its level at the requested size.
  testWidgets('atLevel decoration renders at its level, at its height',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MapChunkWidget(
              chunkContext: SagaChunkContext(
                  chunkIndex: 0, levels: _chunk(0), progress: const {}),
              levels: _chunk(0),
              chunkIndex: 0,
              chunkExtent: 800,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              lateralBounds: _config.lateralBounds,
              trailingNeighbors: _chunk(1).sublist(0, 2),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              responsiveResolver: SagaResponsiveResolver(
                config: SagaMapResponsiveConfig.defaults.copyWith(
                  nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
                  zoomPolicy: const SagaMapValuePolicy.all(1.0),
                ),
              ),
              decorationBuilder: (context, chunk) => [
                SagaMapDecoration.atLevel(
                  levelId: 4,
                  height: 30,
                  scaleWithZoom: false,
                  builder: (context) =>
                      const SizedBox.expand(key: ValueKey('flag')),
                ),
              ],
              nodeBuilder: (context, level, layout) =>
                  SizedBox.expand(key: ValueKey('node-${level.id}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final flagFinder = find.byKey(const ValueKey('flag'));
    expect(flagFinder, findsOneWidget);

    // Sized by `height`, not collapsed to zero.
    final size = tester.getSize(flagFinder);
    expect(size.width, 30);
    expect(size.height, 30);

    // Anchored to level 4's node, not to a raw coordinate.
    final node = tester.getCenter(find.byKey(const ValueKey('node-4')));
    final flag = tester.getCenter(flagFinder);
    expect((flag.dx - node.dx).abs(), lessThan(40));
    expect((flag.dy - node.dy).abs(), lessThan(40));
  });

  // Backward-compat: chunkContext is optional. A host that used MapChunkWidget
  // before 1.1.0 (no chunkContext) still works, and a context-aware
  // decorationBuilder receives a context derived from the widget's own levels.
  testWidgets('decorationBuilder works without an explicit chunkContext',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    int? seenIndex;
    int seenLevelCount = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MapChunkWidget(
              // chunkContext intentionally omitted.
              levels: _chunk(2),
              chunkIndex: 2,
              chunkExtent: 800,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              lateralBounds: _config.lateralBounds,
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              decorationBuilder: (context, chunk) {
                seenIndex = chunk.chunkIndex;
                seenLevelCount = chunk.levels.length;
                return const <SagaMapDecoration>[];
              },
              nodeBuilder: (context, level, layout) => const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(seenIndex, 2);
    expect(seenLevelCount, _levelsPerChunk);
  });
}
