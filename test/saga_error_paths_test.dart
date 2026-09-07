@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// T-24: the paths taken when something has already gone wrong. Each of these
/// used to fail silently, throw where an empty answer was correct, or put host
/// exception text on a player's screen unbounded.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;

void main() {
  testWidgets('a missing background asset reaches the host', (tester) async {
    Object? seenError;
    String? seenPath;
    int? seenChunk;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapChunkWidget(
            levels: const [
              LevelData(
                  id: 0, position: SagaPoint(0.5, 0.5), biomeId: 'forest'),
            ],
            chunkIndex: 0,
            chunkExtent: 300,
            chunkSpanNormalized: 1.0,
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            backgroundConfig: SagaMapBackgroundConfig.imageAsset(
              assetPath: 'assets/does_not_exist.png',
              errorBuilder: (context, chunkIndex, path, error) {
                seenChunk = chunkIndex;
                seenPath = path;
                seenError = error;
                return const ColoredBox(color: Color(0xFF884400));
              },
            ),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Without the hook this renders a blank chunk and a console line, and the
    // host has no way to know the map is not what it looks like.
    expect(seenError, isNotNull);
    expect(seenPath, 'assets/does_not_exist.png');
    expect(seenChunk, 0);
  });

  test('an empty chunk has no path to split, and does not throw', () {
    // A chunk with no levels is a normal state while one loads. It used to
    // throw a StateError out of `levels.first`.
    final context = SagaMapRenderContext(
      levels: const [],
      chunkIndex: 0,
      chunkSize: const SagaSize(width: 100, height: 100),
      chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
      layout: const SagaResponsiveResolver().resolveForWidth(400),
      pathProgressPosition: 4,
    );

    final split = context.splitPathAtProgress();
    expect(split.walked, isEmpty);
    expect(split.upcoming, isEmpty);
    expect(context.ownsPathPosition(4), isFalse);
  });

  testWidgets('a loader failure is reported without dumping the exception',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final controller = SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 1,
      chunkLoader: (chunkIndex, sectionsPerChunk) => throw Exception(
        'https://internal.example/secrets?token=${'x' * 500}',
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SagaInfiniteMapView(
            controller: controller,
            chunkExtent: 600,
            chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
            biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
            nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.widgetList<Text>(find.byType(Text)).single.data!;
    expect(text, startsWith('Failed to load chunks'));

    // Clipped: the message is for a player, and a host exception's toString can
    // carry a URL, a token or a path that has no business on their screen.
    expect(text.length, lessThan(300));
  });
}
