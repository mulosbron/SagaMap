import 'level_progress.dart';

/// Aggregate progression model for all known levels.
class SagaProgress {
  final int currentMaxUnlockedLevelId;
  final Map<int, LevelProgress> levels;

  /// Host-owned data the package stores but never interprets.
  ///
  /// The package reads nothing from it and will never claim a key.
  /// Keep it small; it is serialised on every save.
  final Map<String, dynamic> extra;

  /// Defensively copies [levels] and [extra] as unmodifiable maps, so a caller
  /// mutating a returned map cannot silently rewrite "persisted" state — it
  /// throws instead. This mirrors the inventory repository's
  /// `List.unmodifiable` guarantee. The cost is that the constructor is no
  /// longer `const`.
  SagaProgress({
    required this.currentMaxUnlockedLevelId,
    required Map<int, LevelProgress> levels,
    Map<String, dynamic> extra = const {},
  })  : levels = Map<int, LevelProgress>.unmodifiable(levels),
        extra = Map<String, dynamic>.unmodifiable(extra);

  /// Creates the baseline progress with level `0` unlocked.
  /// Note that level `0` is the first level.
  factory SagaProgress.initial() {
    return SagaProgress(
      currentMaxUnlockedLevelId: 0,
      levels: {
        0: const LevelProgress(
          levelId: 0,
          state: LevelCompletionState.unlocked,
          stars: 0,
        ),
      },
      extra: {},
    );
  }

  /// Serializes the progress tree for repository storage.
  Map<String, dynamic> toJson() {
    final levelsMap = <String, dynamic>{};
    for (final e in levels.entries) {
      levelsMap[e.key.toString()] = e.value.toJson();
    }
    final json = <String, dynamic>{
      'currentMaxUnlockedLevelId': currentMaxUnlockedLevelId,
      'levels': levelsMap,
    };
    if (extra.isNotEmpty) {
      json['extra'] = extra;
    }
    return json;
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

    final extraRaw = json['extra'];
    Map<String, dynamic> extra = {};
    if (extraRaw is Map<String, dynamic>) {
      extra = Map<String, dynamic>.from(extraRaw);
    } else if (extraRaw is Map) {
      extra = Map<String, dynamic>.from(extraRaw);
    }

    return SagaProgress(
      currentMaxUnlockedLevelId: unlocked < 0 ? 0 : unlocked,
      levels: levels.isNotEmpty ? levels : SagaProgress.initial().levels,
      extra: extra,
    );
  }

  /// Returns a copy with selective field overrides.
  SagaProgress copyWith({
    int? currentMaxUnlockedLevelId,
    Map<int, LevelProgress>? levels,
    Map<String, dynamic>? extra,
  }) {
    return SagaProgress(
      currentMaxUnlockedLevelId:
          currentMaxUnlockedLevelId ?? this.currentMaxUnlockedLevelId,
      levels: levels ?? Map<int, LevelProgress>.from(this.levels),
      extra: extra ?? Map<String, dynamic>.from(this.extra),
    );
  }
}
