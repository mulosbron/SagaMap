@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Visual record of what 1.1.0 added to the rendered map.
///
/// These are the images the README shows, so they are drawn from plain shapes
/// rather than icons or glyphs — a golden must not depend on a font being
/// available to the test renderer.
///
/// Regenerate after an intentional visual change:
///
/// ```bash
/// flutter test --update-goldens test/golden
/// ```
const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 5;

/// Hand-authored so these goldens track rendering, not the generator.
const _levels = <LevelData>[
  LevelData(id: 0, position: SagaPoint(0.28, 0.02), biomeId: kBiomeIdForest),
  LevelData(id: 1, position: SagaPoint(0.72, 0.22), biomeId: kBiomeIdForest),
  LevelData(id: 2, position: SagaPoint(0.28, 0.42), biomeId: kBiomeIdForest),
  LevelData(id: 3, position: SagaPoint(0.72, 0.62), biomeId: kBiomeIdDesert),
  LevelData(id: 4, position: SagaPoint(0.28, 0.82), biomeId: kBiomeIdForest),
];

/// Progress with stars and a host-owned `bookmarked` flag in `extra` — the
/// 1.1.0 field the library persists but never interprets.
final _progress = SagaProgress(
  currentMaxUnlockedLevelId: 2,
  levels: {
    0: LevelProgress(
      levelId: 0,
      state: LevelCompletionState.completed,
      stars: 3,
    ),
    1: LevelProgress(
      levelId: 1,
      state: LevelCompletionState.completed,
      stars: 2,
      extra: {'app.bookmarked': true},
    ),
    2: LevelProgress(levelId: 2, state: LevelCompletionState.unlocked),
    3: LevelProgress(levelId: 3, state: LevelCompletionState.locked),
    4: LevelProgress(levelId: 4, state: LevelCompletionState.locked),
  },
);

LevelProgress? _progressFor(LevelData level) => _progress.levels[level.id];

/// The tint `SagaChunkContext.dominantBiomeId` drives in the demo.
Color _biomeTint(String biomeId) {
  switch (biomeId) {
    case kBiomeIdDesert:
      return const Color(0xFFD9A441);
    case kBiomeIdGlacier:
      return const Color(0xFF7FC7E8);
    default:
      return const Color(0xFF5FA84E);
  }
}

/// A node drawn from shapes: fill by state, star pips along the bottom, and a
/// stripe when the host bookmarked it through `LevelProgress.extra`.
Widget _node(BuildContext context, LevelData level, ResolvedSagaLayout layout) {
  final progress = _progressFor(level);
  final state = progress?.state ?? LevelCompletionState.locked;
  final stars = progress?.stars ?? 0;
  final bookmarked = (progress?.extra['app.bookmarked'] as bool?) ?? false;

  final Color fill;
  switch (state) {
    case LevelCompletionState.completed:
      fill = const Color(0xFFFFC107);
    case LevelCompletionState.unlocked:
      fill = const Color(0xFF7BC96F);
    case LevelCompletionState.locked:
      fill = const Color(0xFF6B6B6B);
  }

  return DecoratedBox(
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFF23331F), width: 2),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Star pips.
        Align(
          alignment: const Alignment(0, 0.62),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < stars; i++)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: const BoxDecoration(
                    color: Color(0xFF23331F),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
        // Bookmark stripe, driven by LevelProgress.extra.
        if (bookmarked)
          const Align(
            alignment: Alignment(0.55, -0.6),
            child: SizedBox(
              width: 8,
              height: 14,
              child: ColoredBox(color: Color(0xFF1B3A17)),
            ),
          ),
      ],
    ),
  );
}

/// Scenery built from a [SagaChunkContext]: trees tinted by the chunk's
/// dominant biome, plus an `atLevel` flag pinned beside chosen levels.
List<SagaMapDecoration> _decorations(
  BuildContext context,
  SagaChunkContext chunk,
) {
  final tint = _biomeTint(chunk.dominantBiomeId);
  final base = chunk.chunkIndex * _levelsPerChunk;

  return <SagaMapDecoration>[
    for (var i = 0; i < _levelsPerChunk; i++)
      SagaMapDecoration.besidePath(
        pathPosition: (base + i).toDouble(),
        lateralOffset: i.isEven ? 96 : -96,
        size: const Size(30, 30),
        builder: (context) => DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF16250F), width: 2),
          ),
        ),
      ),
    // 1.1.0: a band aligned to the level itself, no coordinate maths. It spans
    // the chunk's full lateral width and ignores the path's wander.
    for (final levelId in const [1, 3])
      SagaMapDecoration.atLevel(
        levelId: base + levelId,
        height: 34,
        scaleWithZoom: false,
        builder: (context) => const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x66E23D3D),
            border: Border(
              top: BorderSide(color: Color(0xFFE23D3D), width: 2),
              bottom: BorderSide(color: Color(0xFFE23D3D), width: 2),
            ),
          ),
        ),
      ),
  ];
}

void main() {
  void useViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  testWidgets('1.1.0 — atLevel markers, biome-tinted scenery, extra bookmark',
      (tester) async {
    useViewport(tester, const Size(360, 640));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MapChunkWidget(
              // chunkContext omitted on purpose: 1.1.0 derives it, which is the
              // backward-compatible path a pre-1.1.0 host still takes.
              levels: _levels,
              chunkIndex: 0,
              chunkExtent: 720,
              chunkSpanNormalized: 1.0,
              lateralBounds: _config.lateralBounds,
              pathCurvature: 0.85,
              pathProgressPosition: 1.0,
              // A real background layer, so the chunk painter does not fill
              // over the decorations — it paints the base itself only when the
              // background config is `none`.
              backgroundConfig: const SagaMapBackgroundConfig.color(
                color: Color(0xFF2D5A27),
              ),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              responsiveResolver: const SagaResponsiveResolver(
                config: SagaMapResponsiveConfig.defaults,
              ),
              progressResolver: _progressFor,
              chunkDecorationBuilder: _decorations,
              nodeBuilder: _node,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/features_1_1_0_decorations.png'),
    );
  });

  testWidgets('1.1.0 — episode header reads stars from the chunk context',
      (tester) async {
    useViewport(tester, const Size(360, 640));

    final controller = SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 2,
      // Positions are global along the path axis, so each chunk's copy is
      // pushed forward by that chunk's span.
      chunkLoader: (chunkIndex, sectionsPerChunk) => [
        for (final level in _levels)
          LevelData(
            id: chunkIndex * sectionsPerChunk + level.id,
            position: SagaPoint(
              level.position.x,
              level.position.y + chunkIndex,
            ),
            biomeId: level.biomeId,
          ),
      ],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: controller,
            chunkExtent: 720,
            chunkSpanNormalized: 1.0,
            lateralBounds: _config.lateralBounds,
            pathCurvature: 0.85,
            backgroundConfig: const SagaMapBackgroundConfig.color(
              color: Color(0xFF2D5A27),
            ),
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            responsiveResolver: const SagaResponsiveResolver(
              config: SagaMapResponsiveConfig.defaults,
            ),
            progressResolver: _progressFor,
            chunkDecorationBuilder: _decorations,
            // 1.1.0: the header builder is handed the chunk context, so it can
            // report stars earned across that chunk with starsInRange.
            chunkEpisodeHeaderBuilder: (context, chunk) {
              final earned = _progress.starsInRange(
                chunk.chunkIndex * _levelsPerChunk,
                _levelsPerChunk,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xCC1B3A17),
                      border:
                          Border.all(color: const Color(0xFF7BC96F), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Chunk index as blocks, stars earned as pips.
                        for (var i = 0; i <= chunk.chunkIndex; i++)
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 6),
                            color: const Color(0xFF7BC96F),
                          ),
                        const SizedBox(width: 6),
                        for (var i = 0; i < earned; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFC107),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
            nodeBuilder: _node,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/features_1_1_0_episode_header.png'),
    );
  });
}
