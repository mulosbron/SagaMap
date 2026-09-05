import 'level_progress.dart';
import 'saga_progress.dart';

/// Provides total star counts and chunk evaluation without duplicate loops.
extension SagaProgressStars on SagaProgress {
  /// Total stars from all completed levels.
  int get totalStars {
    int total = 0;
    for (final level in levels.values) {
      if (level.state == LevelCompletionState.completed) {
        total += level.stars;
      }
    }
    return total;
  }

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
