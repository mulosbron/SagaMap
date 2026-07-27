import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Episode headers between chunks, and a parallax layer that lags the scroll.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _generator = SagaMapLevelGenerator();

SagaInfiniteMapController _mapController() => SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 4,
      chunkLoader: (chunkIndex, sectionsPerChunk) =>
          _generator.generateLevels(
        globalSeed: 5,
        config: _config,
        startLevelId: chunkIndex * sectionsPerChunk,
        count: sectionsPerChunk,
      ),
    );

void main() {
  Future<SagaInfiniteMapController> pump(
    WidgetTester tester, {
    Widget? Function(BuildContext, int)? episodeHeaderBuilder,
    Widget? parallaxBackground,
    double parallaxFactor = 0.4,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final controller = _mapController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: controller,
            chunkExtent: 500,
            chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
            lateralBounds: _config.lateralBounds,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            episodeHeaderBuilder: episodeHeaderBuilder,
            parallaxBackground: parallaxBackground,
            parallaxFactor: parallaxFactor,
            nodeBuilder: (context, level, layout) =>
                SizedBox.expand(key: ValueKey('node-${level.id}')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  group('episode headers', () {
    testWidgets('a header shows before the chunk it belongs to',
        (tester) async {
      await pump(
        tester,
        episodeHeaderBuilder: (context, index) => index == 0
            ? const SizedBox(height: 40, child: Text('World 1'))
            : null,
      );
      expect(find.text('World 1'), findsOneWidget);
    });

    testWidgets('a null header leaves the chunk bare', (tester) async {
      await pump(tester, episodeHeaderBuilder: (context, index) => null);
      expect(find.byType(Column), findsNothing);
    });

    testWidgets('headers appear for the chunks that want them',
        (tester) async {
      await pump(
        tester,
        episodeHeaderBuilder: (context, index) => index.isEven
            ? SizedBox(height: 30, child: Text('Episode $index'))
            : null,
      );
      expect(find.text('Episode 0'), findsOneWidget);
      // Odd chunks get no banner.
      expect(find.text('Episode 1'), findsNothing);
    });

    testWidgets('the header pushes the first node down', (tester) async {
      await pump(tester);
      final withoutHeader =
          tester.getTopLeft(find.byKey(const ValueKey('node-0'))).dy;

      await pump(
        tester,
        episodeHeaderBuilder: (context, index) =>
            index == 0 ? const SizedBox(height: 60) : null,
      );
      final withHeader =
          tester.getTopLeft(find.byKey(const ValueKey('node-0'))).dy;

      expect(withHeader, greaterThan(withoutHeader));
    });
  });

  group('parallax', () {
    final parallaxLayer = find.byKey(const ValueKey('saga-parallax'));

    testWidgets('no parallax layer means no extra stack', (tester) async {
      await pump(tester);
      expect(parallaxLayer, findsNothing);
    });

    testWidgets('the layer is present behind the map', (tester) async {
      await pump(
        tester,
        parallaxBackground: const ColoredBox(
          color: Color(0xFF102030),
          child: SizedBox.expand(),
        ),
      );
      expect(parallaxLayer, findsOneWidget);
    });

    testWidgets('the layer lags the scroll', (tester) async {
      await pump(
        tester,
        parallaxFactor: 0.4,
        parallaxBackground: const ColoredBox(
          color: Color(0xFF102030),
          child: SizedBox.expand(),
        ),
      );

      Offset shift() => tester
          .widget<Transform>(find.byKey(const ValueKey('saga-parallax')))
          .transform
          .getTranslation()
          .let((t) => Offset(t.x, t.y));

      expect(shift(), Offset.zero);

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Moved, but less than the 300 the map moved — 0.4 of it.
      final moved = shift().dy.abs();
      expect(moved, greaterThan(0));
      expect(moved, lessThan(300));
      expect(moved, moreOrLessEquals(300 * 0.4, epsilon: 20));
    });

    testWidgets('the layer takes no pointer', (tester) async {
      await pump(
        tester,
        parallaxBackground: const ColoredBox(
          color: Color(0xFF102030),
          child: SizedBox.expand(),
        ),
      );
      // The map underneath still scrolls, so the layer is not eating drags.
      final scrollable =
          tester.widget<Scrollable>(find.byType(Scrollable)).controller!;
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scrollable.offset, greaterThan(0));
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
