import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Closed gates hold the character on the near side; open ones are inert.

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
  group('clampTravelThroughGates', () {
    test('a closed gate stops a forward move on its near side', () {
      const gates = [SagaMapGate(pathPosition: 5)];
      final reached = clampTravelThroughGates(gates, 2, 9);
      expect(reached, lessThan(5));
      expect(reached, greaterThan(4.9));
    });

    test('an open gate does not block', () {
      const gates = [SagaMapGate(pathPosition: 5, isOpen: true)];
      expect(clampTravelThroughGates(gates, 2, 9), 9);
    });

    test('only the first gate in the way matters', () {
      const gates = [
        SagaMapGate(pathPosition: 8),
        SagaMapGate(pathPosition: 5),
      ];
      final reached = clampTravelThroughGates(gates, 2, 12);
      expect(reached, lessThan(5));
    });

    test('a gate behind the move is ignored', () {
      const gates = [SagaMapGate(pathPosition: 1)];
      expect(clampTravelThroughGates(gates, 2, 9), 9);
    });

    test('a gate ahead of the start does not block a backward move', () {
      // Gate at 10 is forward of the start; walking back to 2 never meets it.
      const gates = [SagaMapGate(pathPosition: 10)];
      expect(clampTravelThroughGates(gates, 8, 2), 2);
    });

    test('a closed gate blocks a backward move too', () {
      const gates = [SagaMapGate(pathPosition: 5)];
      final reached = clampTravelThroughGates(gates, 8, 2);
      expect(reached, greaterThan(5));
      expect(reached, lessThan(5.1));
    });

    test('standing on a gate is not pushed', () {
      const gates = [SagaMapGate(pathPosition: 5)];
      expect(clampTravelThroughGates(gates, 5, 5), 5);
    });

    test('no gates leaves the target alone', () {
      expect(clampTravelThroughGates(const [], 2, 9), 9);
    });

    test('gates compare by value', () {
      expect(
        const SagaMapGate(pathPosition: 5),
        const SagaMapGate(pathPosition: 5),
      );
      expect(
        const SagaMapGate(pathPosition: 5).hashCode,
        const SagaMapGate(pathPosition: 5, isOpen: false).hashCode,
      );
      expect(
        const SagaMapGate(pathPosition: 5),
        isNot(const SagaMapGate(pathPosition: 5, isOpen: true)),
      );
    });
  });

  group('controller barrier', () {
    testWidgets('a closed gate halts a walk before it', (tester) async {
      late SagaCharacterController controller;
      const gates = [SagaMapGate(pathPosition: 4)];
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 30),
              stepPause: Duration.zero,
              barrier: (from, to) => clampTravelThroughGates(gates, from, to),
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.moveTo(9));
      await tester.pumpAndSettle();

      // Reached the gate's near side and no further.
      expect(controller.pathPosition, lessThan(4));
      expect(controller.pathPosition, greaterThan(3.9));
    });

    testWidgets('opening the gate lets the walk through', (tester) async {
      late SagaCharacterController controller;
      var open = false;
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 20),
              stepPause: Duration.zero,
              barrier: (from, to) => clampTravelThroughGates(
                [SagaMapGate(pathPosition: 4, isOpen: open)],
                from,
                to,
              ),
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.moveTo(9));
      await tester.pumpAndSettle();
      expect(controller.pathPosition, lessThan(4));

      open = true;
      unawaited(controller.moveTo(9));
      await tester.pumpAndSettle();
      expect(controller.pathPosition, 9);
    });

    testWidgets('a gate does not block a move that ends before it',
        (tester) async {
      late SagaCharacterController controller;
      const gates = [SagaMapGate(pathPosition: 8)];
      await tester.pumpWidget(
        _TickerHost(
          build: (context, vsync) {
            controller = SagaCharacterController(
              vsync: vsync,
              stepDuration: const Duration(milliseconds: 20),
              stepPause: Duration.zero,
              barrier: (from, to) => clampTravelThroughGates(gates, from, to),
            );
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(controller.dispose);

      unawaited(controller.moveTo(5));
      await tester.pumpAndSettle();
      expect(controller.pathPosition, 5);
    });
  });
}
