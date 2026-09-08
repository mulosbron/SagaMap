import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:saga_map_example/main.dart';

/// Drives the demo through every 2.0.0 feature it exposes.
///
/// `demo_smoke_test.dart` proves the app boots and survives its toggles. This
/// file asks a narrower question: does flipping a 2.0.0 switch actually change
/// what the app does? A toggle that compiles, renders and changes nothing is
/// the failure mode a smoke test cannot see.
void main() {
  /// Boots the demo at a fixed viewport so layout is predictable.
  Future<void> bootDemo(
    WidgetTester tester, {
    Size size = const Size(420, 1000),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SagaMapDemoApp());
    await tester.pumpAndSettle();
  }

  /// Whether the modal feature sheet is currently up.
  ///
  /// Checked rather than tracked, because the "Features" button stays in the
  /// tree behind the scrim: tapping it a second time hits the barrier, not the
  /// button, and throws instead of failing an expectation.
  bool sheetIsOpen() => find.byType(BottomSheet).evaluate().isNotEmpty;

  Future<void> openSheet(WidgetTester tester) async {
    if (sheetIsOpen()) return;
    await tester.tap(find.text('Features'));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    if (!sheetIsOpen()) return;
    // Tap the scrim above the sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  /// Opens the feature sheet and flips the switch labelled [label].
  ///
  /// Three things this has to get right, each of which silently produced a
  /// no-op tap while it was wrong:
  ///
  /// - Scroll the **sheet's** list, not the map behind it. `Scrollable.last`
  ///   is whichever happens to be deepest, which is not reliably the sheet.
  /// - Target the `SwitchListTile`, not its `Text`. A label scrolled to the
  ///   very edge is hit-testable at its centre but the text inside it may not
  ///   be, and `tap` then warns and does nothing.
  /// - `ensureVisible` after scrolling, so the tile is fully on screen rather
  ///   than merely reached.
  Future<void> tapInSheet(WidgetTester tester, String label) async {
    await openSheet(tester);

    final tile = find.widgetWithText(SwitchListTile, label);
    final sheetList = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(tile, 120, scrollable: sheetList.first);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  /// Reads the live view out of the tree, which is where the demo's wiring
  /// becomes observable without reaching into its private state.
  SagaInfiniteMapView mapView(WidgetTester tester) =>
      tester.widget<SagaInfiniteMapView>(find.byType(SagaInfiniteMapView));

  group('gates block progression (120)', () {
    testWidgets('the view carries the demo gate, closed by default',
        (tester) async {
      await bootDemo(tester);

      final gates = mapView(tester).gates;
      expect(gates, hasLength(1));
      expect(gates.single.isOpen, isFalse);
    });

    testWidgets('opening the gate flips it in the view', (tester) async {
      await bootDemo(tester);
      await tapInSheet(tester, 'Gate closed at level 12');

      expect(mapView(tester).gates.single.isOpen, isTrue);
    });

    testWidgets('a node past a closed gate is refused by the policy',
        (tester) async {
      await bootDemo(tester);
      final policy = mapView(tester).interactionPolicy;

      // The same predicate drives all three consumers, so testing it through
      // the policy tests the whole gate.
      const unlocked =
          LevelProgress(levelId: 0, state: LevelCompletionState.unlocked);
      LevelData at(int id) =>
          LevelData(id: id, position: const SagaPoint(0.5, 0), biomeId: 'x');

      expect(policy.canTap(at(11), unlocked), isTrue);
      expect(policy.canTap(at(12), unlocked), isFalse);
      expect(policy.canTap(at(40), unlocked), isFalse);
      // A long press is refused with it.
      expect(policy.canLongPress(at(12), unlocked), isFalse);
    });

    testWidgets('opening the gate makes the far side reachable again',
        (tester) async {
      await bootDemo(tester);
      await tapInSheet(tester, 'Gate closed at level 12');

      const unlocked =
          LevelProgress(levelId: 0, state: LevelCompletionState.unlocked);
      expect(
        mapView(tester).interactionPolicy.canTap(
              const LevelData(
                  id: 20, position: SagaPoint(0.5, 0), biomeId: 'x'),
              unlocked,
            ),
        isTrue,
      );
    });
  });

  group('host-defined biomes (130)', () {
    /// The biome ids the loaded chunks actually carry.
    ///
    /// Read off the controller rather than inferred from the status text: the
    /// question is what the generator produced, and a status line can agree
    /// with a toggle while the config behind it never moved.
    Set<String> generatedBiomeIds(WidgetTester tester) {
      final controller = mapView(tester).controller;
      return {
        for (final index in controller.retainedChunkIndices)
          for (final level in controller.chunkLevels(index)) level.biomeId,
      };
    }

    testWidgets('the demo starts on the package biome ids', (tester) async {
      await bootDemo(tester);

      final ids = generatedBiomeIds(tester);
      expect(ids, isNotEmpty);
      expect(ids.every(kSagaBiomeIds.contains), isTrue, reason: '$ids');
    });

    testWidgets('switching to host realms regenerates with the demo ids',
        (tester) async {
      await bootDemo(tester);
      await tapInSheet(tester, 'Host realms');

      final ids = generatedBiomeIds(tester);
      expect(ids, isNotEmpty);
      // Ids the package has never heard of, produced by the package's own
      // generator. That is the whole of ADR-0007 in one assertion.
      expect(ids.any(kSagaBiomeIds.contains), isFalse, reason: '$ids');
      expect(ids.every((id) => id.isNotEmpty), isTrue);

      await closeSheet(tester);
      expect(find.textContaining('host realms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching back returns to the built-in ids', (tester) async {
      await bootDemo(tester);
      await tapInSheet(tester, 'Host realms');
      await tapInSheet(tester, 'Host realms');

      expect(generatedBiomeIds(tester).every(kSagaBiomeIds.contains), isTrue);

      await closeSheet(tester);
      expect(find.textContaining('built-in biome ids'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the realms cycle faster than the built-in span',
        (tester) async {
      // biomeSpan drops from 50 to 10 with the demo's realms, so a map that
      // showed one biome across its first chunks now shows several.
      await bootDemo(tester);
      final builtIn = generatedBiomeIds(tester);

      await tapInSheet(tester, 'Host realms');
      final realms = generatedBiomeIds(tester);

      expect(realms.length, greaterThan(builtIn.length));
    });
  });

  group('injectable rewards (110)', () {
    testWidgets('custom rewards can be switched on and off', (tester) async {
      await bootDemo(tester);

      await tapInSheet(tester, 'Custom rewards');
      expect(tester.takeException(), isNull);

      await tapInSheet(tester, 'Custom rewards');
      expect(tester.takeException(), isNull);
      expect(find.byType(SagaInfiniteMapView), findsOneWidget);
    });
  });

  group('the map still works with every 2.0.0 toggle on', () {
    testWidgets('realms, custom rewards and an open gate together',
        (tester) async {
      await bootDemo(tester);

      await tapInSheet(tester, 'Host realms');
      await tapInSheet(tester, 'Custom rewards');
      await tapInSheet(tester, 'Gate closed at level 12');

      await closeSheet(tester);

      expect(find.byType(SagaInfiniteMapView), findsOneWidget);
      expect(mapView(tester).gates.single.isOpen, isTrue);
      expect(tester.takeException(), isNull);

      // And the map is still interactive: walking to an adjacent level lands.
      await tester.tap(find.text('1'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
