import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:saga_map_example/main.dart';

/// Drives the demo through the 2.1.0 economy.
///
/// Same question `demo_2_0_0_test.dart` asks of its own features: does using
/// a control actually change what the app does, observed through the live view
/// and the status line rather than the demo's private state?
void main() {
  Future<void> bootDemo(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 1000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SagaMapDemoApp());
    await tester.pumpAndSettle();
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

  /// Scrolls the sheet's own list to [target] and taps it.
  Future<void> tapInSheet(WidgetTester tester, Finder target) async {
    await openSheet(tester);
    final sheetList = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(target, 120, scrollable: sheetList.first);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Walks to the node labelled [label] and lets the completion land.
  Future<void> play(WidgetTester tester, String label) async {
    await tester.tap(find.text(label), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  SagaInfiniteMapView mapView(WidgetTester tester) =>
      tester.widget<SagaInfiniteMapView>(find.byType(SagaInfiniteMapView));

  LevelProgress? progressAt(WidgetTester tester, int id) =>
      mapView(tester).progressResolver!(
        LevelData(id: id, position: const SagaPoint(0.5, 0), biomeId: 'x'),
      );

  group('the Economy section', () {
    testWidgets('every 2.1.0 control is reachable', (tester) async {
      await bootDemo(tester);

      await tapInSheet(
        tester,
        find.widgetWithText(SwitchListTile, 'Pity rule'),
      );
      expect(find.text('Hard replay'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Pay the toll'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('replay modes (230)', () {
    testWidgets('a hard run scores apart and unlocks nothing', (tester) async {
      await bootDemo(tester);

      await play(tester, '1');
      expect(progressAt(tester, 0)?.stars, 1);
      expect(progressAt(tester, 1)?.state, LevelCompletionState.unlocked);

      await tapInSheet(tester, find.text('Hard replay'));
      await closeSheet(tester);
      await play(tester, '2');

      expect(find.textContaining('Hard run on level 1'), findsOneWidget);
      // The hard score sits beside the normal one...
      expect(progressAt(tester, 1)?.starsFor('hard'), 2);
      expect(progressAt(tester, 1)?.stars, 0);
      // ...and the level stays exactly as reachable as it was.
      expect(progressAt(tester, 1)?.state, LevelCompletionState.unlocked);
      expect(progressAt(tester, 2), isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('star economy (220)', () {
    testWidgets('the toll refuses a player short of stars', (tester) async {
      await bootDemo(tester);

      await tapInSheet(tester, find.widgetWithText(ListTile, 'Pay the toll'));
      await closeSheet(tester);

      expect(find.textContaining('The toll is 5★'), findsOneWidget);
      expect(mapView(tester).gates.single.isOpen, isFalse);
    });

    testWidgets('earned stars pay the toll and open the gate', (tester) async {
      await bootDemo(tester);

      // One, two and three stars: six earned.
      await play(tester, '1');
      await play(tester, '2');
      await play(tester, '3');

      await tapInSheet(tester, find.widgetWithText(ListTile, 'Pay the toll'));
      await closeSheet(tester);

      expect(find.textContaining('Paid 5★'), findsOneWidget);
      expect(find.textContaining('★ 1/6'), findsOneWidget);
      expect(mapView(tester).gates.single.isOpen, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('pity and reward persistence (200, 210)', () {
    testWidgets('a boss drop is written to the injected inventory',
        (tester) async {
      await bootDemo(tester);

      await tapInSheet(
        tester,
        find.widgetWithText(SwitchListTile, 'Custom rewards'),
      );
      await tapInSheet(
        tester,
        find.widgetWithText(SwitchListTile, 'Pity rule'),
      );
      await closeSheet(tester);

      // A boss every fifth level here, so the fifth node drops.
      for (final label in ['1', '2', '3', '4', '5']) {
        await play(tester, label);
      }

      expect(find.textContaining('Boss cleared'), findsOneWidget);
      // Read back from the repository, not appended by the demo.
      expect(find.textContaining('items 1'), findsOneWidget);

      // The level dialog reports the counter the rule moved.
      await tester.longPress(find.text('5'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Pity:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
