import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Pinch zoom has to coexist with the map's own scrolling. The risk is the
/// gesture arena: a scale recognizer that claims a one-finger drag would stop
/// the map scrolling entirely.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _chunkExtent = 600.0;

SagaInfiniteMapController _controller() {
  const generator = SagaMapLevelGenerator();
  return SagaInfiniteMapController(
    sectionsPerChunk: _levelsPerChunk,
    initialChunkCount: 4,
    chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
      globalSeed: 3,
      config: _config,
      startLevelId: chunkIndex * sectionsPerChunk,
      count: sectionsPerChunk,
    ),
  );
}

void main() {
  late SagaInfiniteMapController controller;
  final zoomLog = <double>[];
  final tapped = <int>[];

  setUp(() {
    controller = _controller();
    zoomLog.clear();
    tapped.clear();
  });

  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    SagaMapZoomConfig? zoomConfig = const SagaMapZoomConfig(),
    SagaMapPathAxis pathAxis = SagaMapPathAxis.vertical,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: controller,
            chunkExtent: _chunkExtent,
            chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
            lateralBounds: _config.lateralBounds,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            responsiveResolver: SagaResponsiveResolver(
              config: SagaMapResponsiveConfig.defaults.copyWith(
                pathAxis: pathAxis,
                nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
                scrollSensitivityPolicy: const SagaMapValuePolicy.all(1.0),
              ),
            ),
            zoomConfig: zoomConfig,
            onZoomChanged: zoomLog.add,
            onLevelTap: (level) => tapped.add(level.id),
            nodeBuilder: (context, level, layout) =>
                SizedBox.expand(key: ValueKey('node-${level.id}')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double scrollOffset(WidgetTester tester) =>
      tester.widget<Scrollable>(find.byType(Scrollable)).controller!.offset;

  /// Drives a two-finger pinch outwards from [centre] by [spread] pixels.
  Future<void> pinch(
    WidgetTester tester,
    Offset centre, {
    required double from,
    required double to,
  }) async {
    final first = await tester.startGesture(centre - Offset(from, 0));
    final second = await tester.startGesture(centre + Offset(from, 0));
    await tester.pump();
    await first.moveTo(centre - Offset(to, 0));
    await second.moveTo(centre + Offset(to, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  }

  testWidgets('one finger still scrolls while zoom is enabled', (tester) async {
    await pump(tester);
    expect(scrollOffset(tester), 0);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // The whole point of holding the pinch recognizer out of the arena.
    expect(scrollOffset(tester), greaterThan(100));
    expect(zoomLog, isEmpty);
  });

  testWidgets('two fingers zoom in', (tester) async {
    await pump(tester);

    await pinch(tester, const Offset(200, 400), from: 50, to: 100);

    expect(zoomLog, isNotEmpty);
    expect(zoomLog.last, greaterThan(1.0));
  });

  testWidgets('two fingers zoom out', (tester) async {
    await pump(tester);

    await pinch(tester, const Offset(200, 400), from: 120, to: 40);

    expect(zoomLog, isNotEmpty);
    expect(zoomLog.last, lessThan(1.0));
  });

  testWidgets('zoom is clamped to the configured bounds', (tester) async {
    await pump(tester, zoomConfig: const SagaMapZoomConfig(min: 0.8, max: 1.4));

    await pinch(tester, const Offset(200, 400), from: 20, to: 190);
    expect(zoomLog.last, lessThanOrEqualTo(1.4));

    zoomLog.clear();
    await pinch(tester, const Offset(200, 400), from: 190, to: 5);
    expect(zoomLog.last, greaterThanOrEqualTo(0.8));
  });

  testWidgets('zooming in spreads the nodes apart', (tester) async {
    await pump(tester);

    double gap() {
      final first = tester.getCenter(find.byKey(const ValueKey('node-0')));
      final second = tester.getCenter(find.byKey(const ValueKey('node-1')));
      return (second.dy - first.dy).abs();
    }

    final before = gap();
    await pinch(tester, const Offset(200, 400), from: 50, to: 110);
    final after = gap();

    expect(after, greaterThan(before * 1.1));
  });

  testWidgets('zooming in enlarges the nodes', (tester) async {
    await pump(tester);

    double nodeWidth() =>
        tester.getSize(find.byKey(const ValueKey('node-0'))).width;

    final before = nodeWidth();
    await pinch(tester, const Offset(200, 400), from: 50, to: 110);

    // Layout-level zoom: the node genuinely grows rather than being magnified.
    expect(nodeWidth(), greaterThan(before * 1.1));
  });

  testWidgets('content under the fingers stays put', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    const focal = Offset(200, 300);
    final anchor = find.byKey(const ValueKey('node-8'));
    final before = tester.getCenter(anchor).dy;

    await pinch(tester, focal, from: 60, to: 90);

    // The focal correction cannot be perfect while the scroll extent is still
    // catching up, but the anchor must not fly off screen.
    expect((tester.getCenter(anchor).dy - before).abs(), lessThan(120));
  });

  testWidgets('nodes remain tappable after zooming', (tester) async {
    await pump(tester);
    await pinch(tester, const Offset(200, 400), from: 50, to: 100);

    // Zoom moves the scroll offset, so pick whichever node is on screen now
    // rather than assuming a particular one survived the gesture.
    const viewport = Rect.fromLTWH(0, 0, 400, 800);
    int? visibleId;
    for (var id = 0; id < 40 && visibleId == null; id++) {
      final finder = find.byKey(ValueKey('node-$id'));
      if (finder.evaluate().isEmpty) continue;
      final centre = tester.getCenter(finder);
      if (viewport.deflate(40).contains(centre)) visibleId = id;
    }
    expect(visibleId, isNotNull, reason: 'no node on screen after zooming');

    // The node visual is a bare SizedBox and takes no part in hit testing; the
    // gesture area wrapped around it is what receives the tap.
    await tester.tap(
      find.byKey(ValueKey('node-$visibleId')),
      warnIfMissed: false,
    );
    await tester.pump();

    // Layout zoom means hit testing needs no inverse transform to stay honest.
    expect(tapped, contains(visibleId));
  });

  testWidgets('no zoom config leaves gestures untouched', (tester) async {
    await pump(tester, zoomConfig: null);

    expect(find.byType(SagaInfiniteMapView), findsOneWidget);

    await pinch(tester, const Offset(200, 400), from: 50, to: 120);
    expect(zoomLog, isEmpty);
  });

  testWidgets('a horizontal map zooms too', (tester) async {
    await pump(tester, pathAxis: SagaMapPathAxis.horizontal);

    await pinch(tester, const Offset(200, 400), from: 50, to: 110);

    expect(zoomLog, isNotEmpty);
    expect(zoomLog.last, greaterThan(1.0));
  });

  testWidgets('scrolling still works after a zoom', (tester) async {
    await pump(tester);
    await pinch(tester, const Offset(200, 400), from: 50, to: 100);

    final before = scrollOffset(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(scrollOffset(tester), greaterThan(before));
  });

  group('SagaMapZoomConfig', () {
    test('clamps into its range', () {
      const config = SagaMapZoomConfig(min: 0.5, max: 2);
      expect(config.clamp(0.1), 0.5);
      expect(config.clamp(9), 2);
      expect(config.clamp(1.25), 1.25);
    });

    test('compares by value', () {
      expect(const SagaMapZoomConfig(), const SagaMapZoomConfig());
      expect(
        const SagaMapZoomConfig(max: 3).hashCode,
        const SagaMapZoomConfig(max: 3).hashCode,
      );
      expect(
        const SagaMapZoomConfig(max: 3),
        isNot(const SagaMapZoomConfig(max: 4)),
      );
    });

    test('starts at the configured initial zoom', () {
      const config = SagaMapZoomConfig(min: 0.5, max: 3, initial: 2);
      expect(config.initial, 2);
      expect(config.clamp(config.initial), 2);
    });
  });
}
