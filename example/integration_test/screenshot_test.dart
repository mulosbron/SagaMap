import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:saga_map_example/main.dart';

/// Captures the demo on a real device, one screenshot per 2.0.0 feature.
///
/// These are the images `README.md` shows. Unlike the goldens under
/// `test/golden/`, they are photographs of the app rather than of a synthetic
/// chunk: real assets, real fonts, real device pixel ratio. They are not
/// compared against anything, so a device or a font change moves them without
/// failing a test — which is exactly why the goldens exist alongside.
///
/// Run from `example/` with a device booted:
///
/// ```bash
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/screenshot_test.dart \
///   -d emulator-5554
/// ```
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> bootDemo(WidgetTester tester) async {
    await tester.pumpWidget(const SagaMapDemoApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Renders the Flutter surface into something capturable.
  ///
  /// Android draws Flutter into a SurfaceView, which `screencap` comes back
  /// from as a black rectangle. This swaps it for an ImageView first. It is a
  /// no-op elsewhere, and calling it twice throws, so it is guarded.
  var surfaceConverted = false;
  Future<void> shoot(WidgetTester tester, String name) async {
    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
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

  Finder sheetList() => find
      .descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> tapInSheet(WidgetTester tester, String label) async {
    await openSheet(tester);
    final tile = find.widgetWithText(SwitchListTile, label);
    await tester.scrollUntilVisible(tile, 120, scrollable: sheetList());
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  /// Picks a background mode from the chip row.
  ///
  /// The realm shots use `None`, which is the only mode that lets the biome's
  /// own background through: every other mode draws a host layer over it, and
  /// the point of these images is the colour the biome resolved to.
  Future<void> pickBackground(WidgetTester tester, String label) async {
    await openSheet(tester);
    final chip = find.text(label);
    await tester.scrollUntilVisible(chip, 120, scrollable: sheetList());
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  /// Walks a few levels so the path behind the character is lit and the nodes
  /// are not uniformly locked grey.
  Future<void> playAFewLevels(WidgetTester tester, int count) async {
    for (var i = 1; i <= count; i++) {
      final node = find.text('$i');
      if (node.evaluate().isEmpty) break;
      await tester.tap(node, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    }
  }

  testWidgets('2.0.0 demo screenshots', (tester) async {
    await bootDemo(tester);

    // 1. The demo as it opens: the host's own background artwork, built-in
    //    biome ids, gate closed at level 12.
    await shoot(tester, 'demo_2_0_0_default');

    // Light the first few nodes, so every later shot shows progress rather
    // than a column of locked grey circles.
    await playAFewLevels(tester, 4);
    await shoot(tester, 'demo_2_0_0_walked_path');

    // 2. Injectable rewards (110): a boss every fifth level instead of the
    //    package's fifteenth, rolling the demo's own loot table. The square
    //    nodes are the bosses the injected rule picked.
    await tapInSheet(tester, 'Custom rewards');
    await closeSheet(tester);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await shoot(tester, 'demo_2_0_0_custom_rewards');

    // 3. Host-defined biome ids (130). Five realms, ten levels each, none of
    //    which the package ships a theme for. Background off, so the biome's
    //    own colour and its ambient wash are what you see; the letter on each
    //    node comes back out of the opaque `SagaBiomeTheme.assets` map.
    await tapInSheet(tester, 'Host realms');
    await pickBackground(tester, 'None');
    await closeSheet(tester);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await shoot(tester, 'demo_2_0_0_host_realms');

    // 4. Scrolled past the tenth level, where the realm turns over — which is
    //    what a ten-level `biomeSpan` buys over the built-in fifty.
    for (var i = 0; i < 5; i++) {
      await tester.drag(
          find.byType(SagaInfiniteMapView), const Offset(0, -420));
      await tester.pumpAndSettle();
    }
    await shoot(tester, 'demo_2_0_0_realm_cycle');

    // 5. The same view with the package's three ids, for comparison: one
    //    biome across the whole stretch, because the built-in span is fifty.
    await tapInSheet(tester, 'Host realms');
    await closeSheet(tester);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await shoot(tester, 'demo_2_0_0_builtin_biomes');

    // 6. The feature sheet, scrolled to the 2.0.0 switches.
    await openSheet(tester);
    final realms = find.widgetWithText(SwitchListTile, 'Host realms');
    await tester.scrollUntilVisible(realms, 120, scrollable: sheetList());
    await tester.pumpAndSettle();
    await shoot(tester, 'demo_2_0_0_feature_sheet');
    await closeSheet(tester);

    expect(tester.takeException(), isNull);
  });
}
