import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

void main() {
  group('CompleteLevelUseCase', () {
    test('marks current level completed and unlocks next level', () {
      const useCase = CompleteLevelUseCase();
      final now = DateTime.utc(2026, 4, 28, 20);

      final result = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 0,
        globalSeed: 7,
        now: now,
      );

      expect(
        result.nextProgress.levels[0]?.state,
        LevelCompletionState.completed,
      );
      expect(result.nextProgress.levels[0]?.stars, 1);
      expect(result.nextProgress.levels[0]?.lastPlayedAt, now);
      expect(
        result.nextProgress.levels[1]?.state,
        LevelCompletionState.unlocked,
      );
      expect(result.nextProgress.currentMaxUnlockedLevelId, 1);
    });

    test('unlocks a successor that was already stored as locked', () {
      const useCase = CompleteLevelUseCase();

      // Seeding every level as locked up front is a natural thing for a host to
      // do. The successor used to stay locked forever while
      // currentMaxUnlockedLevelId claimed otherwise, so the map went dead after
      // a single completion.
      const preSeeded = SagaProgress(
        currentMaxUnlockedLevelId: 0,
        levels: {
          0: LevelProgress(levelId: 0, state: LevelCompletionState.unlocked),
          1: LevelProgress(levelId: 1, state: LevelCompletionState.locked),
          2: LevelProgress(levelId: 2, state: LevelCompletionState.locked),
        },
      );

      final result = useCase.execute(
        currentProgress: preSeeded,
        levelId: 0,
        globalSeed: 7,
      );

      expect(
        result.nextProgress.levels[1]?.state,
        LevelCompletionState.unlocked,
      );
      expect(result.nextProgress.currentMaxUnlockedLevelId, 1);
      // Levels further ahead stay shut.
      expect(result.nextProgress.levels[2]?.state, LevelCompletionState.locked);
    });

    test('keeps the best star count when a level is replayed', () {
      const useCase = CompleteLevelUseCase();
      const threeStarred = SagaProgress(
        currentMaxUnlockedLevelId: 3,
        levels: {
          2: LevelProgress(
            levelId: 2,
            state: LevelCompletionState.completed,
            stars: 3,
          ),
        },
      );

      final replayed = useCase.execute(
        currentProgress: threeStarred,
        levelId: 2,
        globalSeed: 7,
        stars: 1,
      );

      // A weaker replay keeps the earlier three-star result.
      expect(replayed.nextProgress.levels[2]?.stars, 3);
    });

    test('clamps an out-of-range star score', () {
      const useCase = CompleteLevelUseCase();

      // Genre norm is three stars; a caller (or tampered save) passing more is
      // coerced rather than propagated. The guard is a runtime clamp, not a
      // release-stripped assert.
      final tooMany = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 0,
        globalSeed: 7,
        stars: 5,
      );
      expect(tooMany.nextProgress.levels[0]?.stars, kMaxLevelStars);

      final negative = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 0,
        globalSeed: 7,
        stars: -3,
      );
      expect(negative.nextProgress.levels[0]?.stars, 0);
    });

    test('completing a level ahead is rejected when unlock order is enforced',
        () {
      const useCase = CompleteLevelUseCase();
      const atStart = SagaProgress(
        currentMaxUnlockedLevelId: 2,
        levels: {},
      );

      // Skipping to level 50 with the guard on is a no-op.
      final skipped = useCase.execute(
        currentProgress: atStart,
        levelId: 50,
        globalSeed: 7,
        enforceUnlockOrder: true,
      );
      expect(skipped.nextProgress.currentMaxUnlockedLevelId, 2);
      expect(skipped.nextProgress.levels.containsKey(50), isFalse);

      // A reachable level still completes.
      final reachable = useCase.execute(
        currentProgress: atStart,
        levelId: 2,
        globalSeed: 7,
        enforceUnlockOrder: true,
      );
      expect(
        reachable.nextProgress.levels[2]?.state,
        LevelCompletionState.completed,
      );
    });

    test('a boss reward is minted only on first clear', () {
      const useCase = CompleteLevelUseCase();

      final first = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 15,
        globalSeed: 99,
      );
      expect(first.reward, isNotNull);

      // Replaying the boss must not re-mint the reward.
      final replay = useCase.execute(
        currentProgress: first.nextProgress,
        levelId: 15,
        globalSeed: 99,
      );
      expect(replay.reward, isNull);
    });

    test('never lowers currentMaxUnlockedLevelId', () {
      const useCase = CompleteLevelUseCase();
      const deepProgress = SagaProgress(
        currentMaxUnlockedLevelId: 20,
        levels: {},
      );

      // Replaying an early level must not roll progression back.
      final result = useCase.execute(
        currentProgress: deepProgress,
        levelId: 1,
        globalSeed: 7,
      );

      expect(result.nextProgress.currentMaxUnlockedLevelId, 20);
    });

    test('does not demote an already completed successor', () {
      const useCase = CompleteLevelUseCase();
      const bothDone = SagaProgress(
        currentMaxUnlockedLevelId: 5,
        levels: {
          3: LevelProgress(levelId: 3, state: LevelCompletionState.completed),
          4: LevelProgress(
            levelId: 4,
            state: LevelCompletionState.completed,
            stars: 2,
          ),
        },
      );

      final result = useCase.execute(
        currentProgress: bothDone,
        levelId: 3,
        globalSeed: 7,
      );

      expect(
        result.nextProgress.levels[4]?.state,
        LevelCompletionState.completed,
      );
      expect(result.nextProgress.levels[4]?.stars, 2);
    });

    test('returns boss reward only on boss levels', () {
      const useCase = CompleteLevelUseCase();
      final initial = SagaProgress.initial();

      final nonBoss = useCase.execute(
        currentProgress: initial,
        levelId: 9,
        globalSeed: 99,
      );
      final boss = useCase.execute(
        currentProgress: initial,
        levelId: 15,
        globalSeed: 99,
      );

      expect(nonBoss.reward, isNull);
      expect(boss.reward, isNotNull);
    });
  });
}
