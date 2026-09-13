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

  /// Per-level host data — a no-mistake streak, a bookmark.
  final Map<String, dynamic> extra;

  /// Best star score per alternate replay mode, keyed by the host's mode id.
  ///
  /// The default mode's score stays in [stars]; this map holds only the
  /// others — `'hard'`, `'mirror'`, whatever the host calls them. A mode run
  /// never touches [stars] or [state], and its stars are not counted by
  /// `SagaProgressStars.totalStars`, so they are not spendable either: a host
  /// that wants them in its economy sums them itself. Read one with
  /// [starsFor].
  ///
  /// Each value is bounded to `[0, kMaxLevelStars]` on load, like [stars].
  final Map<String, int> starsByMode;

  const LevelProgress({
    required this.levelId,
    required this.state,
    this.stars = 0,
    this.lastPlayedAt,
    this.extra = const {},
    this.starsByMode = const {},
  });

  /// Throws an [ArgumentError] if [modeId] cannot name an alternate mode.
  ///
  /// The default mode is `null` — its score is [stars] — so an id that reads
  /// as "the default" is refused rather than stored beside it: the empty
  /// string, an id of only whitespace, and `'default'`. Accepting one would
  /// give the default mode two scores free to disagree.
  static void checkModeId(String modeId) {
    if (_namesDefaultMode(modeId)) {
      throw ArgumentError.value(
        modeId,
        'modeId',
        'Names the default mode, which is null.',
      );
    }
  }

  /// This level's best score in [modeId], where `null` is the default mode.
  ///
  /// A mode never played scores `0`. Throws an [ArgumentError] for a [modeId]
  /// [checkModeId] refuses.
  int starsFor(String? modeId) {
    if (modeId == null) return stars;
    checkModeId(modeId);
    return starsByMode[modeId] ?? 0;
  }

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
    // Omitted while empty, so a save that never used a mode is byte-for-byte
    // what 2.0.0 wrote.
    if (starsByMode.isNotEmpty) {
      json['starsByMode'] = starsByMode;
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

    // A wrong-typed map reads as no modes played. Inside a well-typed one each
    // entry is judged alone — a bad score costs that mode, not every mode —
    // and a key naming the default mode is dropped, since `stars` already
    // holds that score and the two must not disagree.
    final modesRaw = json['starsByMode'];
    final starsByMode = <String, int>{};
    if (modesRaw is Map) {
      for (final entry in modesRaw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! num || _namesDefaultMode(key)) {
          continue;
        }
        starsByMode[key] = _clampStars(value.toInt());
      }
    }

    return LevelProgress(
      levelId: rawLevel is num ? rawLevel.toInt() : 0,
      state: LevelCompletionState.fromString(
        rawState is String ? rawState : 'locked',
      ),
      // Bounded to a plausible score; a negative or absurd value is coerced.
      stars: _clampStars(stars),
      lastPlayedAt:
          rawLastPlayed is String ? DateTime.tryParse(rawLastPlayed) : null,
      extra: extra,
      starsByMode: starsByMode,
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
    Map<String, int>? starsByMode,
  }) {
    return LevelProgress(
      levelId: levelId ?? this.levelId,
      state: state ?? this.state,
      stars: stars ?? this.stars,
      lastPlayedAt: lastPlayedAt == null ? this.lastPlayedAt : lastPlayedAt(),
      extra: extra ?? Map<String, dynamic>.from(this.extra),
      starsByMode: starsByMode ?? Map<String, int>.from(this.starsByMode),
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
  /// a per-frame diff can afford. [starsByMode] holds only integers, so its
  /// entry-by-entry comparison is complete.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LevelProgress) return false;
    if (other.levelId != levelId ||
        other.state != state ||
        other.stars != stars ||
        other.lastPlayedAt != lastPlayedAt ||
        other.extra.length != extra.length ||
        other.starsByMode.length != starsByMode.length) {
      return false;
    }
    for (final entry in extra.entries) {
      if (!other.extra.containsKey(entry.key) ||
          other.extra[entry.key] != entry.value) {
        return false;
      }
    }
    for (final entry in starsByMode.entries) {
      if (other.starsByMode[entry.key] != entry.value) return false;
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
        starsByMode.length,
      );
}

bool _namesDefaultMode(String modeId) =>
    modeId.trim().isEmpty || modeId == 'default';

int _clampStars(int stars) =>
    stars < 0 ? 0 : (stars > kMaxLevelStars ? kMaxLevelStars : stars);
