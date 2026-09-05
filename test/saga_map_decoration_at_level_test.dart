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
  // box collapsed to zero even after that. Per 041 an atLevel decoration is a
  // band: full width across the lateral axis, `height` thick along the path
  // axis, aligned with its level and ignoring the path's wander.
  testWidgets('atLevel renders as a full-width band aligned to its level',
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
              chunkDecorationBuilder: (context, chunk) => [
                SagaMapDecoration.atLevel(
                  levelId: 4,
                  height: 30,
                  scaleWithZoom: false,
                  builder: (context) =>
                      const SizedBox.expand(key: ValueKey('band')),
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

    final bandFinder = find.byKey(const ValueKey('band'));
    expect(bandFinder, findsOneWidget);

    // A band: `height` thick, spanning the chunk's full lateral width.
    final chunkWidth = tester.getSize(find.byType(MapChunkWidget)).width;
    final size = tester.getSize(bandFinder);
    expect(size.height, 30);
    expect(size.width, moreOrLessEquals(chunkWidth, epsilon: 0.5));

    // Aligned with level 4 along the path axis, and centred laterally rather
    // than following the path's wander.
    final node = tester.getCenter(find.byKey(const ValueKey('node-4')));
    final band = tester.getCenter(bandFinder);
    expect(band.dy, moreOrLessEquals(node.dy, epsilon: 1.0));
    expect(band.dx, moreOrLessEquals(chunkWidth / 2, epsilon: 1.0));
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
              chunkDecorationBuilder: (context, chunk) {
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
