import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Camera: following a travelling character, opening where the player left off,
/// and scrolling to a level on demand.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _chunkExtent = 600.0;
const _generator = SagaMapLevelGenerator();

SagaInfiniteMapController _mapController({int? maxChunkCount}) =>
    SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 2,
      maxChunkCount: maxChunkCount,
      chunkLoader: (chunkIndex, sectionsPerChunk) =>
          _generator.generateLevels(
        globalSeed: 5,
        config: _config,
        startLevelId: chunkIndex * sectionsPerChunk,
        count: sectionsPerChunk,
      ),
    );

class _TickerHost extends StatefulWidget {
  const _TickerHost({required this.build});
  final Widget Function(BuildContext, TickerProvider) build;

  @override
  State<_TickerHost> createState() => _TickerHostState();
}

class _TickerHostState extends State<_TickerHost>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => widget.build(context, this);
}

void main() {
  double offsetOf(WidgetTester tester) =>
      tester.widget<Scrollable>(find.byType(Scrollable)).controller!.offset;

  /// Mounts a map, optionally with a character and a camera controller.
  Future<SagaCharacterController?> pumpMap(
    WidgetTester tester, {
    bool withCharacter = true,
    bool followCharacter = true,
    double initialCharacterPosition = 0,
    double? initialPathPosition,
    SagaMapCameraController? camera,
    int? maxChunkCount,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final mapController = _mapController(maxChunkCount: maxChunkCount);
    addTearDown(mapController.dispose);
    SagaCharacterController? character;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _TickerHost(
            build: (context, vsync) {
              if (withCharacter) {
                character ??= SagaCharacterController(
                  vsync: vsync,
                  initialPosition: initialCharacterPosition,
                  stepDuration: const Duration(milliseconds: 100),
                  stepPause: Duration.zero,
                  curve: Curves.linear,
                );
              }
              return SagaInfiniteMapView(
                controller: mapController,
                chunkExtent: _chunkExtent,
                chunkSpanNormalized:
                    _config.spanForLevelCount(_levelsPerChunk),
                lateralBounds: _config.lateralBounds,
                biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                responsiveResolver: SagaResponsiveResolver(
                  config: SagaMapResponsiveConfig.defaults.copyWith(
                    nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
                  ),
                ),
                followCharacter: followCharacter,
                initialPathPosition: initialPathPosition,
                cameraController: camera,
                character: character == null
                    ? null
                    : SagaCharacter(
                        controller: character,
                        builder: (context, state) =>
                            const SizedBox.expand(key: ValueKey('hero')),
                      ),
                nodeBuilder: (context, level, layout) =>
                    SizedBox.expand(key: ValueKey('node-${level.id}')),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (character != null) addTearDown(character!.dispose);
    return character;
  }

  group('opening position', () {
    testWidgets('opens at the top with nothing to resume', (tester) async {
      await pumpMap(tester);
      expect(offsetOf(tester), 0);
    });

    testWidgets('resumes where the player left off', (tester) async {
      // The whole point of "continue from where you were": the map should not
      // open at level zero for someone who has played to 15.
      await pumpMap(tester, initialCharacterPosition: 15);
      expect(offsetOf(tester), greaterThan(0));
    });

    testWidgets('an explicit opening position wins', (tester) async {
      await pumpMap(
        tester,
        initialCharacterPosition: 2,
        initialPathPosition: 18,
      );
      final atEighteen = offsetOf(tester);

      await pumpMap(tester, initialCharacterPosition: 2);
      expect(atEighteen, greaterThan(offsetOf(tester)));
    });

    testWidgets('loads the chunks the opening position needs',
        (tester) async {
      // Only two chunks load initially; level 35 lives in the fourth.
      await pumpMap(tester, initialPathPosition: 35, withCharacter: false);
      expect(find.byKey(const ValueKey('node-35')), findsOneWidget);
    });

    testWidgets('a capped map stops at its last chunk', (tester) async {
      await pumpMap(
        tester,
        initialPathPosition: 500,
        withCharacter: false,
        maxChunkCount: 3,
      );
      // Clamped to what exists rather than scrolling into nothing.
      expect(tester.takeException(), isNull);
      expect(offsetOf(tester), greaterThan(0));
    });

    testWidgets('the opening scroll happens once', (tester) async {
      final character = await pumpMap(tester, initialCharacterPosition: 12);
      final opened = offsetOf(tester);

      // A later rebuild must not yank the map back to the opening position.
      await tester.drag(find.byType(ListView), const Offset(0, -150));
      await tester.pumpAndSettle();
      final scrolled = offsetOf(tester);
      expect(scrolled, isNot(opened));

      character!.jumpTo(12);
      await tester.pumpAndSettle();
      expect(offsetOf(tester), scrolled);
    });
  });

  group('following', () {
    testWidgets('keeps a travelling character in view', (tester) async {
      final character = await pumpMap(tester);
      expect(offsetOf(tester), 0);

      unawaited(character!.moveTo(12));
      await tester.pumpAndSettle();

      // Twelve levels along, the viewport must have come with it.
      expect(offsetOf(tester), greaterThan(200));
    });

    testWidgets('the character stays on screen throughout', (tester) async {
      final character = await pumpMap(tester);

      unawaited(character!.moveTo(14));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final hero = find.byKey(const ValueKey('hero'));
        if (hero.evaluate().isEmpty) continue;
        final centre = tester.getCenter(hero);
        expect(centre.dy, greaterThan(-100));
        expect(centre.dy, lessThan(900));
      }
      await tester.pumpAndSettle();
    });

    testWidgets('following can be turned off', (tester) async {
      final character = await pumpMap(tester, followCharacter: false);

      unawaited(character!.moveTo(12));
      await tester.pumpAndSettle();

      expect(offsetOf(tester), 0);
    });

    testWidgets('a still character does not move the camera', (tester) async {
      final character = await pumpMap(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      final scrolled = offsetOf(tester);

      character!.jumpTo(3);
      await tester.pumpAndSettle();
      // Following applies to travel, not to every position change.
      expect(offsetOf(tester), scrolled);
    });
  });

  group('camera controller', () {
    testWidgets('scrolls to a level on demand', (tester) async {
      final camera = SagaMapCameraController();
      addTearDown(camera.dispose);
      await pumpMap(tester, camera: camera, withCharacter: false);

      expect(camera.isAttached, isTrue);
      expect(offsetOf(tester), 0);

      unawaited(camera.scrollToPathPosition(16));
      await tester.pumpAndSettle();
      expect(offsetOf(tester), greaterThan(200));
    });

    testWidgets('alignment places the target in the viewport',
        (tester) async {
      final camera = SagaMapCameraController();
      addTearDown(camera.dispose);
      await pumpMap(tester, camera: camera, withCharacter: false);

      unawaited(camera.scrollToPathPosition(16, alignment: 0));
      await tester.pumpAndSettle();
      final atLeadingEdge = offsetOf(tester);

      unawaited(camera.scrollToPathPosition(16, alignment: 1));
      await tester.pumpAndSettle();
      final atTrailingEdge = offsetOf(tester);

      // Aligning to the trailing edge means scrolling less far.
      expect(atTrailingEdge, lessThan(atLeadingEdge));
    });

    testWidgets('scrolls to the character', (tester) async {
      final camera = SagaMapCameraController();
      addTearDown(camera.dispose);
      final character = await pumpMap(
        tester,
        camera: camera,
        followCharacter: false,
      );

      character!.jumpTo(17);
      await tester.pumpAndSettle();
      expect(offsetOf(tester), 0);

      unawaited(camera.scrollToCharacter());
      await tester.pumpAndSettle();
      expect(offsetOf(tester), greaterThan(200));
    });

    testWidgets('detaches when the view goes away', (tester) async {
      final camera = SagaMapCameraController();
      addTearDown(camera.dispose);
      await pumpMap(tester, camera: camera, withCharacter: false);
      expect(camera.isAttached, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(camera.isAttached, isFalse);
    });

    testWidgets('an unattached controller is a no-op', (tester) async {
      final camera = SagaMapCameraController();
      addTearDown(camera.dispose);

      // Calling before mounting must not throw.
      await camera.scrollToPathPosition(9);
      await camera.scrollToCharacter();
      expect(camera.isAttached, isFalse);
    });
  });
}
