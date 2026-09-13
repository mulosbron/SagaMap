import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saga_map_example/main.dart';

/// Captures the demo's 2.1.0 economy on a real device, for `README.md`.
///
/// Photographs, not goldens: see `screenshot_test.dart` for why both exist.
/// Run from `example/` with a device booted:
///
/// ```bash
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/screenshot_2_1_0_test.dart \
///   -d emulator-5554
/// ```
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  var surfaceConverted = false;
  Future<void> shoot(WidgetTester tester, String name) async {
    // Android draws Flutter into a SurfaceView, which `screencap` returns as a
    // black rectangle; this swaps it for a capturable view, once.
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

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await openSheet(tester);
    final sheetList = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, 120, scrollable: sheetList);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapInSheet(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Walks to each labelled node in turn; a real walk runs on a real vsync.
  Future<void> play(WidgetTester tester, Iterable<String> labels) async {
    for (final label in labels) {
      final node = find.text(label);
      if (node.evaluate().isEmpty) break;
      await tester.tap(node, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    }
  }

  testWidgets('2.1.0 demo screenshots', (tester) async {
    await tester.pumpWidget(const SagaMapDemoApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Earn some stars on the normal game: 1 + 2 + 3 + 1.
    await play(tester, ['1', '2', '3', '4']);

    // 1. Replay modes (230). The first three levels replayed on hard: each
    //    gets a red ring, its normal stars stay inside, and nothing past the
    //    frontier opens.
    await tapInSheet(tester, find.text('Hard replay'));
    await closeSheet(tester);
    await play(tester, ['3', '2', '1']);
    await shoot(tester, 'demo_2_1_0_replay_modes');

    // 2. Both scores for one level, side by side, in the long-press dialog.
    await tester.longPress(find.text('2'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await shoot(tester, 'demo_2_1_0_level_scores');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // 3. The star economy (220): five of the seven stars spent on the toll,
    //    and the gate that held the character is open.
    await tapInSheet(tester, find.text('Normal'));
    await tapInSheet(tester, find.widgetWithText(ListTile, 'Pay the toll'));
    await closeSheet(tester);
    await shoot(tester, 'demo_2_1_0_star_toll');

    // 4. The Economy section, with the pity rule switched on (200).
    await tapInSheet(tester, find.widgetWithText(SwitchListTile, 'Pity rule'));
    await reveal(tester, find.widgetWithText(ListTile, 'Pay the toll'));
    await shoot(tester, 'demo_2_1_0_feature_sheet');
    await closeSheet(tester);

    expect(tester.takeException(), isNull);
  });
}
