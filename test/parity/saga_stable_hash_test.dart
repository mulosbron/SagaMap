@Tags(['platform-parity'])
library;

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

    // Every vector above was under 10,000, so the one line that actually needed
    // 64-bit shift semantics was never exercised. `hash ^ ((value >> 32) & …)`
    // has no 64-bit meaning on the web: before the fix, `stableHash([2^32])`
    // returned 1284044959 on the Dart VM and 851875910 under dart2js/Node. A
    // seed minted from `DateTime.now().millisecondsSinceEpoch` is ~2^40.7, so
    // the same seed built a different world on web than on native, and web
    // seeds ~49.7 days apart aliased onto one world.
    //
    // Note the inputs below are integer *literals*, not `1 << 32`: a shift
    // count of 32 has no meaning on the web either (dart2js uses JavaScript
    // shift semantics, so `1 << 32` itself collapses to `1` there), so the
    // literals are what make the two runtimes see the same input. The values
    // were captured on both runtimes and must stay equal on both;
    // `dart_test.yaml` runs this suite under `chrome` as well as `vm`.
    test('matches its reference values above 2^32', () {
      expect(stableHash([4294967296]), 538560542); // 2^32
      expect(stableHash([4294967297]), 2936534305); // 2^32 + 1
      expect(stableHash([1099511627776]), 3662924666); // 2^40
      // A realistic `DateTime.now().millisecondsSinceEpoch`.
      expect(stableHash([1757203200000]), 3430044811);
      expect(stableHash([4294967296, 7]), 1463335543);
    });

    test('seeds exactly 2^32 apart do not collide', () {
      const seed = 1757203200000;
      expect(stableHash([seed]), isNot(stableHash([seed + 4294967296])));
      expect(stableHash([seed + 4294967296]), 2520830661);
      expect(stableHash([0]), isNot(stableHash([4294967296])));
    });

    test('negative values hash stably and do not alias their magnitude', () {
      expect(stableHash([-42]), 3818627525);
      expect(stableHash([-4294967296]), 1112350902);
      expect(stableHash([-42]), isNot(stableHash([42])));
    });

    // A-07.01. Everything above is either negative *or* above 2^32, never
    // both, and never mixed inside one call. The sign is carried by taking the
    // magnitude before the high-word fold, so a vector that is negative *and*
    // large is the only one that exercises the two together — and a mixed
    // list checks that a sign salt from one value does not leak into the next.
    //
    // What no test here can do is tell `magnitude >> 32` from
    // `magnitude ~/ 0x100000000`. On the Dart VM those are the same expression:
    // `magnitude` is non-negative by construction, and for non-negative
    // 64-bit ints an arithmetic shift and integer division agree exactly. The
    // difference only exists under dart2js, where a shift count of 32 has no
    // meaning. **That half of the fix is verifiable only under Chrome**, which
    // is what the `platform-parity` tag on this library and the web job in CI
    // are for; it cannot be checked locally. Reverting the sign handling,
    // however, turns this suite red on the VM — verified by hand.
    test('negative and above 2^32 at the same time', () {
      expect(stableHash([-4294967297]), 861595412); // -(2^32 + 1)
      expect(stableHash([-1099511627776]), 4239139107); // -2^40
      expect(stableHash([-1757203200000]), 4255135428); // a negated timestamp

      // Sign is per value, not per call: these differ from each other and from
      // the all-positive vector with the same magnitudes.
      expect(stableHash([4294967296, -4294967296]), 3849804774);
      expect(stableHash([-42, 4294967296]), 2175706753);
      expect(stableHash([0, -1]), 3842415898);

      expect(
        stableHash([4294967296, -4294967296]),
        isNot(stableHash([-4294967296, 4294967296])),
        reason: 'the sign salt must not be order-insensitive',
      );
      expect(
        stableHash([-4294967297]),
        isNot(stableHash([4294967297])),
        reason: 'a large negative must not alias its magnitude',
      );
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
      final values = <int>{
        for (var i = 0; i < 500; i++) stableHash([42, i])
      };
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
