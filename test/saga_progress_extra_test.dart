import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/src/core/domain/models/level_progress.dart';
import 'package:saga_map/src/core/domain/models/saga_progress.dart';
import 'package:saga_map/src/core/domain/usecases/complete_level_usecase.dart';

void main() {
  group('SagaProgress.extra', () {
    test('omits extra key when empty', () {
      final progress = SagaProgress.initial();
      final json = progress.toJson();
      expect(json.containsKey('extra'), isFalse);
    });

    test('reads 1.0.0 format seamlessly', () {
      final json100 = {
        'currentMaxUnlockedLevelId': 2,
        'levels': {
          '0': {
            'levelId': 0,
            'state': 'completed',
            'stars': 3,
          },
          '1': {
            'levelId': 1,
            'state': 'completed',
            'stars': 1,
          },
        },
      };
      final progress = SagaProgress.fromJson(json100);
      expect(progress.extra, isEmpty);
      expect(progress.currentMaxUnlockedLevelId, 2);
    });

    test('an unlock pointer beyond the recorded levels is clamped', () {
      // T-12: a save claiming level 9999 next to one recorded level used to
      // load as written, and with enforceUnlockOrder that single integer is
      // the only thing standing between a player and any level id. The rule:
      // the pointer may reach one past the highest record — the successor a
      // completion opens — and no further.
      final tampered = {
        'currentMaxUnlockedLevelId': 9999,
        'levels': {
          '0': {'levelId': 0, 'state': 'completed', 'stars': 3},
        },
      };

      expect(SagaProgress.fromJson(tampered).currentMaxUnlockedLevelId, 1);

      // Clamped, not thrown: a save that refuses to load is worse for a player
      // than one that loads honest. Their real levels are untouched.
      expect(
        SagaProgress.fromJson(tampered).levels[0]?.state,
        LevelCompletionState.completed,
      );

      // The empty-levels payload falls back to the initial state, whose only
      // record is level 0 and it is `unlocked`, not completed. Since A-02 the
      // ceiling rests on completions, so a fresh save has cleared nothing and
      // the ceiling is 0.
      expect(
        SagaProgress.fromJson({
          'currentMaxUnlockedLevelId': 9999,
          'levels': <String, dynamic>{},
        }).currentMaxUnlockedLevelId,
        0,
      );
    });

    test('survives round-trip intact', () {
      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 0,
        levels: {},
        extra: {'app.played_times': 42},
      );
      final json = progress.toJson();
      final restored = SagaProgress.fromJson(json);
      expect(restored.extra, equals({'app.played_times': 42}));
    });

    test('preserves nested Maps and Lists in round-trip', () {
      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 0,
        levels: {},
        extra: {
          'app.nested': {
            'foo': 'bar',
            'list': [1, 2, 3],
          },
        },
      );
      final json = progress.toJson();
      final restored = SagaProgress.fromJson(json);
      expect(
        restored.extra['app.nested'],
        equals({
          'foo': 'bar',
          'list': [1, 2, 3],
        }),
      );
    });

    test('yields empty map on invalid string type', () {
      final jsonBad = {
        'currentMaxUnlockedLevelId': 0,
        'levels': {},
        'extra': 'bozuk',
      };
      final progress = SagaProgress.fromJson(jsonBad);
      expect(progress.extra, isEmpty);
    });

    test('yields empty map on null type', () {
      final jsonNull = {
        'currentMaxUnlockedLevelId': 0,
        'levels': {},
        'extra': null,
      };
      final progress = SagaProgress.fromJson(jsonNull);
      expect(progress.extra, isEmpty);
    });

    test('copyWith isolates extra changes', () {
      final original = SagaProgress(
        currentMaxUnlockedLevelId: 5,
        levels: {},
        extra: {'app.a': 1},
      );
      final modified = original.copyWith(extra: {'app.a': 2});
      expect(modified.currentMaxUnlockedLevelId, 5);
      expect(modified.extra, {'app.a': 2});
      expect(original.extra, {'app.a': 1}); // No mutation
    });
  });

  group('LevelProgress.extra', () {
    test('omits extra key when empty', () {
      const level = LevelProgress(
        levelId: 1,
        state: LevelCompletionState.unlocked,
      );
      final json = level.toJson();
      expect(json.containsKey('extra'), isFalse);
    });

    test('reads 1.0.0 format seamlessly', () {
      final json100 = {
        'levelId': 1,
        'state': 'unlocked',
        'stars': 0,
      };
      final level = LevelProgress.fromJson(json100);
      expect(level.extra, isEmpty);
      expect(level.levelId, 1);
    });

    test('survives round-trip intact', () {
      const level = LevelProgress(
        levelId: 1,
        state: LevelCompletionState.completed,
        extra: {'app.streak': 5},
      );
      final json = level.toJson();
      final restored = LevelProgress.fromJson(json);
      expect(restored.extra, equals({'app.streak': 5}));
    });

    test('yields empty map on invalid string type', () {
      final jsonBad = {
        'levelId': 1,
        'state': 'completed',
        'extra': 'bozuk',
      };
      final level = LevelProgress.fromJson(jsonBad);
      expect(level.extra, isEmpty);
    });

    test('yields empty map on null type', () {
      final jsonNull = {
        'levelId': 1,
        'state': 'completed',
        'extra': null,
      };
      final level = LevelProgress.fromJson(jsonNull);
      expect(level.extra, isEmpty);
    });

    test('preserves extra on re-completion', () {
      final originalProgress = SagaProgress(
        currentMaxUnlockedLevelId: 1,
        levels: {
          1: const LevelProgress(
            levelId: 1,
            state: LevelCompletionState.completed,
            stars: 2,
            extra: {'app.score': 9000},
          ),
          2: const LevelProgress(
            levelId: 2,
            state: LevelCompletionState.unlocked,
          ),
        },
      );

      const useCase = CompleteLevelUseCase();
      final result = useCase.execute(
        currentProgress: originalProgress,
        levelId: 1,
        globalSeed: 123,
        stars: 3,
      );

      final updatedLevel = result.nextProgress.levels[1]!;
      expect(updatedLevel.stars, 3);
      expect(updatedLevel.extra, equals({'app.score': 9000}));
    });
  });

  group('A-02 — the ceiling rests on completed records only', () {
    test('a fake locked record cannot lift the unlock pointer', () {
      // The audit ran this payload against the shipped code: the pointer
      // survived at 999999 and CompleteLevelUseCase(), with the order guard
      // on, happily completed level 999998. Folding over every key made the
      // presence of a record — any record, in any state — proof of progress.
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 999999,
        'levels': {
          '0': {'levelId': 0, 'state': 'unlocked', 'stars': 0},
          '999998': {'levelId': 999998, 'state': 'locked', 'stars': 0},
        },
      });

      expect(progress.currentMaxUnlockedLevelId, 0);

      final result = const CompleteLevelUseCase().execute(
        currentProgress: progress,
        levelId: 999998,
        globalSeed: 7,
      );
      expect(result.outcome, CompleteLevelOutcome.rejectedUnreached);
      // The forged record still loads — sanitising never drops a host's data —
      // but it stays `locked` and buys nothing.
      expect(
        result.nextProgress.levels[999998]?.state,
        LevelCompletionState.locked,
      );
    });

    test('a record for some other level does not lift the pointer', () {
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 9,
        'levels': {
          '0': {'levelId': 0, 'state': 'completed', 'stars': 1},
          '5': {'levelId': 5, 'state': 'unlocked', 'stars': 0},
        },
      });
      // Nothing justifies 9: level 5's record is not a claim about level 9,
      // and one completed level (0) opens exactly one successor.
      expect(progress.currentMaxUnlockedLevelId, 1);
    });

    test('no completed record means a ceiling of zero', () {
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 4,
        'levels': {
          '0': {'levelId': 0, 'state': 'unlocked', 'stars': 0},
        },
      });
      expect(progress.currentMaxUnlockedLevelId, 0);
    });

    test('a deliberately jumped pointer with its own record survives', () {
      // The chapter-skip host: it opened level 5 itself and wrote the record
      // saying so. Folding over completions alone would have erased that on
      // the next load, so the pointer stands when the payload justifies it at
      // the pointer itself.
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 5,
        'levels': {
          '0': {'levelId': 0, 'state': 'completed', 'stars': 1},
          '5': {'levelId': 5, 'state': 'unlocked', 'stars': 0},
        },
      });
      expect(progress.currentMaxUnlockedLevelId, 5);
    });

    test('an honest save is untouched', () {
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 2,
        'levels': {
          '0': {'levelId': 0, 'state': 'completed', 'stars': 3},
          '1': {'levelId': 1, 'state': 'completed', 'stars': 2},
          '2': {'levelId': 2, 'state': 'unlocked', 'stars': 0},
        },
      });
      expect(progress.currentMaxUnlockedLevelId, 2);
    });
  });

  group('A-01 — a sparse 1.x save', () {
    // 1.x read a missing record as "unlocked if below the pointer", so a host
    // could persist a pointer of 20 beside three records. 2.0.0 reads a
    // missing record as locked; the pointer is reconciled and the player, to
    // whom the pointer *is* the progress, sees it vanish.
    Map<String, dynamic> sparse() => {
          'currentMaxUnlockedLevelId': 20,
          'levels': {
            '0': {'levelId': 0, 'state': 'completed', 'stars': 3},
            '1': {'levelId': 1, 'state': 'completed', 'stars': 2},
            '2': {'levelId': 2, 'state': 'completed', 'stars': 1},
          },
          'extra': {'lastWorld': 'verdant'},
        };

    test('drops the pointer on a plain load — and says so', () {
      final clamps = <SagaProgressClamp>[];
      final progress = SagaProgress.fromJson(sparse(), onClamp: clamps.add);

      expect(progress.currentMaxUnlockedLevelId, 3);
      expect(clamps, hasLength(1));
      expect(clamps.single.storedPointer, 20);
      expect(clamps.single.clampedTo, 3);
      expect(clamps.single.completedCeiling, 3);
      expect(clamps.single.lostGround, isTrue);
    });

    test('every level above the new pointer then refuses to complete', () {
      final progress = SagaProgress.fromJson(sparse());
      final result = const CompleteLevelUseCase().execute(
        currentProgress: progress,
        levelId: 12,
        globalSeed: 1,
      );
      expect(result.outcome, CompleteLevelOutcome.rejectedUnreached);
    });

    test('migrateFrom1x keeps the pointer and backfills reachability', () {
      final progress = SagaProgress.migrateFrom1x(sparse());

      expect(progress.currentMaxUnlockedLevelId, 20);
      expect(progress.levels.keys.length, 21);
      expect(progress.levels[2]?.state, LevelCompletionState.completed);
      expect(progress.levels[2]?.stars, 1);
      expect(progress.levels[12]?.state, LevelCompletionState.unlocked);
      expect(progress.levels[12]?.stars, 0);
      expect(progress.extra['lastWorld'], 'verdant');

      // And the migrated save survives its own round trip through fromJson,
      // because level 20 is now recorded rather than merely pointed at.
      final clamps = <SagaProgressClamp>[];
      final reloaded =
          SagaProgress.fromJson(progress.toJson(), onClamp: clamps.add);
      expect(reloaded.currentMaxUnlockedLevelId, 20);
      expect(clamps, isEmpty);
    });

    test('migrateFrom1x bounds a hostile pointer', () {
      final progress = SagaProgress.migrateFrom1x(
        {'currentMaxUnlockedLevelId': 2000000000, 'levels': {}},
        maxBackfill: 50,
      );
      expect(progress.currentMaxUnlockedLevelId, 50);
      expect(progress.levels.keys.length, 51);
    });

    test('a clean load reports no clamp', () {
      final clamps = <SagaProgressClamp>[];
      SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 1,
        'levels': {
          '0': {'levelId': 0, 'state': 'completed', 'stars': 1},
        },
      }, onClamp: clamps.add);
      expect(clamps, isEmpty);
    });
  });

  group('A-13 — fromJson sanitises its keys', () {
    test('a negative level key is skipped', () {
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 1,
        'levels': {
          '-5': {'levelId': -5, 'state': 'completed', 'stars': 3},
          '0': {'levelId': 0, 'state': 'completed', 'stars': 1},
        },
      });
      // A negative level is an impossible state everywhere else in the class:
      // the pointer is raised to 0 and CompleteLevelUseCase refuses a negative
      // id whatever the order guard says. The key was the door left open.
      expect(progress.levels.containsKey(-5), isFalse);
      expect(progress.levels.containsKey(0), isTrue);
    });

    test('a record disagreeing with its key is corrected to the key', () {
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 0,
        'levels': {
          '3': {'levelId': 7, 'state': 'completed', 'stars': 2},
        },
      });
      // Looking the record up by key and reading its `levelId` used to give
      // two different answers about the same record. Corrected rather than
      // dropped, matching how every other field here is sanitised.
      expect(progress.levels[3]?.levelId, 3);
      expect(progress.levels[3]?.stars, 2);
      expect(progress.levels.containsKey(7), isFalse);
    });

    test('a negative key that disagrees with its record is still skipped', () {
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 0,
        'levels': {
          '-5': {'levelId': 7, 'state': 'completed', 'stars': 3},
        },
      });
      expect(progress.levels.containsKey(-5), isFalse);
      expect(progress.levels.containsKey(7), isFalse);
      // Nothing survived, so this reads as an uninitialised save.
      expect(progress.levels.keys.toList(), [0]);
    });

    test('an agreeing record is passed through untouched', () {
      final progress = SagaProgress.fromJson({
        'currentMaxUnlockedLevelId': 1,
        'levels': {
          '0': {'levelId': 0, 'state': 'completed', 'stars': 3},
        },
      });
      expect(progress.levels[0]?.levelId, 0);
      expect(progress.levels[0]?.stars, 3);
    });
  });

  group('A-14 — SagaProgress is compared by value', () {
    SagaProgress make({int pointer = 1, int stars = 3, String world = 'a'}) =>
        SagaProgress(
          currentMaxUnlockedLevelId: pointer,
          levels: {
            0: LevelProgress(
              levelId: 0,
              state: LevelCompletionState.completed,
              stars: stars,
            ),
          },
          extra: {'lastWorld': world},
        );

    test('two field-equal instances are equal', () {
      // 2.0.0 gave LevelProgress value equality because a host resolver
      // building a fresh instance per call reported a change on every sweep.
      // The same mistake sat one level up, on a bigger object.
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('each field is actually compared', () {
      expect(make(), isNot(make(pointer: 2)));
      expect(make(), isNot(make(stars: 1)));
      expect(make(), isNot(make(world: 'b')));
    });

    test('a differing levels map is not equal', () {
      final a = make();
      final b = SagaProgress(
        currentMaxUnlockedLevelId: 1,
        levels: {
          0: const LevelProgress(
              levelId: 0, state: LevelCompletionState.completed, stars: 3),
          1: const LevelProgress(
              levelId: 1, state: LevelCompletionState.unlocked),
        },
        extra: const {'lastWorld': 'a'},
      );
      expect(a, isNot(b));
    });

    test('a round trip through JSON compares equal', () {
      final progress = make();
      expect(SagaProgress.fromJson(progress.toJson()), progress);
    });
  });
}
