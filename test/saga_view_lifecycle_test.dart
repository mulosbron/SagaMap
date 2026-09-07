import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// T-16: four defects that all need a *change* mid-test rather than a static
/// build — a swapped controller, a header, the tail of the map.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _chunkExtent = 600.0;
const _generator = SagaMapLevelGenerator();

SagaInfiniteMapController _mapController({int seed = 5, int chunks = 3}) {
  return SagaInfiniteMapController(
    sectionsPerChunk: _levelsPerChunk,
    initialChunkCount: chunks,
    chunkLoader: (chunkIndex, sectionsPerChunk) => _generator.generateLevels(
      globalSeed: seed,
      config: _config,
      startLevelId: chunkIndex * sectionsPerChunk,
      count: sectionsPerChunk,
    ),
  );
}

void main() {
  double offsetOf(WidgetTester tester) =>
      tester.widget<Scrollable>(find.byType(Scrollable)).controller!.offset;

  Widget buildView({
    required SagaInfiniteMapController controller,
    SagaMapCameraController? camera,
    double headerExtent = 0,
    bool withHeaders = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SagaInfiniteMapView(
          controller: controller,
          cameraController: camera,
          chunkExtent: _chunkExtent,
          chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
          lateralBounds: _config.lateralBounds,
          biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
          responsiveResolver: SagaResponsiveResolver(
            config: SagaMapResponsiveConfig.defaults.copyWith(
              nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
            ),
          ),
          episodeHeaderExtent: headerExtent,
          chunkEpisodeHeaderBuilder: withHeaders
              ? (context, chunk) => SizedBox(
                    height: headerExtent,
                    child: Text('Episode ${chunk.chunkIndex}'),
                  )
              : null,
          nodeBuilder: (context, level, layout) =>
              SizedBox.expand(key: ValueKey('node-${level.id}')),
        ),
      ),
    );
  }

  testWidgets('a swapped camera controller is attached, not ignored',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final first = SagaMapCameraController();
    final second = SagaMapCameraController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final controller = _mapController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildView(controller: controller, camera: first));
    await tester.pumpAndSettle();
    expect(first.isAttached, isTrue);

    await tester.pumpWidget(buildView(controller: controller, camera: second));
    await tester.pumpAndSettle();

    // The old handle stops working and the new one starts: a camera that
    // reports success by returning is the worst kind of no-op.
    expect(first.isAttached, isFalse);
    expect(second.isAttached, isTrue);

    await second.scrollToPathPosition(20, duration: Duration.zero);
    await tester.pumpAndSettle();
    expect(offsetOf(tester), greaterThan(0));
  });

  testWidgets('headers are counted in every scroll target', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    const headerExtent = 80.0;
    final camera = SagaMapCameraController();
    addTearDown(camera.dispose);
    final controller = _mapController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildView(
      controller: controller,
      camera: camera,
      headerExtent: headerExtent,
      withHeaders: true,
    ));
    await tester.pumpAndSettle();

    // Asserted against where node 20 actually lands, not against the formula:
    // the point is that the camera and the layout agree. Without counting the
    // headers the camera stops short by one header per chunk.
    await camera.scrollToPathPosition(20,
        alignment: 0, duration: Duration.zero);
    await tester.pumpAndSettle();

    final withHeaders =
        tester.getTopLeft(find.byKey(const ValueKey('node-20')));

    // The same map with no headers at all: node 20 lands in the same place
    // relative to the viewport, which is the whole claim.
    final bare = _mapController();
    addTearDown(bare.dispose);
    final bareCamera = SagaMapCameraController();
    addTearDown(bareCamera.dispose);

    await tester.pumpWidget(buildView(controller: bare, camera: bareCamera));
    await tester.pumpAndSettle();
    await bareCamera.scrollToPathPosition(20,
        alignment: 0, duration: Duration.zero);
    await tester.pumpAndSettle();

    final without = tester.getTopLeft(find.byKey(const ValueKey('node-20')));

    // A-05.01: the tolerance used to be exactly `headerExtent`, which is
    // exactly the error the defect produced — the test could not fail. One
    // pixel is the real claim: the camera lands node 20 in the same place
    // whether or not the map has headers.
    expect(withHeaders.dy, closeTo(without.dy, 1.0));
  });

  testWidgets('a controller swap does not render the previous world',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final first = _mapController(seed: 5);
    final second = _mapController(seed: 777);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(buildView(controller: first));
    await tester.pumpAndSettle();

    SagaChunkContext? contextOf(WidgetTester t) => t
        .widgetList<MapChunkWidget>(find.byType(MapChunkWidget))
        .first
        .chunkContext;

    final before = contextOf(tester)!.levels.map((l) => l.position).toList();

    await tester.pumpWidget(buildView(controller: second));
    await tester.pumpAndSettle();

    final after = contextOf(tester)!.levels.map((l) => l.position).toList();

    // The cache is keyed by chunk index alone, so a new seed at the same index
    // would otherwise keep painting the old world's node positions.
    expect(after, isNot(equals(before)));
    expect(after, equals(second.chunkLevels(0).map((l) => l.position)));
  });

  test('the last level of the last chunk still has a pose', () {
    // The final point has no segment leaving it, so the character used to
    // vanish standing exactly on it — while ownsPathPosition still claimed the
    // position, so no other chunk drew it either.
    final levels = _generator.generateLevels(
      globalSeed: 5,
      config: _config,
      startLevelId: 0,
      count: _levelsPerChunk,
    );
    final context = SagaMapRenderContext(
      levels: levels,
      chunkIndex: 0,
      chunkSize: const SagaSize(width: 400, height: _chunkExtent),
      chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
      layout: const SagaResponsiveResolver().resolveForWidth(400),
    );

    final lastId = levels.last.id.toDouble();
    expect(context.ownsPathPosition(lastId), isTrue);
    expect(context.poseAtPathPosition(lastId), isNotNull);
    expect(context.characterPixel(lastId), isNotNull);

    // And one level short of it, which always worked, still does.
    expect(context.poseAtPathPosition(lastId - 1), isNotNull);
  });
}
