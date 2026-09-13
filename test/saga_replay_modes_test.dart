import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

SagaProgress _reached(int levelId) => SagaProgress(
      currentMaxUnlockedLevelId: levelId,
      levels: {
        levelId: LevelProgress(
          levelId: levelId,
          state: LevelCompletionState.unlocked,
        ),
      },
    );

/// Level 2 cleared once on one star; level 3 opened behind it.
SagaProgress _clearedOnOneStar() => SagaProgress(
      currentMaxUnlockedLevelId: 3,
      levels: {
        2: const LevelProgress(
          levelId: 2,
          state: LevelCompletionState.completed,
          stars: 1,
        ),
        3: const LevelProgress(
            levelId: 3, state: LevelCompletionState.unlocked),
      },
    );

bool _mustNotBeAsked(int levelId) =>
    fail('canUnlock was consulted for a replay-mode run (level $levelId)');

void main() {
  group('230.14 — a mode score does not overwrite stars', () {
    test('a hard run records its own score beside the default one', () {
      final result = const CompleteLevelUseCase().execute(
        currentProgress: _clearedOnOneStar(),
        levelId: 2,
        globalSeed: 7,
        stars: 3,
        modeId: 'hard',
      );

      final level = result.nextProgress.levels[2]!;
      expect(level.stars, 1);
      expect(level.starsByMode, {'hard': 3});
      expect(level.state, LevelCompletionState.completed);
      expect(result.outcome, CompleteLevelOutcome.applied);
    });

    test('the best mode score stays, as the default one does', () {
      const useCase = CompleteLevelUseCase();
      final three = useCase
          .execute(
            currentProgress: _clearedOnOneStar(),
            levelId: 2,
            globalSeed: 7,
            stars: 3,
            modeId: 'hard',
          )
          .nextProgress;
      final replayed = useCase
          .execute(
            currentProgress: three,
            levelId: 2,
            globalSeed: 7,
            stars: 1,
            modeId: 'hard',
          )
          .nextProgress;

      expect(replayed.levels[2]!.starsFor('hard'), 3);
    });

    test('modes score independently of one another', () {
      const useCase = CompleteLevelUseCase();
      var progress = _clearedOnOneStar();
      progress = useCase
          .execute(
            currentProgress: progress,
            levelId: 2,
            globalSeed: 7,
            stars: 2,
            modeId: 'hard',
          )
          .nextProgress;
      progress = useCase
          .execute(
            currentProgress: progress,
            levelId: 2,
            globalSeed: 7,
            stars: 3,
            modeId: 'mirror',
          )
          .nextProgress;

      expect(progress.levels[2]!.starsByMode, {'hard': 2, 'mirror': 3});
    });

    test('a default replay keeps the mode scores', () {
      const useCase = CompleteLevelUseCase();
      final withHard = useCase
          .execute(
            currentProgress: _clearedOnOneStar(),
            levelId: 2,
            globalSeed: 7,
            stars: 2,
            modeId: 'hard',
          )
          .nextProgress;
      final replayed = useCase
          .execute(
            currentProgress: withHard,
            levelId: 2,
            globalSeed: 7,
            stars: 3,
          )
          .nextProgress;

      expect(replayed.levels[2]!.stars, 3);
      expect(replayed.levels[2]!.starsByMode, {'hard': 2});
    });

    test('starsFor reads either score', () {
      const level = LevelProgress(
        levelId: 0,
        state: LevelCompletionState.completed,
        stars: 2,
        starsByMode: {'hard': 1},
      );
      expect(level.starsFor(null), 2);
      expect(level.starsFor('hard'), 1);
      expect(level.starsFor('never-played'), 0);
    });
  });

  group('230.15 — a mode run never unlocks', () {
    test('an unlocked level stays unlocked and its successor unrecorded', () {
      final result =
          const CompleteLevelUseCase(canUnlock: _mustNotBeAsked).execute(
        currentProgress: _reached(4),
        levelId: 4,
        globalSeed: 7,
        stars: 3,
        modeId: 'hard',
      );

      final next = result.nextProgress;
      expect(next.levels[4]?.state, LevelCompletionState.unlocked);
      expect(next.levels[4]?.stars, 0);
      expect(next.levels[4]?.starsFor('hard'), 3);
      expect(next.levels.containsKey(5), isFalse);
      expect(next.currentMaxUnlockedLevelId, 4);
      expect(result.unlockBlocked, isFalse);
    });

    test('a successor stored as locked stays locked', () {
      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 3,
        levels: {
          3: const LevelProgress(
            levelId: 3,
            state: LevelCompletionState.completed,
            stars: 1,
          ),
          4: const LevelProgress(
              levelId: 4, state: LevelCompletionState.locked),
        },
      );

      final next = const CompleteLevelUseCase()
          .execute(
            currentProgress: progress,
            levelId: 3,
            globalSeed: 7,
            modeId: 'hard',
          )
          .nextProgress;

      expect(next.levels[4]?.state, LevelCompletionState.locked);
      expect(next.currentMaxUnlockedLevelId, 3);
    });

    test('a record written for an unrecorded level opens nothing new', () {
      // Within the pointer the level is already reachable, so its new record
      // says so; past it, with the guard off, the record stays locked rather
      // than handing the default game a level it never opened.
      final atPointer = SagaProgress(currentMaxUnlockedLevelId: 6, levels: {});
      final within = const CompleteLevelUseCase().execute(
        currentProgress: atPointer,
        levelId: 6,
        globalSeed: 7,
        modeId: 'hard',
      );
      expect(
        within.nextProgress.levels[6]?.state,
        LevelCompletionState.unlocked,
      );

      final beyond =
          const CompleteLevelUseCase(enforceUnlockOrder: false).execute(
        currentProgress: atPointer,
        levelId: 40,
        globalSeed: 7,
        modeId: 'hard',
      );
      expect(
          beyond.nextProgress.levels[40]?.state, LevelCompletionState.locked);
      expect(beyond.nextProgress.currentMaxUnlockedLevelId, 6);
    });

    test('the order guard still refuses an unreached level', () {
      final result = const CompleteLevelUseCase().execute(
        currentProgress: SagaProgress.initial(),
        levelId: 9,
        globalSeed: 7,
        modeId: 'hard',
      );
      expect(result.outcome, CompleteLevelOutcome.rejectedUnreached);
      expect(result.nextProgress.levels.containsKey(9), isFalse);
    });
  });

  group('230.16 — a mode run drops no boss reward', () {
    test('hard on an uncleared boss mints nothing, and spends no first clear',
        () {
      const useCase = CompleteLevelUseCase();

      final hard = useCase.execute(
        currentProgress: _reached(14),
        levelId: 14,
        globalSeed: 99,
        modeId: 'hard',
      );
      expect(hard.reward, isNull);

      // The default clear afterwards is still the first clear, and pays out.
      final normal = useCase.execute(
        currentProgress: hard.nextProgress,
        levelId: 14,
        globalSeed: 99,
      );
      expect(normal.reward, isNotNull);

      final hardAgain = useCase.execute(
        currentProgress: normal.nextProgress,
        levelId: 14,
        globalSeed: 99,
        modeId: 'hard',
      );
      expect(hardAgain.reward, isNull);
    });
  });

  group('230.13 — an id naming the default mode is refused', () {
    for (final bad in ['', '   ', 'default']) {
      test('"$bad" throws from execute and from starsFor', () {
        expect(
          () => const CompleteLevelUseCase().execute(
            currentProgress: _reached(0),
            levelId: 0,
            globalSeed: 7,
            modeId: bad,
          ),
          throwsArgumentError,
        );
        expect(
          () => const LevelProgress(
            levelId: 0,
            state: LevelCompletionState.completed,
          ).starsFor(bad),
          throwsArgumentError,
        );
      });
    }

    test('an ordinary id passes', () {
      expect(() => LevelProgress.checkModeId('hard'), returnsNormally);
      expect(() => LevelProgress.checkModeId('Default'), returnsNormally);
    });
  });

  group('230.17 — mode scores survive a round trip', () {
    test('LevelProgress keeps every mode', () {
      const level = LevelProgress(
        levelId: 5,
        state: LevelCompletionState.completed,
        stars: 2,
        starsByMode: {'hard': 1, 'mirror': 3},
      );
      final reloaded = LevelProgress.fromJson(level.toJson());
      expect(reloaded.starsByMode, {'hard': 1, 'mirror': 3});
      expect(reloaded, level);
    });

    test('SagaProgress keeps them through its own round trip', () {
      final progress = const CompleteLevelUseCase()
          .execute(
            currentProgress: _clearedOnOneStar(),
            levelId: 2,
            globalSeed: 7,
            stars: 2,
            modeId: 'hard',
            now: DateTime.utc(2026, 9, 13),
          )
          .nextProgress;
      expect(SagaProgress.fromJson(progress.toJson()), progress);
    });

    test('toJson omits the key while no mode was played', () {
      const level =
          LevelProgress(levelId: 0, state: LevelCompletionState.unlocked);
      expect(level.toJson().containsKey('starsByMode'), isFalse);
    });

    test('fromJson clamps, skips and drops what it cannot trust', () {
      final level = LevelProgress.fromJson({
        'levelId': 0,
        'state': 'completed',
        'stars': 1,
        'starsByMode': {
          'hard': -2,
          'mirror': 9,
          'memory': 'three',
          'slow': 1.9,
          '': 3,
          'default': 2,
        },
      });
      expect(level.starsByMode, {'hard': 0, 'mirror': 3, 'slow': 1});
    });

    test('a wrong-typed map reads as no modes played', () {
      for (final broken in [
        'broken',
        42,
        [1, 2],
        null
      ]) {
        final level = LevelProgress.fromJson({
          'levelId': 0,
          'state': 'completed',
          'starsByMode': broken,
        });
        expect(level.starsByMode, isEmpty, reason: '$broken');
      }
    });

    test('starsByMode takes part in equality and copyWith', () {
      const plain =
          LevelProgress(levelId: 0, state: LevelCompletionState.completed);
      final hard = plain.copyWith(starsByMode: {'hard': 2});
      expect(hard, isNot(plain));
      expect(hard.starsByMode, {'hard': 2});
      expect(hard.copyWith(stars: 1).starsByMode, {'hard': 2});
    });
  });
}
