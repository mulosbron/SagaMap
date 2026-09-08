@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Visual record of what 2.0.0 changed on the rendered map.
///
/// Three of the six breaking changes are visible, and these pin them:
///
/// - **Host-defined biome ids.** The generator cycles `SagaMapConfig.biomeIds`,
///   so a chunk can carry a realm the package has never heard of.
/// - **`SagaBiomeTheme.ambientTint`.** A wash the chunk painter lays over the
///   background and the path, under the node widgets.
/// - **Gates that block progression.** A node past a closed gate is drawn as
///   unreachable, whatever its recorded progress says.
///
/// The other three — injectable rewards, `saveGlobalSeed` and the dropped
/// `flutter_svg` — have no pixels of their own and are covered by
/// `saga_2_0_0_upgrade_test.dart`.
///
/// Drawn from plain shapes rather than icons or glyphs: a golden must not
/// depend on a font being available to the test renderer.
///
/// Regenerate after an intentional visual change:
///
/// ```bash
/// flutter test --update-goldens test/golden
/// ```
const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 5;

/// The demo's own realms, none of which the package ships a theme for.
const _realms = <String>['sunspire', 'drownlands', 'ashreach'];

/// Where the gate sits, on the same zero-based scale as [LevelData.id]:
/// level 3 and everything after it is behind it.
const int _gateLevel = 3;

/// Hand-authored so these goldens track rendering, not the generator. The
/// biome ids are host-defined, which is the point of the first golden.
const _levels = <LevelData>[
  LevelData(id: 0, position: SagaPoint(0.28, 0.02), biomeId: 'sunspire'),
  LevelData(id: 1, position: SagaPoint(0.72, 0.22), biomeId: 'sunspire'),
  LevelData(id: 2, position: SagaPoint(0.28, 0.42), biomeId: 'drownlands'),
  LevelData(id: 3, position: SagaPoint(0.72, 0.62), biomeId: 'drownlands'),
  LevelData(id: 4, position: SagaPoint(0.28, 0.82), biomeId: 'ashreach'),
];

final _progress = SagaProgress(
  currentMaxUnlockedLevelId: 4,
  levels: {
    0: const LevelProgress(
      levelId: 0,
      state: LevelCompletionState.completed,
      stars: 3,
    ),
    1: const LevelProgress(
      levelId: 1,
      state: LevelCompletionState.completed,
      stars: 2,
    ),
    2: const LevelProgress(levelId: 2, state: LevelCompletionState.unlocked),
    // Recorded as unlocked, but the gate below makes it unreachable — which is
    // exactly the state 1.x could not express.
    3: const LevelProgress(levelId: 3, state: LevelCompletionState.unlocked),
    4: const LevelProgress(levelId: 4, state: LevelCompletionState.unlocked),
  },
);

LevelProgress? _progressFor(LevelData level) => _progress.levels[level.id];

/// A resolver for host-defined ids, which is what ADR-0007 expects a host with
/// its own realms to write instead of living with the built-in fallback.
///
/// Every realm sets an [SagaBiomeTheme.ambientTint], so the second golden can
/// show the same chunk with and without one.
class _RealmThemeResolver implements SagaBiomeThemeResolver {
  const _RealmThemeResolver({this.withTint = true});

  /// Turns the wash off, so the pair of goldens differs in one variable.
  final bool withTint;

  /// The washes are deliberately heavy. A shipping game would use something
  /// far subtler, but a golden pair has to differ by more than a few levels of
  /// alpha to be worth keeping.
  static const Map<String, (Color, Color, Color)> _palette = {
    // id: (background, path, ambient wash)
    'sunspire': (Color(0xFF7A3E12), Color(0xFFFFB74D), Color(0x66FF7043)),
    'drownlands': (Color(0xFF14323F), Color(0xFF5FC7D6), Color(0x6600ACC1)),
    'ashreach': (Color(0xFF3A2F35), Color(0xFFBFA8B4), Color(0x66120C18)),
  };

  @override
  SagaBiomeTheme resolve(String biomeId) {
    final (background, path, tint) = _palette[biomeId] ?? _palette['sunspire']!;

    return SagaBiomeTheme(
      backgroundColor: background,
      pathFillColor: path,
      pathBorderColor: const Color(0xFF23180C),
      upcomingPathFillColor: const Color(0xFF6E7A6B),
      upcomingPathBorderColor: const Color(0xFF3B443A),
      shadowColor: const Color(0x40000000),
      pathBorderWidth: 10,
      pathInnerStrokeWidth: 6,
      ambientTint: withTint ? tint : null,

      // Opaque art keys the package carries and never reads. `_node` reads the
      // emblem back, which is the round trip this field exists for.
      assets: {'emblem': biomeId.substring(0, 1).toUpperCase()},
    );
  }
}

/// The single gate condition, the way ADR-0005 asks for it: one predicate, and
/// every consumer derived from it.
bool _gateOpen(int levelId) => levelId < _gateLevel;

/// A node drawn from shapes: fill by state, star pips along the bottom, and a
/// bar across it when a closed gate makes it unreachable.
///
/// The emblem block in the corner is read out of
/// [SagaBiomeTheme.assets] — proof the package carried a host-owned key from
/// the config, through generation, to the builder, without reading it.
Widget _node(BuildContext context, LevelData level, ResolvedSagaLayout layout) {
  final progress = _progressFor(level);
  final state = progress?.state ?? LevelCompletionState.locked;
  final stars = progress?.stars ?? 0;
  final reachable = _gateOpen(level.id);
  final theme = const _RealmThemeResolver().resolve(level.biomeId);
  final hasEmblem = theme.assets.containsKey('emblem');

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
      // A reachable node keeps its state colour; a gated one is greyed out
      // whatever its progress says.
      color: reachable ? fill : const Color(0xFF5A5A5A),
      shape: BoxShape.circle,
      border: Border.all(
        color: reachable ? const Color(0xFF23331F) : const Color(0xFF2A2A2A),
        width: 2,
      ),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
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
        // The biome's emblem, straight out of the opaque asset map.
        if (hasEmblem)
          Align(
            alignment: const Alignment(-0.62, -0.62),
            child: SizedBox(
              width: 7,
              height: 7,
              child: ColoredBox(color: theme.pathFillColor),
            ),
          ),
        // A closed gate: a bar across the node, so "unreachable" is legible
        // without reading the colour.
        if (!reachable)
          const SizedBox(
            width: 26,
            height: 5,
            child: ColoredBox(color: Color(0xFFE23D3D)),
          ),
      ],
    ),
  );
}

void main() {
  void useViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  /// Builds one chunk with no background config, so the chunk painter fills
  /// the biome's own background — which is what the ambient tint then washes
  /// over. That choice also rules out a decoration marking the gate: with no
  /// background config the painter fills the base itself, and the painter sits
  /// above the decoration layer. The gate is drawn on the nodes instead.
  Widget buildChunk({required SagaBiomeThemeResolver resolver}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MapChunkWidget(
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 720,
            chunkSpanNormalized: 1.0,
            lateralBounds: _config.lateralBounds,
            pathCurvature: 0.85,
            pathProgressPosition: 2.0,
            // The chunk painter fills the base itself only when the background
            // config is `none`, which is what lets the ambient tint sit over a
            // painted background rather than over a host widget.
            backgroundConfig: const SagaMapBackgroundConfig.none(),
            biomeThemeResolver: resolver,
            responsiveResolver: const SagaResponsiveResolver(
              config: SagaMapResponsiveConfig.defaults,
            ),
            progressResolver: _progressFor,
            interactionPolicy: SagaNodeInteractionPolicy(
              // 2.0.0: the same predicate that greys the node also stops the
              // tap, the Tab stop and the screen-reader announcement.
              isReachable: (level, progress) => _gateOpen(level.id),
            ),
            nodeBuilder: _node,
          ),
        ),
      ),
    );
  }

  testWidgets('2.0.0 — host realms, ambient tint and a closed gate',
      (tester) async {
    useViewport(tester, const Size(360, 640));

    await tester.pumpWidget(
      buildChunk(resolver: const _RealmThemeResolver()),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/features_2_0_0_realms_gate.png'),
    );
  });

  testWidgets('2.0.0 — the same chunk with the ambient tint turned off',
      (tester) async {
    useViewport(tester, const Size(360, 640));

    // The pair differs in one variable, so the wash is what the diff shows.
    await tester.pumpWidget(
      buildChunk(resolver: const _RealmThemeResolver(withTint: false)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/features_2_0_0_no_ambient_tint.png'),
    );
  });

  testWidgets('2.0.0 — a ten-realm cycle across three chunks', (tester) async {
    useViewport(tester, const Size(360, 640));

    // `biomeSpan: 5` against three realms closes the cycle in 15 levels, so a
    // scrolling map shows every realm rather than one flat colour.
    final config = _config.copyWith(biomeSpan: 5, biomeIds: _realms);
    const generator = SagaMapLevelGenerator();

    final controller = SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 3,
      chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
        globalSeed: 42,
        config: config,
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
            chunkExtent: 240,
            chunkSpanNormalized: config.spanForLevelCount(_levelsPerChunk),
            lateralBounds: config.lateralBounds,
            pathCurvature: 0.85,
            backgroundConfig: const SagaMapBackgroundConfig.none(),
            biomeThemeResolver: const _RealmThemeResolver(),
            responsiveResolver: const SagaResponsiveResolver(
              config: SagaMapResponsiveConfig.defaults,
            ),
            nodeBuilder: (context, level, layout) => DecoratedBox(
              decoration: BoxDecoration(
                color: const _RealmThemeResolver()
                    .resolve(level.biomeId)
                    .pathFillColor,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF23331F), width: 2),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/features_2_0_0_realm_cycle.png'),
    );
  });
}
