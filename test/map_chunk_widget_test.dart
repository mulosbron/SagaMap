import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Resolver locked to [pathAxis] with spacing neutralised.
///
/// `nodeSpacing` scales the path axis per breakpoint, which would otherwise mix
/// into every along-axis measurement here. These tests are about the lateral
/// cap and orientation; spacing has its own tests.
SagaResponsiveResolver _resolverFor(SagaMapPathAxis pathAxis) {
  return SagaResponsiveResolver(
    config: SagaMapResponsiveConfig.defaults.copyWith(
      pathAxis: pathAxis,
      nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
    ),
  );
}

/// Node visual that fills its slot, so `getCenter` reports the node's own
/// center rather than the intrinsic size of some child.
Widget _slotNode(BuildContext context, LevelData level, ResolvedSagaLayout _) {
  return SizedBox.expand(key: ValueKey('node-${level.id}'));
}

Offset _nodeCenter(WidgetTester tester, int levelId) {
  return tester.getCenter(find.byKey(ValueKey('node-$levelId')));
}

void main() {
  /// Pins the logical viewport for a test, restoring it afterwards.
  void useViewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Widget host({
    required Widget child,
    required SagaMapPathAxis pathAxis,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          scrollDirection: pathAxis == SagaMapPathAxis.horizontal
              ? Axis.horizontal
              : Axis.vertical,
          child: child,
        ),
      ),
    );
  }

  testWidgets('renders a node per level', (tester) async {
    final levels = <LevelData>[
      const LevelData(
          id: 1, position: SagaPoint(0.2, 0.1), biomeId: kBiomeIdForest),
      const LevelData(
          id: 2, position: SagaPoint(0.5, 0.2), biomeId: kBiomeIdDesert),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
            levels: levels,
            chunkIndex: 0,
            chunkExtent: 600,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            nodeBuilder: (context, level, layout) => Text('Level ${level.id}'),
          ),
        ),
      ),
    );

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
  });

  testWidgets('breakpoint follows the viewport, not the chunk lane',
      (tester) async {
    useViewport(tester, const Size(375, 812));
    final captured = <SagaMapBreakpointName>[];

    await tester.pumpWidget(
      host(
        pathAxis: SagaMapPathAxis.horizontal,
        child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
          levels: const [
            LevelData(
                id: 1, position: SagaPoint(0.5, 0.0), biomeId: kBiomeIdForest),
          ],
          chunkIndex: 0,
          // A lane far wider than any desktop viewport. Resolving the
          // breakpoint from this would misreport a phone as ultra4k.
          chunkExtent: 3000,
          chunkSpanNormalized: 1.0,
          biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
          responsiveResolver: _resolverFor(SagaMapPathAxis.horizontal),
          nodeBuilder: (context, level, layout) {
            captured.add(layout.breakpoint);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured, isNotEmpty);
    expect(captured.first, SagaMapBreakpointName.mobile);
  });

  testWidgets('lateral cap does not shorten the horizontal path axis',
      (tester) async {
    // Desktop width, so maxLateralExtentPolicy resolves to a finite 1366.
    useViewport(tester, const Size(1400, 900));

    await tester.pumpWidget(
      host(
        pathAxis: SagaMapPathAxis.horizontal,
        child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
          levels: const [
            LevelData(
                id: 1, position: SagaPoint(0.5, 0.0), biomeId: kBiomeIdForest),
            LevelData(
                id: 2, position: SagaPoint(0.5, 0.5), biomeId: kBiomeIdForest),
          ],
          chunkIndex: 0,
          chunkExtent: 2000,
          chunkSpanNormalized: 1.0,
          biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
          responsiveResolver: _resolverFor(SagaMapPathAxis.horizontal),
          nodeBuilder: _slotNode,
        ),
      ),
    );

    // Half-way along the path must land at half the chunk extent, untouched by
    // the 1366 lateral cap.
    expect(_nodeCenter(tester, 1).dx, moreOrLessEquals(0, epsilon: 0.5));
    expect(_nodeCenter(tester, 2).dx, moreOrLessEquals(1000, epsilon: 0.5));
  });

  testWidgets('lateral cap still applies to a vertical map width',
      (tester) async {
    useViewport(tester, const Size(1800, 900));

    await tester.pumpWidget(
      host(
        pathAxis: SagaMapPathAxis.vertical,
        child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
          levels: const [
            LevelData(
                id: 1, position: SagaPoint(0.5, 0.5), biomeId: kBiomeIdForest),
          ],
          chunkIndex: 0,
          chunkExtent: 1000,
          chunkSpanNormalized: 1.0,
          biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
          responsiveResolver: _resolverFor(SagaMapPathAxis.vertical),
          nodeBuilder: _slotNode,
        ),
      ),
    );

    // Content is capped at 1366 and centered in 1800, so a lateral-center node
    // sits at the viewport's midpoint.
    expect(_nodeCenter(tester, 1).dx, moreOrLessEquals(900, epsilon: 0.5));
  });

  testWidgets('band centering is identical across chunks', (tester) async {
    useViewport(tester, const Size(400, 800));
    const bounds = SagaLateralBounds(min: 0.2, max: 0.6);
    const span = 1.0;

    Widget chunk(int index, LevelData level) {
      return MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
        levels: [level],
        chunkIndex: index,
        chunkExtent: 400,
        chunkSpanNormalized: span,
        lateralBounds: bounds,
        biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
        responsiveResolver: _resolverFor(SagaMapPathAxis.horizontal),
        nodeBuilder: _slotNode,
      );
    }

    await tester.pumpWidget(
      host(
        pathAxis: SagaMapPathAxis.horizontal,
        child: Row(
          children: [
            // Same lateral coordinate, different chunks. A chunk-local
            // centering offset would drift them apart.
            chunk(
              0,
              const LevelData(
                  id: 1, position: SagaPoint(0.2, 0.0), biomeId: kBiomeIdForest),
            ),
            chunk(
              1,
              const LevelData(
                  id: 2, position: SagaPoint(0.2, 1.0), biomeId: kBiomeIdForest),
            ),
          ],
        ),
      ),
    );

    expect(
      _nodeCenter(tester, 1).dy,
      moreOrLessEquals(_nodeCenter(tester, 2).dy, epsilon: 0.001),
    );
  });

  testWidgets('mismatched chunk span asserts instead of silently clamping',
      (tester) async {
    useViewport(tester, const Size(400, 800));

    await tester.pumpWidget(
      host(
        pathAxis: SagaMapPathAxis.vertical,
        child: MapChunkWidget(chunkContext: SagaChunkContext(chunkIndex: 0, levels: const [], progress: const {}),
          levels: const [
            // Sits at 2.5x the declared span: previously snapped onto the edge.
            LevelData(
                id: 1, position: SagaPoint(0.5, 2.5), biomeId: kBiomeIdForest),
          ],
          chunkIndex: 0,
          chunkExtent: 600,
          chunkSpanNormalized: 1.0,
          biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
          responsiveResolver: _resolverFor(SagaMapPathAxis.vertical),
          nodeBuilder: _slotNode,
        ),
      ),
    );

    expect(tester.takeException(), isAssertionError);
  });
}
