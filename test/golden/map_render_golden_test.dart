@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Visual regression net for map rendering.
///
/// Geometry is asserted numerically elsewhere; these catch the things numbers
/// miss — a path drawn behind the background, a chunk seam that visibly breaks,
/// nodes clipped at a lateral edge.
///
/// Regenerate after an intentional visual change:
///
/// ```bash
/// flutter test --update-goldens test/golden
/// ```
///
/// Exclude on platforms that do not match the reference renderer:
///
/// ```bash
/// flutter test --exclude-tags golden
/// ```
const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 8;
const _pixelsPerLevel = 64.0;

/// Hand-authored levels, so these goldens track rendering rather than doubling
/// as a generator snapshot.
const _fixedLevels = <LevelData>[
  LevelData(id: 0, position: SagaPoint(0.30, 0.00), biomeId: kBiomeIdForest),
  LevelData(id: 1, position: SagaPoint(0.70, 0.25), biomeId: kBiomeIdForest),
  LevelData(id: 2, position: SagaPoint(0.30, 0.50), biomeId: kBiomeIdDesert),
  LevelData(id: 3, position: SagaPoint(0.70, 0.75), biomeId: kBiomeIdDesert),
];

Widget _node(BuildContext context, LevelData level, ResolvedSagaLayout layout) {
  return const DecoratedBox(
    decoration: BoxDecoration(
      color: Color(0xFFFFC107),
      shape: BoxShape.circle,
    ),
  );
}

SagaResponsiveResolver _resolver(SagaMapPathAxis pathAxis) {
  return SagaResponsiveResolver(
    config: SagaMapResponsiveConfig.defaults.copyWith(pathAxis: pathAxis),
  );
}

/// High-contrast pair so the split is unmistakable in a golden.
class _ProgressThemeResolver implements SagaBiomeThemeResolver {
  const _ProgressThemeResolver();

  @override
  SagaBiomeTheme resolve(String biomeId) => const SagaBiomeTheme(
        backgroundColor: Color(0xFF2D5A27),
        pathFillColor: Color(0xFFFFC107),
        pathBorderColor: Color(0xFF7A5C00),
        upcomingPathFillColor: Color(0xFF6B7A66),
        upcomingPathBorderColor: Color(0xFF3E4A3B),
        shadowColor: Color(0x40000000),
        pathBorderWidth: 10,
        pathInnerStrokeWidth: 6,
      );
}

void main() {
  void useViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  // Every breakpoint, not a sample: each resolves different node sizing,
  // spacing and lateral capping, so each is its own rendering path.
  const devices = <String, Size>{
    'mobile': Size(360, 640),
    'tablet': Size(700, 900),
    'desktop': Size(1000, 600),
    'ultra4k': Size(2200, 900),
  };

  for (final pathAxis in SagaMapPathAxis.values) {
    for (final device in devices.entries) {
      testWidgets('single chunk — ${pathAxis.name} on ${device.key}',
          (tester) async {
        useViewport(tester, device.value);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: pathAxis == SagaMapPathAxis.horizontal
                    ? Axis.horizontal
                    : Axis.vertical,
                child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
                  levels: _fixedLevels,
                  chunkIndex: 0,
                  chunkExtent: 520,
                  chunkSpanNormalized: 1.0,
                  biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                  responsiveResolver: _resolver(pathAxis),
                  nodeBuilder: _node,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/single_chunk_${pathAxis.name}_${device.key}.png',
          ),
        );
      });
    }
  }

  for (final curvature in const [0.0, 1.0]) {
    final label = curvature == 0 ? 'straight' : 'curved';

    testWidgets('chunk seam stays continuous — horizontal, $label',
        (tester) async {
      // Wide enough to show two whole chunks and the seam between them. With
      // curvature this is the shot that would expose a kink at the join.
      useViewport(tester, const Size(1100, 400));
      const generator = SagaMapLevelGenerator();
      final controller = SagaInfiniteMapController(
        sectionsPerChunk: _levelsPerChunk,
        initialChunkCount: 3,
        chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
          globalSeed: 7,
          config: _config,
          startLevelId: chunkIndex * sectionsPerChunk,
          count: sectionsPerChunk,
        ),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: _levelsPerChunk * _pixelsPerLevel,
              chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
              lateralBounds: _config.lateralBounds,
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              responsiveResolver: _resolver(SagaMapPathAxis.horizontal),
              pathCurvature: curvature,
              nodeBuilder: _node,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/chunk_seam_horizontal_$label.png'),
      );
    });
  }

  for (final progress in const <double?>[null, 1.5]) {
    final label = progress == null ? 'untracked' : 'partway';

    testWidgets('walked path is painted apart — $label', (tester) async {
      useViewport(tester, const Size(360, 640));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
                levels: _fixedLevels,
                chunkIndex: 0,
                chunkExtent: 520,
                chunkSpanNormalized: 1.0,
                pathCurvature: 1,
                pathProgressPosition: progress,
                // Dim ahead, bright behind: the road lights up as you go.
                biomeThemeResolver: const _ProgressThemeResolver(),
                responsiveResolver: _resolver(SagaMapPathAxis.vertical),
                nodeBuilder: _node,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/path_progress_$label.png'),
      );
    });
  }

  testWidgets('curvature rounds a single chunk', (tester) async {
    useViewport(tester, const Size(360, 640));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
              levels: _fixedLevels,
              chunkIndex: 0,
              chunkExtent: 520,
              chunkSpanNormalized: 1.0,
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              responsiveResolver: _resolver(SagaMapPathAxis.vertical),
              pathCurvature: 1.0,
              nodeBuilder: _node,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/single_chunk_vertical_curved.png'),
    );
  });
}
