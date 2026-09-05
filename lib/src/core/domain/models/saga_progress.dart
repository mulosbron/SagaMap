import 'level_progress.dart';

/// Aggregate progression model for all known levels.
class SagaProgress {
  final int currentMaxUnlockedLevelId;
  final Map<int, LevelProgress> levels;

  const SagaProgress({
    required this.currentMaxUnlockedLevelId,
    required this.levels,
  });

  /// Creates the baseline progress with level `0` unlocked.
  /// Note that level `0` is the first level.
  factory SagaProgress.initial() {
    return const SagaProgress(
      currentMaxUnlockedLevelId: 0,
      levels: {
        0: LevelProgress(
          levelId: 0,
          state: LevelCompletionState.unlocked,
          stars: 0,
        ),
      },
    );
  }

  /// Serializes the progress tree for repository storage.
  Map<String, dynamic> toJson() {
    final levelsMap = <String, dynamic>{};
    for (final e in levels.entries) {
      levelsMap[e.key.toString()] = e.value.toJson();
    }
    return {
      'currentMaxUnlockedLevelId': currentMaxUnlockedLevelId,
      'levels': levelsMap,
    };
  }

  /// Restores progress from serialized payload.
  static SagaProgress fromJson(Map<String, dynamic> json) {
    final levelsRaw = json['levels'];
    final Map<int, LevelProgress> levels = {};
    if (levelsRaw is Map<String, dynamic>) {
      for (final e in levelsRaw.entries) {
        final key = int.tryParse(e.key);
        if (key != null && e.value is Map<String, dynamic>) {
          levels[key] = LevelProgress.fromJson(e.value as Map<String, dynamic>);
        }
      }
    } else if (levelsRaw is Map) {
      for (final e in levelsRaw.entries) {
        final key =
            e.key is int ? e.key as int : int.tryParse(e.key.toString());
        if (key != null && e.value is Map<String, dynamic>) {
          levels[key] = LevelProgress.fromJson(e.value as Map<String, dynamic>);
        }
      }
    }
    // `is num` guards a wrong-typed value; a negative unlock pointer is an
    // impossible state — a tampered save must not make the map think level -5
    // is unlocked.
    final rawUnlocked = json['currentMaxUnlockedLevelId'];
    final unlocked = rawUnlocked is num ? rawUnlocked.toInt() : 0;
    return SagaProgress(
      currentMaxUnlockedLevelId: unlocked < 0 ? 0 : unlocked,
      levels: levels.isNotEmpty ? levels : SagaProgress.initial().levels,
    );
  }

  /// Returns a copy with selective field overrides.
  SagaProgress copyWith({
    int? currentMaxUnlockedLevelId,
    Map<int, LevelProgress>? levels,
  }) {
    return SagaProgress(
      currentMaxUnlockedLevelId:
          currentMaxUnlockedLevelId ?? this.currentMaxUnlockedLevelId,
      levels: levels ?? Map<int, LevelProgress>.from(this.levels),
    );
  }
}
