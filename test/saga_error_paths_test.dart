@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:saga_map/src/rendering/widgets/saga_map_view_internals.dart'
    show validateZoomRange;

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

  group('A-12 — configuration fails at its source, not at paint time', () {
    // All three used to reach a paint before failing, and one named the wrong
    // field when it did. An exception that names the wrong field sends the
    // host looking in the wrong place, which is worse than a late one.

    test('spanForLevelCount names levelCount, in release too', () {
      // The release error used to name `chunkSpanNormalized` — the field the
      // *result* is assigned to, not the argument that was wrong.
      expect(
        () => SagaMapConfig.defaultConfig.spanForLevelCount(0),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'levelCount')
            .having((e) => e.invalidValue, 'invalidValue', 0)),
      );
      expect(
        () => SagaMapConfig.defaultConfig.spanForLevelCount(-3),
        throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'levelCount')),
      );
      // The ordinary path is untouched.
      expect(SagaMapConfig.defaultConfig.spanForLevelCount(10),
          SagaMapConfig.defaultConfig.stepHeight * 10);
    });

    test('a degenerate sheet blames the field its layout actually reads', () {
      // The old message said "must have at least one column" for every layout.
      // A horizontal sheet has one column per frame and never reads `columns`,
      // so that sent the host to inspect a field the layout ignores; the wrong
      // field named is worse than the error arriving late.
      //
      // Exercised through the message builder because a debug build cannot
      // construct a degenerate sheet to ask — the constructor's asserts refuse
      // it first, so `resolvedColumns` only ever throws in release.
      expect(
        describeDegenerateSheet(
            layout: SagaSpriteLayout.horizontal, frameCount: 0, columns: null),
        allOf(contains('frameCount'), isNot(contains('grid columns'))),
      );
      expect(
        describeDegenerateSheet(
            layout: SagaSpriteLayout.vertical, frameCount: 0, columns: null),
        contains('frameCount'),
      );
      expect(
        describeDegenerateSheet(
            layout: SagaSpriteLayout.grid, frameCount: 4, columns: 0),
        contains('columns'),
      );
      // And a sound sheet still resolves rather than complaining.
      expect(
        const SagaSpriteSheet(frameWidth: 10, frameHeight: 10, frameCount: 4)
            .resolvedColumns,
        4,
      );
    });

    test('a backwards zoom range is refused before anything paints', () {
      // Two layers. In debug, `SagaMapZoomConfig`'s own asserts refuse the
      // config at construction — for a `const` expression the compiler refuses
      // it outright. In release those asserts are gone, and `clamp`, reached
      // from a pinch a frame away from the line that built the config,
      // returned NaN for every call.
      //
      // `validateZoomRange` is the release-mode counterpart, run where the
      // view *accepts* the config rather than where it paints. It takes plain
      // numbers precisely so this test can reach it: a debug build cannot
      // build the invalid config to pass in.
      expect(
        () => validateZoomRange(min: 2, max: 0.5, initial: 2),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'SagaMapZoomConfig.max')),
      );
      expect(
        () => validateZoomRange(min: 1, max: 2, initial: 5),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'SagaMapZoomConfig.initial')),
      );
      expect(
        () => validateZoomRange(min: 0, max: 2, initial: 1),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'SagaMapZoomConfig.min')),
      );
      // A sound range passes.
      validateZoomRange(min: 0.5, max: 2, initial: 1);
    });
  });
}
