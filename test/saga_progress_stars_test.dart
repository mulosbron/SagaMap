import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

void main() {
  group('SagaProgressStars', () {
    test('empty SagaProgress -> totalStars == 0', () {
      final progress = SagaProgress.initial();
      expect(progress.totalStars, 0);
    });

    test('only unlocked levels -> totalStars == 0', () {
      final progressOnlyUnlocked = const SagaProgress(
        currentMaxUnlockedLevelId: 2,
        levels: {
          0: LevelProgress(levelId: 0, state: LevelCompletionState.unlocked, stars: 3), // e.g. cheating stars, but state is unlocked
          1: LevelProgress(levelId: 1, state: LevelCompletionState.unlocked, stars: 2),
          2: LevelProgress(levelId: 2, state: LevelCompletionState.unlocked, stars: 0),
        },
      );
      
      expect(progressOnlyUnlocked.totalStars, 0);
    });

    test('range boundaries are inclusive/exclusive correctly', () {
      final progress = const SagaProgress(
        currentMaxUnlockedLevelId: 5,
        levels: {
          0: LevelProgress(levelId: 0, state: LevelCompletionState.completed, stars: 3),
          1: LevelProgress(levelId: 1, state: LevelCompletionState.completed, stars: 2),
          2: LevelProgress(levelId: 2, state: LevelCompletionState.completed, stars: 1),
          3: LevelProgress(levelId: 3, state: LevelCompletionState.completed, stars: 3),
        },
      );

      // starsInRange(1, 2) -> levels 1 and 2 -> 2 + 1 = 3
      expect(progress.starsInRange(1, 2), 3);
      
      // completedCountInRange(1, 2) -> levels 1 and 2 -> 2
      expect(progress.completedCountInRange(1, 2), 2);
    });

    test('isRangePerfect is false when one level is missing or not perfect', () {
      final progress = const SagaProgress(
        currentMaxUnlockedLevelId: 5,
        levels: {
          0: LevelProgress(levelId: 0, state: LevelCompletionState.completed, stars: 3),
          1: LevelProgress(levelId: 1, state: LevelCompletionState.completed, stars: 3),
          2: LevelProgress(levelId: 2, state: LevelCompletionState.completed, stars: 2), // not perfect
        },
      );

      // missing level 3
      expect(progress.isRangePerfect(0, 4), isFalse);
      
      // not perfect level 2
      expect(progress.isRangePerfect(0, 3), isFalse);

      // perfect levels 0 and 1
      expect(progress.isRangePerfect(0, 2), isTrue);
    });

    test('unregistered level counts as 0 stars, does not throw', () {
      final progress = SagaProgress.initial();
      // unregistered level 5
      expect(progress.starsInRange(5, 1), 0);
    });
  });
}
