import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';
import 'package:saga_map_example/main.dart';

/// Proves the demo actually runs, rather than merely compiling: it boots, draws
/// a map, responds to a tap by walking the character, and survives switching
/// every feature toggle.
void main() {
  /// Boots the demo at a fixed viewport so layout is predictable.
  Future<void> bootDemo(WidgetTester tester,
      {Size size = const Size(420, 860)}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SagaMapDemoApp());
    await tester.pumpAndSettle();
  }

  testWidgets('the demo boots and draws a map', (tester) async {
    await bootDemo(tester);

    expect(find.byType(SagaInfiniteMapView), findsOneWidget);
    expect(find.text('Tap a level to walk there'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a level walks the character and completes it',
      (tester) async {
    await bootDemo(tester);

    // Level 1 is adjacent to the start, so the walk is short and ungated.
    await tester.tap(find.text('1'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the feature sheet opens and every toggle is reachable',
      (tester) async {
    await bootDemo(tester, size: const Size(420, 1000));

    await tester.tap(find.text('Features'));
    await tester.pumpAndSettle();

    // A representative control from each section of the sheet.
    expect(find.text('Vertical'), findsOneWidget);
    expect(find.text('Light up the walked path'), findsOneWidget);
    expect(find.text('Sprite sheet'), findsOneWidget);
    expect(find.text('Decorations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to a horizontal map keeps the demo alive',
      (tester) async {
    await bootDemo(tester, size: const Size(900, 620));

    await tester.tap(find.text('Features'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Horizontal'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Dismiss the sheet by tapping the scrim above it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(SagaInfiniteMapView), findsOneWidget);
  });

  testWidgets('toggling scenery, headers and parallax does not throw',
      (tester) async {
    await bootDemo(tester, size: const Size(420, 1000));

    await tester.tap(find.text('Features'));
    await tester.pumpAndSettle();

    for (final label in const [
      'Decorations',
      'Episode headers',
      'Parallax background',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('the plain-Flutter character swaps in for the sprite sheet',
      (tester) async {
    await bootDemo(tester, size: const Size(420, 1000));

    await tester.tap(find.text('Features'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Widget'));
    await tester.pumpAndSettle();

    // The library only reports state; the host swaps the art freely.
    expect(find.byIcon(Icons.directions_walk), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
