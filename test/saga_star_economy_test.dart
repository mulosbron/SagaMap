import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Six stars earned across three completed levels, plus an unlocked one whose
/// stars must not count.
SagaProgress _earnedSix({int spent = 0}) => SagaProgress(
      currentMaxUnlockedLevelId: 3,
      levels: {
        0: const LevelProgress(
          levelId: 0,
          state: LevelCompletionState.completed,
          stars: 3,
        ),
        1: const LevelProgress(
          levelId: 1,
          state: LevelCompletionState.completed,
          stars: 2,
        ),
        2: const LevelProgress(
          levelId: 2,
          state: LevelCompletionState.completed,
          stars: 1,
        ),
        3: const LevelProgress(
            levelId: 3, state: LevelCompletionState.unlocked),
      },
      spentStars: spent,
    );

Map<String, dynamic> _payload(Object? spentStars) => {
      'currentMaxUnlockedLevelId': 2,
      'levels': {
        '0': {'levelId': 0, 'state': 'completed', 'stars': 3},
        '1': {'levelId': 1, 'state': 'completed', 'stars': 2},
        '2': {'levelId': 2, 'state': 'unlocked', 'stars': 0},
      },
      'spentStars': spentStars,
    };

void main() {
  group('220.14 — spending', () {
    test('spending lowers availableStars and leaves totalStars alone', () {
      final progress = _earnedSix();
      expect(progress.totalStars, 6);
      expect(progress.availableStars, 6);

      final next = progress.spendStars(4)!;
      expect(next.spentStars, 4);
      expect(next.availableStars, 2);
      expect(next.totalStars, 6);

      // The original is a value: spending returned a new one.
      expect(progress.spentStars, 0);
      expect(progress.availableStars, 6);
    });

    test('everything earned can be spent, down to zero', () {
      final broke = _earnedSix().spendStars(6)!;
      expect(broke.availableStars, 0);
    });

    test('spending carries every other field through', () {
      final progress = _earnedSix().copyWith(extra: {'app.chests': 2});
      final next = progress.spendStars(1)!;
      expect(next.levels, progress.levels);
      expect(next.extra, progress.extra);
      expect(
        next.currentMaxUnlockedLevelId,
        progress.currentMaxUnlockedLevelId,
      );
    });
  });

  group('220.15 — too few stars', () {
    test('an overdraw returns null and changes nothing', () {
      final progress = _earnedSix(spent: 5);
      expect(progress.spendStars(2), isNull);
      expect(progress.spendStars(1)?.availableStars, 0);
      expect(progress.spentStars, 5);
    });

    test('spending nothing, or a negative amount, is a caller error', () {
      final progress = _earnedSix();
      expect(() => progress.spendStars(0), throwsArgumentError);
      expect(() => progress.spendStars(-3), throwsArgumentError);
    });

    test('the constructor refuses an impossible ledger', () {
      expect(() => _earnedSix(spent: -1), throwsArgumentError);
      expect(() => _earnedSix(spent: 7), throwsArgumentError);
      expect(_earnedSix(spent: 6).availableStars, 0);
    });

    test('replacing the levels with fewer stars than were spent throws', () {
      final progress = _earnedSix(spent: 4);
      expect(
        () => progress.copyWith(levels: SagaProgress.initial().levels),
        throwsArgumentError,
      );
    });

    test('alternate-mode stars are not spendable', () {
      // Mode scores are not part of totalStars, so they cannot fund a spend.
      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 1,
        levels: {
          0: const LevelProgress(
            levelId: 0,
            state: LevelCompletionState.completed,
            stars: 1,
            starsByMode: {'hard': 3, 'mirror': 3},
          ),
        },
      );
      expect(progress.totalStars, 1);
      expect(progress.spendStars(2), isNull);
    });
  });

  group('220.16 — a tampered save is clamped', () {
    test('a negative spentStars loads as zero', () {
      final progress = SagaProgress.fromJson(_payload(-40));
      expect(progress.spentStars, 0);
      expect(progress.availableStars, 5);
    });

    test('spentStars above the stars earned loads as the total', () {
      final progress = SagaProgress.fromJson(_payload(999));
      expect(progress.spentStars, 5);
      expect(progress.availableStars, 0);
    });

    test('a wrong-typed spentStars loads as zero', () {
      expect(SagaProgress.fromJson(_payload('lots')).spentStars, 0);
      expect(SagaProgress.fromJson(_payload(true)).spentStars, 0);
      expect(SagaProgress.fromJson(_payload(2.9)).spentStars, 2);
    });

    test('availableStars is never negative, whatever was stored', () {
      for (final stored in [-1000, -1, 0, 1, 5, 6, 1000, 'x', null]) {
        expect(
          SagaProgress.fromJson(_payload(stored)).availableStars,
          greaterThanOrEqualTo(0),
          reason: 'spentStars: $stored',
        );
      }
    });

    test('a clamp costs no other field', () {
      final progress = SagaProgress.fromJson(_payload(999));
      expect(progress.currentMaxUnlockedLevelId, 2);
      expect(progress.levels[0]?.stars, 3);
    });
  });

  group('220.17 — the 2.0.0 format', () {
    test('a save with no spentStars key loads with nothing spent', () {
      final json = _payload(null)..remove('spentStars');
      final progress = SagaProgress.fromJson(json);
      expect(progress.spentStars, 0);
      expect(progress.availableStars, 5);
    });

    test('toJson omits spentStars at zero', () {
      expect(_earnedSix().toJson().containsKey('spentStars'), isFalse);
    });

    test('a non-zero spend is written and survives the round trip', () {
      final progress = _earnedSix(spent: 4);
      expect(progress.toJson()['spentStars'], 4);

      final reloaded = SagaProgress.fromJson(progress.toJson());
      expect(reloaded.spentStars, 4);
      expect(reloaded, progress);
    });

    test('a 2.0.0 workaround in extra is carried, not interpreted', () {
      // ADR-0004 promised the package never claims an `extra` key. A host that
      // kept its own ledger there keeps it until it migrates deliberately.
      final json = _payload(null)
        ..remove('spentStars')
        ..['extra'] = {'spentStars': 4};
      final progress = SagaProgress.fromJson(json);
      expect(progress.spentStars, 0);
      expect(progress.extra['spentStars'], 4);
    });

    test('spentStars takes part in equality', () {
      expect(_earnedSix(spent: 1), isNot(_earnedSix()));
      expect(_earnedSix(spent: 1), _earnedSix(spent: 1));
    });

    test('migrateFrom1x keeps what was spent', () {
      final json = _payload(3);
      expect(SagaProgress.migrateFrom1x(json).spentStars, 3);
    });
  });
}
