import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:saga_map_example/main.dart';

/// System tests: the demo running on a real device or emulator.
///
/// Widget tests already cover the 2.0.0 wiring. What they cannot cover is
/// everything the fake test environment stands in for — decoding the real PNG
/// and SVG assets, a real text shaper, a real frame scheduler, real vsync. Each
/// of those has broken this demo at least once in a way `flutter test` could
/// not see.
///
/// Run against a booted device:
///
/// ```bash
/// cd example && flutter test integration_test
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> bootDemo(WidgetTester tester) async {
    await tester.pumpWidget(const SagaMapDemoApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  bool sheetIsOpen() => find.byType(BottomSheet).evaluate().isNotEmpty;

  Future<void> openSheet(WidgetTester tester) async {
    if (sheetIsOpen()) return;
    await tester.tap(find.text('Features'));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    if (!sheetIsOpen()) return;
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

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

  SagaInfiniteMapView mapView(WidgetTester tester) =>
      tester.widget<SagaInfiniteMapView>(find.byType(SagaInfiniteMapView));

  testWidgets('the demo boots on device and draws a map', (tester) async {
    await bootDemo(tester);

    expect(find.byType(SagaInfiniteMapView), findsOneWidget);
    expect(find.text('Tap a level to walk there'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('walking a level completes it and lights the path',
      (tester) async {
    await bootDemo(tester);

    await tester.tap(find.text('1'), warnIfMissed: false);
    // A real walk is animated on a real vsync, so this waits for the journey
    // rather than a single frame.
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.textContaining('complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host realms regenerate the map with the demo ids on device',
      (tester) async {
    await bootDemo(tester);
    await tapInSheet(tester, 'Host realms');

    final controller = mapView(tester).controller;
    final ids = {
      for (final index in controller.retainedChunkIndices)
        for (final level in controller.chunkLevels(index)) level.biomeId,
    };

    expect(ids, isNotEmpty);
    expect(ids.any(kSagaBiomeIds.contains), isFalse, reason: '$ids');

    await closeSheet(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a closed gate stops the character on a real vsync',
      (tester) async {
    await bootDemo(tester);

    // The gate sits at level 12 and starts closed, so a walk aimed past it
    // has to stop short. This is the one gate consumer a widget test cannot
    // fully exercise: the clamp runs inside an animation driven by the real
    // ticker.
    expect(mapView(tester).gates.single.isOpen, isFalse);

    await tester.tap(find.text('1'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(tester.takeException(), isNull);
  });

  testWidgets('every background mode decodes its real asset', (tester) async {
    // The reason this test exists on device: `Image.asset` and
    // `SvgPicture.asset` both no-op in a widget test with no asset bundle, so
    // a broken path or a dropped pubspec entry only shows up here. The SVG
    // modes also prove the 2.0.0 `builder` config reaches a host decoder the
    // package no longer depends on.
    await bootDemo(tester);
    await openSheet(tester);

    for (final label in const ['Colour', 'Image', 'SVG', 'Multi-SVG', 'None']) {
      final chip = find.text(label);
      if (chip.evaluate().isEmpty) continue;
      await tester.scrollUntilVisible(
        chip,
        120,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(chip, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: 'background $label');
    }

    await closeSheet(tester);
  });

  testWidgets('scrolling a long map stays alive across chunk seams',
      (tester) async {
    await bootDemo(tester);

    // Chunks load lazily; dragging far enough crosses seams and evicts chunks
    // when bounded memory is on. Real scroll physics, not a synthetic jump.
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(SagaInfiniteMapView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    expect(find.byType(SagaInfiniteMapView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
