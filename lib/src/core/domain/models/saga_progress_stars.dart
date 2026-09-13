import 'level_progress.dart';
import 'saga_progress.dart';

/// Provides total star counts and chunk evaluation without duplicate loops.
extension SagaProgressStars on SagaProgress {
  /// Total stars from all completed levels.
  ///
  /// Counts the default mode's [LevelProgress.stars] only; alternate-mode
  /// scores in [LevelProgress.starsByMode] are not part of it. Spending does
  /// not lower it — see [availableStars].
  ///
  /// This is the one definition. It stays on the extension rather than moving
  /// into the class beside [SagaProgress.spentStars], because a call written
  /// as `SagaProgressStars(progress).totalStars` would stop compiling — a
  /// break a minor release does not get to make.
  int get totalStars {
    int total = 0;
    for (final level in levels.values) {
      if (level.state == LevelCompletionState.completed) {
        total += level.stars;
      }
    }
    return total;
  }

  /// Stars earned and not yet spent: [totalStars] minus
  /// [SagaProgress.spentStars].
  ///
  /// Never negative, because `spentStars` never exceeds [totalStars].
  int get availableStars => totalStars - spentStars;

  /// Calculates the sum of stars in the interval [startLevelId, startLevelId + count).
  ///
  /// For instance, chunk completion: progress.starsInRange(chunkIndex * sectionsPerChunk, sectionsPerChunk)
  int starsInRange(int startLevelId, int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must not be negative.');
    }
    if (count == 0) return 0;

    int total = 0;
    for (int id = startLevelId; id < startLevelId + count; id++) {
      final level = levels[id];
      if (level != null && level.state == LevelCompletionState.completed) {
        total += level.stars;
      }
    }
    return total;
  }

  /// Calculates how many levels are completed in [startLevelId, startLevelId + count).
  ///
  /// Example: progress.completedCountInRange(chunkIndex * sectionsPerChunk, sectionsPerChunk)
  int completedCountInRange(int startLevelId, int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must not be negative.');
    }
    if (count == 0) return 0;

    int completed = 0;
    for (int id = startLevelId; id < startLevelId + count; id++) {
      final level = levels[id];
      if (level != null && level.state == LevelCompletionState.completed) {
        completed++;
      }
    }
    return completed;
  }

  /// Checks if every level in [startLevelId, startLevelId + count) is completed and
  /// has [perLevel] stars. If the range is empty (count == 0), returns true.
  ///
  /// Example: progress.isRangePerfect(chunkIndex * sectionsPerChunk, sectionsPerChunk)
  bool isRangePerfect(int startLevelId, int count,
      {int perLevel = kMaxLevelStars}) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must not be negative.');
    }
    if (count == 0) return true;

    for (int id = startLevelId; id < startLevelId + count; id++) {
      final level = levels[id];
      if (level == null ||
          level.state != LevelCompletionState.completed ||
          level.stars < perLevel) {
        return false;
      }
    }
    return true;
  }
}
