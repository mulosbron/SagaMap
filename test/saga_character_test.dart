import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// A character standing on the path: placement, anchoring, ownership across
/// chunk seams, and scaling with the map.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _generator = SagaMapLevelGenerator();

List<LevelData> _chunk(int index) => _generator.generateLevels(
      globalSeed: 5,
      config: _config,
      startLevelId: index * _levelsPerChunk,
      count: _levelsPerChunk,
    );

SagaMapRenderContext _context(int index) {
  final previous = index > 0 ? _chunk(index - 1) : const <LevelData>[];
  final next = _chunk(index + 1);
  return SagaMapRenderContext(
    levels: _chunk(index),
    chunkIndex: index,
    chunkSize: const SagaSize(width: 400, height: 800),
    chunkSpanNormalized: _config.spanForLevelCount(_levelsPerChunk),
    layout: const SagaResponsiveResolver().resolveForWidth(400),
    lateralBounds: _config.lateralBounds,
    leadingNeighbors: previous.isEmpty
        ? const <LevelData>[]
        : previous.sublist(previous.length - kSagaPathNeighborCount),
    trailingNeighbors: next.sublist(0, kSagaPathNeighborCount),
  );
}

Widget _marker(BuildContext context, SagaCharacterState state) =>
    const SizedBox.expand(key: ValueKey('hero'));

void main() {
  group('ownership across seams', () {
    test('a chunk owns only positions on its own levels', () {
      final chunk1 = _context(1);

      expect(chunk1.ownsPathPosition(10), isTrue);
      expect(chunk1.ownsPathPosition(19.9), isTrue);
      expect(chunk1.ownsPathPosition(9.5), isFalse);
      expect(chunk1.ownsPathPosition(20), isFalse);
    });

    test('exactly one chunk claims any position near a seam', () {
      // A chunk can resolve positions inside its neighbours, because it holds
      // their levels to keep the curve smooth. Without a single owner both
      // chunks would draw the character.
      for (final position in const [9.0, 9.5, 9.99, 10.0, 10.5]) {
        final owners = [
          for (var index = 0; index < 3; index++)
            if (_context(index).ownsPathPosition(position)) index,
        ];
        expect(owners, hasLength(1), reason: 'position $position -> $owners');
      }
    });

    test('both chunks can still resolve a shared position', () {
      // Ownership is about who draws; either side must still be able to place
      // the character, which is what lets the hand-off happen at a node.
      expect(_context(0).characterPixel(9.5), isNotNull);
      expect(_context(1).characterPixel(9.5), isNotNull);
    });

    test('an empty chunk owns nothing', () {
      final empty = SagaMapRenderContext(
        levels: const <LevelData>[],
        chunkIndex: 0,
        chunkSize: const SagaSize(width: 400, height: 800),
        chunkSpanNormalized: 1,
        layout: const SagaResponsiveResolver().resolveForWidth(400),
      );
      expect(empty.ownsPathPosition(0), isFalse);
    });
  });

  group('anchoring', () {
    const point = SagaPoint(200, 500);
    const size = Size(40, 60);

    SagaCharacter character(SagaCharacterAnchor anchor) => SagaCharacter(
          pathPosition: 0,
          builder: _marker,
          size: size,
          anchor: anchor,
        );

    test('bottomCenter puts the feet on the node', () {
      final topLeft = character(SagaCharacterAnchor.bottomCenter)
          .topLeftFor(point, size);
      expect(topLeft.dx, 180); // centred horizontally
      expect(topLeft.dy, 440); // bottom edge lands on the node
    });

    test('center puts the middle on the node', () {
      final topLeft =
          character(SagaCharacterAnchor.center).topLeftFor(point, size);
      expect(topLeft.dy, 470);
    });

    test('topCenter hangs the art below the node', () {
      final topLeft =
          character(SagaCharacterAnchor.topCenter).topLeftFor(point, size);
      expect(topLeft.dy, 500);
    });

    test('offset nudges after anchoring', () {
      const nudged = SagaCharacter(
        pathPosition: 0,
        builder: _marker,
        size: size,
        offset: Offset(5, -8),
      );
      final topLeft = nudged.topLeftFor(point, size);
      expect(topLeft.dx, 185);
      expect(topLeft.dy, 432);
    });
  });

  group('state', () {
    test('facesLeft follows the path direction', () {
      SagaCharacterState state(SagaPoint direction) => SagaCharacterState(
            pathPosition: 1,
            nearestLevelId: 1,
            motion: SagaCharacterMotion.idle,
            facing: SagaCharacterFacing.forward,
            direction: direction,
            headingRadians: 0,
            layout: const SagaResponsiveResolver().resolveForWidth(400),
          );

      expect(state(const SagaPoint(1, 0)).facesLeft, isFalse);
      expect(state(const SagaPoint(-1, 0)).facesLeft, isTrue);
    });
  });

  group('rendering', () {
    Future<void> pump(
      WidgetTester tester, {
      required SagaCharacter? character,
      int chunkIndex = 0,
      double userZoom = 1,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      final previous = chunkIndex > 0
          ? _chunk(chunkIndex - 1)
          : const <LevelData>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MapChunkWidget(
                levels: _chunk(chunkIndex),
                chunkIndex: chunkIndex,
                chunkExtent: 800,
                chunkSpanNormalized:
                    _config.spanForLevelCount(_levelsPerChunk),
                lateralBounds: _config.lateralBounds,
                leadingNeighbors: previous.isEmpty
                    ? const <LevelData>[]
                    : previous.sublist(previous.length - 2),
                trailingNeighbors: _chunk(chunkIndex + 1).sublist(0, 2),
                biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                responsiveResolver: SagaResponsiveResolver(
                  config: SagaMapResponsiveConfig.defaults.copyWith(
                    nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
                    zoomPolicy: const SagaMapValuePolicy.all(1.0),
                  ),
                ),
                userZoom: userZoom,
                character: character,
                nodeBuilder: (context, level, layout) =>
                    SizedBox.expand(key: ValueKey('node-${level.id}')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('nothing is drawn without a character', (tester) async {
      await pump(tester, character: null);
      expect(find.byKey(const ValueKey('hero')), findsNothing);
    });

    testWidgets('the character appears on its chunk', (tester) async {
      await pump(
        tester,
        character: const SagaCharacter(pathPosition: 3, builder: _marker),
      );
      expect(find.byKey(const ValueKey('hero')), findsOneWidget);
    });

    testWidgets('a chunk that does not own the position draws nothing',
        (tester) async {
      // Position 3 belongs to chunk 0, so chunk 1 must leave it alone even
      // though it can resolve nearby points.
      await pump(
        tester,
        chunkIndex: 1,
        character: const SagaCharacter(pathPosition: 3, builder: _marker),
      );
      expect(find.byKey(const ValueKey('hero')), findsNothing);
    });

    testWidgets('feet land on the node it stands on', (tester) async {
      await pump(
        tester,
        character: const SagaCharacter(
          pathPosition: 4,
          builder: _marker,
          size: Size(40, 60),
        ),
      );

      final node = tester.getCenter(find.byKey(const ValueKey('node-4')));
      final hero = tester.getRect(find.byKey(const ValueKey('hero')));

      expect(hero.bottom, moreOrLessEquals(node.dy, epsilon: 0.5));
      expect(hero.center.dx, moreOrLessEquals(node.dx, epsilon: 0.5));
    });

    testWidgets('a fractional position sits between two nodes',
        (tester) async {
      await pump(
        tester,
        character: const SagaCharacter(
          pathPosition: 4.5,
          builder: _marker,
          anchor: SagaCharacterAnchor.center,
        ),
      );

      final a = tester.getCenter(find.byKey(const ValueKey('node-4'))).dy;
      final b = tester.getCenter(find.byKey(const ValueKey('node-5'))).dy;
      final hero = tester.getCenter(find.byKey(const ValueKey('hero'))).dy;

      expect(hero, greaterThan(a));
      expect(hero, lessThan(b));
    });

    testWidgets('the character grows with zoom', (tester) async {
      await pump(
        tester,
        character: const SagaCharacter(
          pathPosition: 3,
          builder: _marker,
          size: Size(40, 60),
        ),
      );
      final before = tester.getSize(find.byKey(const ValueKey('hero')));

      await pump(
        tester,
        userZoom: 2,
        character: const SagaCharacter(
          pathPosition: 3,
          builder: _marker,
          size: Size(40, 60),
        ),
      );
      final after = tester.getSize(find.byKey(const ValueKey('hero')));

      expect(after.width, moreOrLessEquals(before.width * 2, epsilon: 0.5));
    });

    testWidgets('scaleWithZoom false keeps a fixed size', (tester) async {
      await pump(
        tester,
        userZoom: 2,
        character: const SagaCharacter(
          pathPosition: 3,
          builder: _marker,
          size: Size(40, 60),
          scaleWithZoom: false,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('hero'))).width,
        moreOrLessEquals(40, epsilon: 0.5),
      );
    });

    testWidgets('the builder is told where it stands', (tester) async {
      SagaCharacterState? seen;
      await pump(
        tester,
        character: SagaCharacter(
          pathPosition: 6.5,
          motion: SagaCharacterMotion.walking,
          builder: (context, state) {
            seen = state;
            return const SizedBox.expand(key: ValueKey('hero'));
          },
        ),
      );

      expect(seen, isNotNull);
      expect(seen!.pathPosition, 6.5);
      expect(seen!.nearestLevelId, 7);
      expect(seen!.motion, SagaCharacterMotion.walking);
      // Direction comes from the curve, so it is usable for facing.
      expect(seen!.direction.x.isFinite, isTrue);
    });

    testWidgets('the character does not swallow node taps', (tester) async {
      final tapped = <int>[];
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MapChunkWidget(
                levels: _chunk(0),
                chunkIndex: 0,
                chunkExtent: 800,
                chunkSpanNormalized:
                    _config.spanForLevelCount(_levelsPerChunk),
                lateralBounds: _config.lateralBounds,
                biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                onLevelTap: (level) => tapped.add(level.id),
                // Sitting right on the node it must not block.
                character: const SagaCharacter(
                  pathPosition: 4,
                  builder: _marker,
                  size: Size(120, 120),
                  anchor: SagaCharacterAnchor.center,
                ),
                nodeBuilder: (context, level, layout) =>
                    SizedBox.expand(key: ValueKey('node-${level.id}')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('node-4')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(tapped, contains(4));
    });

    testWidgets('a labelled character is announced', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        character: const SagaCharacter(
          pathPosition: 3,
          builder: _marker,
          semanticsLabel: 'Player, level 3',
        ),
      );

      expect(find.bySemanticsLabel('Player, level 3'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an unlabelled character adds no semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        character: const SagaCharacter(pathPosition: 3, builder: _marker),
      );

      expect(find.bySemanticsLabel('Player, level 3'), findsNothing);
      handle.dispose();
    });
  });
}
