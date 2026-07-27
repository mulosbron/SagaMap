import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Every policy on [SagaMapResponsiveConfig] must observably change rendering.
/// A knob a host can set with no effect is worse than no knob at all, so each
/// one is pinned here.

const _levels = <LevelData>[
  LevelData(id: 1, position: SagaPoint(0.5, 0.0), biomeId: kBiomeIdForest),
  LevelData(id: 2, position: SagaPoint(0.5, 0.5), biomeId: kBiomeIdForest),
];

SagaResponsiveResolver _resolver({
  SagaMapPathAxis pathAxis = SagaMapPathAxis.vertical,
  double nodeSize = 1.0,
  double nodeSpacing = 1.0,
  double zoom = 1.0,
  double interactionRadius = 1.0,
  double cameraPadding = 0.0,
}) {
  return SagaResponsiveResolver(
    config: SagaMapResponsiveConfig.defaults.copyWith(
      pathAxis: pathAxis,
      nodeSizePolicy: SagaMapValuePolicy.all(nodeSize),
      nodeSpacingPolicy: SagaMapValuePolicy.all(nodeSpacing),
      zoomPolicy: SagaMapValuePolicy.all(zoom),
      interactionRadiusPolicy: SagaMapValuePolicy.all(interactionRadius),
      cameraPaddingPolicy: SagaMapValuePolicy.all(cameraPadding),
      maxLateralExtentPolicy: null,
    ),
  );
}

void main() {
  void useViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpMap(
    WidgetTester tester, {
    required SagaResponsiveResolver resolver,
    List<LevelData> levels = _levels,
    ValueChanged<LevelData>? onLevelTap,
    double chunkExtent = 600,
  }) async {
    final pathAxis = resolver.config.pathAxis;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: pathAxis == SagaMapPathAxis.horizontal
                ? Axis.horizontal
                : Axis.vertical,
            child: MapChunkWidget(
              levels: levels,
              chunkIndex: 0,
              chunkExtent: chunkExtent,
              chunkSpanNormalized: 1.0,
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              responsiveResolver: resolver,
              onLevelTap: onLevelTap,
              nodeBuilder: (context, level, layout) =>
                  SizedBox.expand(key: ValueKey('node-${level.id}')),
            ),
          ),
        ),
      ),
    );
  }

  Size nodeSizeOf(WidgetTester tester, int id) =>
      tester.getSize(find.byKey(ValueKey('node-$id')));

  Offset nodeCenterOf(WidgetTester tester, int id) =>
      tester.getCenter(find.byKey(ValueKey('node-$id')));

  group('nodeSize', () {
    testWidgets('scales the node below the touch minimum', (tester) async {
      useViewport(tester, const Size(400, 800));
      await pumpMap(tester, resolver: _resolver(nodeSize: 0.5));

      // 44 * 0.5 = 22. The previous implementation clamped visual size up to
      // the 44dp touch minimum, silently discarding every shrinking policy.
      expect(nodeSizeOf(tester, 1).width, moreOrLessEquals(22, epsilon: 0.01));
    });

    testWidgets('scales the node up', (tester) async {
      useViewport(tester, const Size(400, 800));
      await pumpMap(tester, resolver: _resolver(nodeSize: 1.5));

      expect(nodeSizeOf(tester, 1).width, moreOrLessEquals(66, epsilon: 0.01));
    });
  });

  testWidgets('zoom scales node size on top of nodeSize', (tester) async {
    useViewport(tester, const Size(400, 800));
    await pumpMap(tester, resolver: _resolver(nodeSize: 1.0, zoom: 2.0));

    expect(nodeSizeOf(tester, 1).width, moreOrLessEquals(88, epsilon: 0.01));
  });

  testWidgets('nodeSpacing widens the gap between nodes', (tester) async {
    useViewport(tester, const Size(400, 800));

    await pumpMap(tester, resolver: _resolver(nodeSpacing: 1.0));
    final tight = nodeCenterOf(tester, 2).dy - nodeCenterOf(tester, 1).dy;

    await pumpMap(tester, resolver: _resolver(nodeSpacing: 1.5));
    final loose = nodeCenterOf(tester, 2).dy - nodeCenterOf(tester, 1).dy;

    expect(loose, moreOrLessEquals(tight * 1.5, epsilon: 0.5));
  });

  testWidgets('cameraPadding keeps an edge node off the lateral edge',
      (tester) async {
    useViewport(tester, const Size(400, 800));
    const edgeLevel = <LevelData>[
      LevelData(id: 1, position: SagaPoint(0.0, 0.0), biomeId: kBiomeIdForest),
    ];

    await pumpMap(
      tester,
      resolver: _resolver(cameraPadding: 0),
      levels: edgeLevel,
    );
    expect(nodeCenterOf(tester, 1).dx, moreOrLessEquals(0, epsilon: 0.5));

    await pumpMap(
      tester,
      resolver: _resolver(cameraPadding: 30),
      levels: edgeLevel,
    );
    expect(nodeCenterOf(tester, 1).dx, moreOrLessEquals(30, epsilon: 0.5));
  });

  group('interactionRadius', () {
    testWidgets('a tap outside the visual still hits the node',
        (tester) async {
      useViewport(tester, const Size(400, 800));
      final tapped = <int>[];

      // Visual is 22px wide, so 11px from center. The touch target floors at
      // 44dp, giving 22px of reach.
      await pumpMap(
        tester,
        resolver: _resolver(nodeSize: 0.5),
        onLevelTap: (level) => tapped.add(level.id),
      );

      final center = nodeCenterOf(tester, 1);
      await tester.tapAt(center + const Offset(18, 0));
      await tester.pump();

      expect(tapped, [1]);
    });

    testWidgets('grows the touch target beyond the accessibility floor',
        (tester) async {
      useViewport(tester, const Size(400, 800));
      final tapped = <int>[];

      // 44 * 1.0 visual, radius 2.0 -> 88px target, 44px of reach.
      await pumpMap(
        tester,
        resolver: _resolver(interactionRadius: 2.0),
        onLevelTap: (level) => tapped.add(level.id),
      );

      final center = nodeCenterOf(tester, 1);
      await tester.tapAt(center + const Offset(40, 0));
      await tester.pump();

      expect(tapped, [1]);
    });
  });

  testWidgets('scrollSensitivity reaches the scroll view as physics',
      (tester) async {
    useViewport(tester, const Size(400, 800));
    const generator = SagaMapLevelGenerator();
    final controller = SagaInfiniteMapController(
      sectionsPerChunk: 10,
      chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
        globalSeed: 1,
        config: SagaMapConfig.defaultConfig,
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
            chunkExtent: 900,
            chunkSpanNormalized:
                SagaMapConfig.defaultConfig.spanForLevelCount(10),
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            responsiveResolver: SagaResponsiveResolver(
              config: SagaMapResponsiveConfig.defaults.copyWith(
                scrollSensitivityPolicy: const SagaMapValuePolicy.all(2.0),
              ),
            ),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<SagaMapScrollPhysics>());
    expect((listView.physics! as SagaMapScrollPhysics).sensitivity, 2.0);
  });

  testWidgets('a neutral scrollSensitivity leaves platform physics alone',
      (tester) async {
    useViewport(tester, const Size(400, 800));
    final controller = SagaInfiniteMapController(
      sectionsPerChunk: 10,
      chunkLoader: (_, __) => const <LevelData>[],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: controller,
            chunkExtent: 900,
            chunkSpanNormalized:
                SagaMapConfig.defaultConfig.spanForLevelCount(10),
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            responsiveResolver: SagaResponsiveResolver(
              config: SagaMapResponsiveConfig.defaults.copyWith(
                scrollSensitivityPolicy: const SagaMapValuePolicy.all(1.0),
              ),
            ),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<ListView>(find.byType(ListView)).physics, isNull);
  });
}
