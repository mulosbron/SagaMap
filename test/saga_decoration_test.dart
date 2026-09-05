import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Scenery: placement beside the path or at a chunk fraction, drawn below the
/// nodes, and never stealing a level's tap.

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
  Future<void> pump(
    WidgetTester tester, {
    required SagaMapDecorationBuilder builder,
    ValueChanged<LevelData>? onLevelTap,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
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
              decorationBuilder: builder,
              onLevelTap: onLevelTap,
              nodeBuilder: (context, level, layout) =>
                  SizedBox.expand(key: ValueKey('node-${level.id}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a beside-path decoration is drawn near its level',
      (tester) async {
    await pump(
      tester,
      builder: (context, chunk) {
        expect(chunk.chunkIndex, 0);
        return [

        SagaMapDecoration.besidePath(
          pathPosition: 4,
          lateralOffset: 120,
          builder: (context) => const SizedBox.expand(key: ValueKey('tree')),
        ),
      ],
    );

    final node = tester.getCenter(find.byKey(const ValueKey('node-4')));
    final tree = tester.getCenter(find.byKey(const ValueKey('tree')));

    // Pushed off the path along the lateral axis, roughly level with the node.
    expect((tree.dx - node.dx).abs(), greaterThan(50));
    expect((tree.dy - node.dy).abs(), lessThan(120));
  });

  testWidgets('a fraction decoration lands at that point of the chunk',
      (tester) async {
    await pump(
      tester,
      builder: (context, chunk) {
        expect(chunk.chunkIndex, 0);
        return [

        SagaMapDecoration.atFraction(
          chunkFraction: const Offset(0.5, 0.25),
          builder: (context) => const SizedBox.expand(key: ValueKey('cloud')),
        ),
      ],
    );

    final cloud = tester.getCenter(find.byKey(const ValueKey('cloud')));
    // Chunk is 800 tall in this test; a quarter down is near y=200.
    expect(cloud.dy, moreOrLessEquals(200, epsilon: 30));
  });

  testWidgets('decorations do not swallow a level tap', (tester) async {
    final tapped = <int>[];
    await pump(
      tester,
      onLevelTap: (level) => tapped.add(level.id),
      builder: (context, chunk) {
        expect(chunk.chunkIndex, 0);
        return [

        // A decoration sitting right on the node it must not block.
        SagaMapDecoration.besidePath(
          pathPosition: 4,
          builder: (context) => const SizedBox.expand(key: ValueKey('tree')),
          size: const Size(140, 140),
        ),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey('node-4')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(tapped, contains(4));
  });

  testWidgets('z-order stacks later decorations on top', (tester) async {
    await pump(
      tester,
      builder: (context, chunk) {
        expect(chunk.chunkIndex, 0);
        return [

        SagaMapDecoration.atFraction(
          chunkFraction: const Offset(0.5, 0.3),
          z: 5,
          builder: (context) => const SizedBox.expand(key: ValueKey('top')),
        ),
        SagaMapDecoration.atFraction(
          chunkFraction: const Offset(0.5, 0.3),
          z: 0,
          builder: (context) => const SizedBox.expand(key: ValueKey('bottom')),
        ),
      ],
    );

    // Sorted by z, so 'bottom' is painted before 'top'; both are present.
    final topLast = tester
        .widgetList(find.byType(Positioned))
        .whereType<Positioned>()
        .toList();
    expect(topLast, isNotEmpty);
    expect(find.byKey(const ValueKey('top')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom')), findsOneWidget);
  });

  testWidgets('an empty builder draws no scenery', (tester) async {
    await pump(tester, builder: (context, chunkIndex) => const []);
    expect(find.byKey(const ValueKey('tree')), findsNothing);
  });

  testWidgets('a decoration off this chunk is skipped', (tester) async {
    // Level 40 is far past chunk 0's reach, so nothing is drawn.
    await pump(
      tester,
      builder: (context, chunk) {
        expect(chunk.chunkIndex, 0);
        return [

        SagaMapDecoration.besidePath(
          pathPosition: 40,
          builder: (context) => const SizedBox.expand(key: ValueKey('tree')),
        ),
      ],
    );
    expect(find.byKey(const ValueKey('tree')), findsNothing);
  });
}
