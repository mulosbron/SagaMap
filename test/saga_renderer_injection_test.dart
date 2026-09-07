import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// T-19: `SagaMapRenderer` called itself an extension point while nothing in
/// the package depended on the type — a host wanting its own path painter had
/// to fork the widget.

const _levels = <LevelData>[
  LevelData(id: 0, position: SagaPoint(0.3, 0.0), biomeId: kBiomeIdForest),
  LevelData(id: 1, position: SagaPoint(0.7, 0.5), biomeId: kBiomeIdForest),
];

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.levelCount);
  final int levelCount;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 10, 10),
      Paint()..color = const Color(0xFFFF00FF),
    );
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter old) =>
      old.levelCount != levelCount;
}

/// The whole seam: a renderer that ignores the built-in look entirely.
class _CountingRenderer implements SagaMapRenderer<CustomPainter> {
  int calls = 0;
  int lastLevelCount = -1;

  @override
  CustomPainter render(SagaMapRenderContext context) {
    calls++;
    lastLevelCount = context.levels.length;
    return _MarkerPainter(context.levels.length);
  }
}

void main() {
  testWidgets('a host path renderer replaces the built-in one', (tester) async {
    final renderer = _CountingRenderer();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 400,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            pathRenderer: renderer,
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(renderer.calls, greaterThan(0));
    expect(renderer.lastLevelCount, _levels.length);

    // The chunk is painted by the injected renderer, not MapChunkPainter.
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<CustomPainter>();
    expect(painters.whereType<_MarkerPainter>(), isNotEmpty);
  });

  testWidgets('passing nothing keeps the built-in look', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            levels: _levels,
            chunkIndex: 0,
            chunkExtent: 400,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<CustomPainter>();
    expect(painters.whereType<_MarkerPainter>(), isEmpty);
    expect(painters, isNotEmpty);
  });
}
