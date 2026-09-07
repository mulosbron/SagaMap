import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Walking: stepping node by node, interruption, the locks that stop the user
/// fighting a journey, and the chunk hand-off.

const _config = SagaMapConfig.defaultConfig;
const _levelsPerChunk = 10;
const _generator = SagaMapLevelGenerator();

SagaInfiniteMapController _mapController() => SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 4,
      chunkLoader: (chunkIndex, sectionsPerChunk) => _generator.generateLevels(
        globalSeed: 5,
        config: _config,
        startLevelId: chunkIndex * sectionsPerChunk,
        count: sectionsPerChunk,
      ),
    );

/// Hosts a controller so it gets a real ticker.
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
  group('stepping', () {
    testWidgets('walks one node at a time', (tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 100),
              stepPause: Duration.zero,
              curve: Curves.linear,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.moveTo(3));
      expect(controller.isMoving, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Half of the first step, not half of the whole journey.
      expect(controller.pathPosition, closeTo(0.5, 0.05));

      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.pathPosition, closeTo(1, 0.05));

      await tester.pumpAndSettle();
      expect(controller.pathPosition, 3);
      expect(controller.isMoving, isFalse);
    });

    testWidgets('a longer journey takes proportionally longer', (tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 100),
              stepPause: Duration.zero,
              curve: Curves.linear,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      // A partial step must not cost a whole step's time, or the character
      // visibly changes pace.
      unawaited(controller.moveTo(0.5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.pathPosition, closeTo(0.5, 0.05));
      await tester.pumpAndSettle();
    });

    testWidgets('pauses on each node it passes through', (tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 100),
              stepPause: const Duration(milliseconds: 100),
              curve: Curves.linear,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.moveTo(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.pathPosition, closeTo(1, 0.05));

      // Standing still on node 1 while the pause runs.
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.pathPosition, closeTo(1, 0.05));

      await tester.pumpAndSettle();
      expect(controller.pathPosition, 2);
    });

    testWidgets('walks backwards too', (tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              initialPosition: 5,
              stepDuration: const Duration(milliseconds: 50),
              stepPause: Duration.zero,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.moveTo(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(controller.facing, SagaCharacterFacing.backward);

      await tester.pumpAndSettle();
      expect(controller.pathPosition, 2);
    });

    testWidgets('advance moves relative to where it stands', (tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              initialPosition: 4,
              stepDuration: const Duration(milliseconds: 20),
              stepPause: Duration.zero,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.advance(steps: 2));
      await tester.pumpAndSettle();
      expect(controller.pathPosition, 6);
    });
  });

  group('interruption', () {
    Future<SagaCharacterController> host(WidgetTester tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 100),
              stepPause: Duration.zero,
              curve: Curves.linear,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('a new destination resumes from where it got to',
        (tester) async {
      final controller = await host(tester);

      unawaited(controller.moveTo(5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 60));
      final interruptedAt = controller.pathPosition;
      expect(interruptedAt, greaterThan(1));

      unawaited(controller.moveTo(0));
      await tester.pump();
      // Snapping back to the old start would be a visible jump.
      expect(controller.pathPosition, closeTo(interruptedAt, 0.2));

      await tester.pumpAndSettle();
      expect(controller.pathPosition, 0);
    });

    testWidgets('stop leaves the character where it stands', (tester) async {
      final controller = await host(tester);

      unawaited(controller.moveTo(5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      controller.stop();
      final stoppedAt = controller.pathPosition;

      expect(controller.isMoving, isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.pathPosition, stoppedAt);
    });

    testWidgets('jumpTo cancels a journey', (tester) async {
      final controller = await host(tester);

      unawaited(controller.moveTo(9));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      controller.jumpTo(2);

      expect(controller.pathPosition, 2);
      expect(controller.isMoving, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.pathPosition, 2);
    });

    testWidgets('an unanimated move places the character at once',
        (tester) async {
      final controller = await host(tester);

      await controller.moveTo(7, animate: false);
      expect(controller.pathPosition, 7);
      expect(controller.isMoving, isFalse);
    });
  });

  group('hop', () {
    testWidgets('arcs up between nodes and lands on them', (tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 100),
              stepPause: Duration.zero,
              curve: Curves.linear,
              gait: SagaCharacterGait.hop,
              hopHeight: 40,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.hopOffset, 0);

      unawaited(controller.moveTo(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Negative is upwards on screen; the peak is mid-step.
      expect(controller.hopOffset, lessThan(-30));

      await tester.pumpAndSettle();
      // Back on the ground once it arrives, or it would float past the node.
      expect(controller.hopOffset, 0);
    });

    testWidgets('a walking gait never lifts off', (tester) async {
      late SagaCharacterController controller;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 50),
              stepPause: Duration.zero,
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.moveTo(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(controller.hopOffset, 0);
      await tester.pumpAndSettle();
    });
  });

  group('locks and hand-off', () {
    Future<SagaCharacterController> pumpMap(
      WidgetTester tester, {
      SagaMapZoomConfig? zoomConfig = const SagaMapZoomConfig(),
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      final mapController = _mapController();
      addTearDown(mapController.dispose);
      late SagaCharacterController character;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TickerHost(
              build: (context, vsync) {
                character = SagaCharacterController(
                  vsync: vsync,
                  stepDuration: const Duration(milliseconds: 100),
                  stepPause: Duration.zero,
                  curve: Curves.linear,
                );
                return SagaInfiniteMapView(
                  controller: mapController,
                  chunkExtent: 600,
                  chunkSpanNormalized:
                      _config.spanForLevelCount(_levelsPerChunk),
                  lateralBounds: _config.lateralBounds,
                  biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                  zoomConfig: zoomConfig,
                  character: SagaCharacter(
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
      addTearDown(character.dispose);
      return character;
    }

    testWidgets('scrolling is locked while the character travels',
        (tester) async {
      final character = await pumpMap(tester);
      final scrollable =
          tester.widget<Scrollable>(find.byType(Scrollable)).controller!;

      unawaited(character.moveTo(4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final before = scrollable.offset;
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(scrollable.offset, before);

      await tester.pumpAndSettle();
    });

    testWidgets('scrolling works again once it arrives', (tester) async {
      final character = await pumpMap(tester);
      final scrollable =
          tester.widget<Scrollable>(find.byType(Scrollable)).controller!;

      unawaited(character.moveTo(2));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scrollable.offset, greaterThan(0));
    });

    testWidgets('pinch zoom is disabled while travelling', (tester) async {
      final character = await pumpMap(tester);
      expect(find.byType(RawGestureDetector), findsWidgets);

      unawaited(character.moveTo(4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // The pinch detector is dropped outright, so it cannot fight the camera.
      final detectors = tester
          .widgetList<RawGestureDetector>(find.byType(RawGestureDetector))
          .where((d) => d.gestures.containsKey(SagaPinchGestureRecognizer));
      expect(detectors, isEmpty);

      await tester.pumpAndSettle();
    });

    testWidgets('the character survives a chunk hand-off', (tester) async {
      final character = await pumpMap(tester);

      // Level 10 opens chunk 1, so this journey crosses a seam.
      character.jumpTo(8);
      await tester.pumpAndSettle();
      final before = tester.element(find.byKey(const ValueKey('hero')));

      unawaited(character.moveTo(11));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('hero')), findsOneWidget);
      // Same element carried across by the global key: a running sprite or
      // Rive animation keeps playing instead of restarting.
      expect(
        identical(tester.element(find.byKey(const ValueKey('hero'))), before),
        isTrue,
      );
    });

    testWidgets('exactly one character is drawn mid-journey', (tester) async {
      final character = await pumpMap(tester);

      character.jumpTo(9.5);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hero')), findsOneWidget);

      character.jumpTo(10);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hero')), findsOneWidget);
    });
  });

  group('gates the view applies itself', () {
    /// Pumps a map carrying [gates], returning the character controller and a
    /// setter that swaps the gate list and rebuilds — the host never calls
    /// `clampTravelThroughGates`.
    Future<(SagaCharacterController, void Function(List<SagaMapGate>))> pumpGated(
      WidgetTester tester,
      List<SagaMapGate> gates, {
      void Function(LevelData)? onLevelReached,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      final mapController = _mapController();
      addTearDown(mapController.dispose);
      late SagaCharacterController character;
      late void Function(List<SagaMapGate>) setGates;
      var current = gates;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setGates = (next) => setState(() => current = next);
                return _TickerHost(
                  build: (context, vsync) {
                    character = SagaCharacterController(
                      vsync: vsync,
                      stepDuration: const Duration(milliseconds: 40),
                      stepPause: Duration.zero,
                      curve: Curves.linear,
                    );
                    return SagaInfiniteMapView(
                      controller: mapController,
                      chunkExtent: 600,
                      chunkSpanNormalized:
                          _config.spanForLevelCount(_levelsPerChunk),
                      lateralBounds: _config.lateralBounds,
                      biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
                      gates: current,
                      onLevelReached: onLevelReached,
                      character: SagaCharacter(
                        controller: character,
                        builder: (context, state) =>
                            const SizedBox.expand(key: ValueKey('hero')),
                      ),
                      nodeBuilder: (context, level, layout) =>
                          SizedBox.expand(key: ValueKey('node-${level.id}')),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(character.dispose);
      return (character, setGates);
    }

    testWidgets('a closed gate stops the walk without host wiring',
        (tester) async {
      final (character, _) =
          await pumpGated(tester, const [SagaMapGate(pathPosition: 4)]);

      unawaited(character.moveTo(8));
      await tester.pumpAndSettle();

      expect(character.pathPosition, lessThan(4));
      expect(character.pathPosition, greaterThan(3.9));
    });

    // The README recipe verbatim: an integer gate, `hasTicket == false`, and a
    // host that walks forward one level at a time. Before 2.0.0 the first
    // `advance()` landed the character *on* the gate and the second walked
    // straight through it, taking `onLevelReached` with it.
    testWidgets('an integer gate survives two consecutive advances',
        (tester) async {
      final reached = <int>[];
      final (character, _) = await pumpGated(
        tester,
        const [SagaMapGate(pathPosition: 4)],
        onLevelReached: (level) => reached.add(level.id),
      );

      unawaited(character.moveTo(3));
      await tester.pumpAndSettle();
      expect(character.pathPosition, 3);

      unawaited(character.advance());
      await tester.pumpAndSettle();
      expect(character.pathPosition, lessThan(4));

      unawaited(character.advance());
      await tester.pumpAndSettle();
      expect(character.pathPosition, lessThan(4));

      expect(reached, isNot(contains(4)));
      expect(reached, isNot(contains(5)));
    });

    testWidgets('opening the gate lets the walk through', (tester) async {
      final (character, setGates) =
          await pumpGated(tester, const [SagaMapGate(pathPosition: 4)]);

      unawaited(character.moveTo(8));
      await tester.pumpAndSettle();
      expect(character.pathPosition, lessThan(4));

      setGates(const [SagaMapGate(pathPosition: 4, isOpen: true)]);
      await tester.pumpAndSettle();

      unawaited(character.moveTo(8));
      await tester.pumpAndSettle();
      expect(character.pathPosition, 8);
    });

    testWidgets('emptying the list lifts the clamp', (tester) async {
      final (character, setGates) =
          await pumpGated(tester, const [SagaMapGate(pathPosition: 4)]);

      setGates(const <SagaMapGate>[]);
      await tester.pumpAndSettle();

      unawaited(character.moveTo(8));
      await tester.pumpAndSettle();
      expect(character.pathPosition, 8);
    });

    testWidgets('no gates is 1.x behaviour', (tester) async {
      final (character, _) = await pumpGated(tester, const <SagaMapGate>[]);
      expect(character.barrier, isNull);

      unawaited(character.moveTo(6));
      await tester.pumpAndSettle();
      expect(character.pathPosition, 6);
    });

    testWidgets('a host-installed barrier wins over the gate list',
        (tester) async {
      // An explicit barrier is assumed deliberate; the view does not overwrite
      // it, and does not tear it down on the way out either.
      final (character, _) =
          await pumpGated(tester, const [SagaMapGate(pathPosition: 4)]);
      character.barrier = (from, to) => to > 2 ? 2 : to;

      unawaited(character.moveTo(8));
      await tester.pumpAndSettle();
      expect(character.pathPosition, 2);
    });
  });
}
