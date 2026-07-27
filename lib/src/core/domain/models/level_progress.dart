/// Upper bound on a level's star score.
///
/// Star systems in this genre top out at three; the cap exists so a tampered
/// save cannot inject an absurd score that later overflows a UI or a total.
const int kMaxLevelStars = 3;

/// Completion status for one level.
enum LevelCompletionState {
  locked,
  unlocked,
  completed;

  static LevelCompletionState fromString(String value) {
    return LevelCompletionState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => LevelCompletionState.locked,
    );
  }
}

/// Persistable progression snapshot for one level id.
class LevelProgress {
  final int levelId;
  final LevelCompletionState state;
  final int stars;
  final DateTime? lastPlayedAt;

  const LevelProgress({
    required this.levelId,
    required this.state,
    this.stars = 0,
    this.lastPlayedAt,
  });

  /// Serializes level progress for storage.
  Map<String, dynamic> toJson() {
    return {
      'levelId': levelId,
      'state': state.name,
      'stars': stars,
      'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    };
  }

  /// Deserializes level progress from JSON.
  ///
  /// Tolerates a malformed or tampered payload: every field is read
  /// defensively and clamped to a sane range rather than trusted. A corrupt
  /// save on the device must not crash the app or produce an impossible state.
  static LevelProgress fromJson(Map<String, dynamic> json) {
    // `is num` rather than `as num?`: the latter throws on a wrong-typed value
    // (a String where a number was expected), which is exactly what a tampered
    // save contains. A type check coerces instead of crashing.
    final rawLevel = json['levelId'];
    final rawStars = json['stars'];
    final rawState = json['state'];
    final rawLastPlayed = json['lastPlayedAt'];

    final stars = rawStars is num ? rawStars.toInt() : 0;
    return LevelProgress(
      levelId: rawLevel is num ? rawLevel.toInt() : 0,
      state: LevelCompletionState.fromString(
        rawState is String ? rawState : 'locked',
      ),
      // Bounded to a plausible score; a negative or absurd value is coerced.
      stars: stars < 0 ? 0 : (stars > kMaxLevelStars ? kMaxLevelStars : stars),
      lastPlayedAt:
          rawLastPlayed is String ? DateTime.tryParse(rawLastPlayed) : null,
    );
  }

  /// Returns a copy with overridden fields.
  LevelProgress copyWith({
    int? levelId,
    LevelCompletionState? state,
    int? stars,
    DateTime? lastPlayedAt,
  }) {
    return LevelProgress(
      levelId: levelId ?? this.levelId,
      state: state ?? this.state,
      stars: stars ?? this.stars,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }
}
