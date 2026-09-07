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

  /// Per-level host data — alternate-mode scores, a no-mistake streak.
  final Map<String, dynamic> extra;

  const LevelProgress({
    required this.levelId,
    required this.state,
    this.stars = 0,
    this.lastPlayedAt,
    this.extra = const {},
  });

  /// Serializes level progress for storage.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'levelId': levelId,
      'state': state.name,
      'stars': stars,
      'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    };
    if (extra.isNotEmpty) {
      json['extra'] = extra;
    }
    return json;
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

    final extraRaw = json['extra'];
    Map<String, dynamic> extra = {};
    if (extraRaw is Map<String, dynamic>) {
      extra = Map<String, dynamic>.from(extraRaw);
    } else if (extraRaw is Map) {
      extra = Map<String, dynamic>.from(extraRaw);
    }

    return LevelProgress(
      levelId: rawLevel is num ? rawLevel.toInt() : 0,
      state: LevelCompletionState.fromString(
        rawState is String ? rawState : 'locked',
      ),
      // Bounded to a plausible score; a negative or absurd value is coerced.
      stars: stars < 0 ? 0 : (stars > kMaxLevelStars ? kMaxLevelStars : stars),
      lastPlayedAt:
          rawLastPlayed is String ? DateTime.tryParse(rawLastPlayed) : null,
      extra: extra,
    );
  }

  /// Returns a copy with overridden fields.
  ///
  /// [lastPlayedAt] is nullable, so `null` cannot mean both "leave it alone"
  /// and "clear it". It is passed as a getter to keep the two apart: omit it to
  /// keep the current value, pass `() => null` to clear it deliberately.
  ///
  /// ```dart
  /// progress.copyWith(stars: 3);                     // date untouched
  /// progress.copyWith(lastPlayedAt: () => null);     // date cleared
  /// progress.copyWith(lastPlayedAt: () => DateTime.now());
  /// ```
  LevelProgress copyWith({
    int? levelId,
    LevelCompletionState? state,
    int? stars,
    DateTime? Function()? lastPlayedAt,
    Map<String, dynamic>? extra,
  }) {
    return LevelProgress(
      levelId: levelId ?? this.levelId,
      state: state ?? this.state,
      stars: stars ?? this.stars,
      lastPlayedAt: lastPlayedAt == null ? this.lastPlayedAt : lastPlayedAt(),
      extra: extra ?? Map<String, dynamic>.from(this.extra),
    );
  }

  /// Compared by value.
  ///
  /// The view diffs the progress it resolved against the progress it cached to
  /// decide whether a chunk needs rebuilding. Without this that diff is
  /// reference equality, so a host resolver that builds a fresh `LevelProgress`
  /// per call — the obvious way to write one — reported a change on every
  /// sweep and rebuilt a chunk that had not moved.
  ///
  /// [extra] is compared shallowly, by its own entries' equality: it is
  /// host-owned JSON, and a deep walk of arbitrary nested maps is not something
  /// a per-frame diff can afford.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LevelProgress) return false;
    if (other.levelId != levelId ||
        other.state != state ||
        other.stars != stars ||
        other.lastPlayedAt != lastPlayedAt ||
        other.extra.length != extra.length) {
      return false;
    }
    for (final entry in extra.entries) {
      if (!other.extra.containsKey(entry.key) ||
          other.extra[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        levelId,
        state,
        stars,
        lastPlayedAt,
        extra.length,
      );
}
