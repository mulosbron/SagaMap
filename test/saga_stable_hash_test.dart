import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// These reference values are the contract.
///
/// A generated map is regenerated from its seed on every launch, so the hash
/// backing it must never change — not across runs, not across platforms, not
/// across releases of this package. `Object.hash` looked adequate and was not:
/// it folds in `identityHashCode(Object)`, which is randomised per run, so a
/// player's map silently rearranged itself on every restart.
///
/// If a change here forces these numbers to move, it is a breaking change to
/// every persisted map.
void main() {
  group('stableHash', () {
    test('matches its reference values', () {
      expect(stableHash([0]), 2886220781);
      expect(stableHash([42, 7]), 991453709);
      expect(stableHash([1, 2, 3]), 4105803690);
    });

    test('stays inside 32 bits', () {
      for (var i = 0; i < 2000; i++) {
        final hash = stableHash([i, i * 7919]);
        expect(hash, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('is stable within a run', () {
      expect(stableHash([42, 7]), stableHash([42, 7]));
      expect(stableUnitValue([9, 9]), stableUnitValue([9, 9]));
    });

    test('separates inputs that differ only by order', () {
      expect(stableHash([1, 2]), isNot(stableHash([2, 1])));
    });

    test('separates neighbouring level ids', () {
      final values = <int>{for (var i = 0; i < 500; i++) stableHash([42, i])};
      // A weak mix would collide constantly across consecutive ids.
      expect(values.length, 500);
    });

    test('spreads unit values across the range', () {
      final buckets = List<int>.filled(10, 0);
      for (var i = 0; i < 10000; i++) {
        final value = stableUnitValue([42, i]);
        expect(value, inInclusiveRange(0.0, 1.0));
        buckets[(value * 10).floor().clamp(0, 9)]++;
      }
      for (final count in buckets) {
        expect(count, greaterThan(700), reason: 'buckets: $buckets');
      }
    });
  });

  test('generated positions match their reference values', () {
    const generator = SagaMapLevelGenerator();
    final levels = generator.generateLevels(
      globalSeed: 42,
      config: SagaMapConfig.defaultConfig,
      startLevelId: 0,
      count: 3,
    );

    expect(levels[0].position.x, closeTo(0.3399703967478126, 1e-15));
    expect(levels[1].position.x, closeTo(0.5984794917423278, 1e-15));
    expect(levels[2].position.x, closeTo(0.32122614209540185, 1e-15));
  });

  test('puzzle seeds are stable across versions', () {
    expect(
      puzzleSeedForLevel(42, 10, 1),
      puzzleSeedForLevel(42, 10, 1),
    );
    expect(
      puzzleSeedForLevel(42, 10, 1),
      isNot(puzzleSeedForLevel(42, 10, 2)),
    );
    expect(
      puzzleSeedForLevelWithDefaultVersion(42, 10),
      puzzleSeedForLevel(42, 10, kPuzzleVersion),
    );
  });
}
