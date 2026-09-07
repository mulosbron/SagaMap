import 'level_progress.dart';

/// What [SagaProgress.fromJson] changed when it reconciled a stored unlock
/// pointer with the records beside it.
///
/// Handed to `fromJson`'s `onClamp` callback. Clamping is silent by default —
/// it has to be, since `fromJson` is called on every load — but a host that
/// upgrades a 1.x install needs to know it happened, because to a player a
/// dropped pointer looks exactly like lost progress. See
/// [SagaProgress.migrateFrom1x].
class SagaProgressClamp {
  const SagaProgressClamp({
    required this.storedPointer,
    required this.clampedTo,
    required this.completedCeiling,
  });

  /// The pointer as it was written on disk.
  final int storedPointer;

  /// The pointer this load will use instead.
  final int clampedTo;

  /// One past the highest **completed** level found in the payload, or `0`
  /// when the payload records no completed level at all.
  final int completedCeiling;

  /// Whether the pointer moved backwards — the case that costs a player
  /// progress, as opposed to a negative pointer being raised to `0`.
  bool get lostGround => clampedTo < storedPointer;

  @override
  String toString() =>
      'SagaProgressClamp(stored: $storedPointer, clamped to: $clampedTo, '
      'completed ceiling: $completedCeiling)';
}

/// Aggregate progression model for all known levels.
class SagaProgress {
  final int currentMaxUnlockedLevelId;

  /// Per-level records, keyed by level id. Unmodifiable.
  ///
  /// **Empty means uninitialised.** `fromJson` reads an empty map as a fresh
  /// save and returns [SagaProgress.initial]'s levels instead, so `levels: {}`
  /// does not survive a round trip — unlike [extra] beside it, which does.
  /// That asymmetry is deliberate: since 2.0.0 a level with no record reads as
  /// locked, so an empty map loaded faithfully is a map on which nothing can be
  /// tapped. A host that needs "no levels" as a real state should carry that
  /// flag in [extra].
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

  /// Restores progress from a serialized payload.
  ///
  /// **Sanitises rather than trusts.** A save file is host-controlled and, on a
  /// device the player owns, player-controlled: wrong types are dropped,
  /// unparseable level keys are skipped, a negative unlock pointer becomes `0`
  /// and a pointer beyond what the payload has *earned* is clamped down to it.
  /// What comes back is always a self-consistent [SagaProgress], never a
  /// faithful echo of the bytes on disk.
  ///
  /// The ceiling is folded over **completed** records only, not over every
  /// key. A record's presence proves nothing — a tampered save could name
  /// level `999998` as `locked` and, folding over keys, lift the pointer to
  /// `999999` with it. A `completed` record is the only one the package itself
  /// writes as a consequence of play, so it is the only one the ceiling may
  /// rest on. With no completed record the ceiling is `0`: nothing has been
  /// cleared, so nothing past the first level has been opened.
  ///
  /// One pointer above that ceiling survives anyway: the one the payload
  /// records as reachable *at the pointer itself*, in `unlocked` or
  /// `completed` state. That is the host that jumped ahead deliberately — a
  /// chapter-skip purchase, a debug build, `enforceUnlockOrder: false` — and
  /// wrote the record to say so, and its saves must round-trip. The rule this
  /// leaves is simply: **a pointer must be justified by its own record or by
  /// a completion below it**, never by a record for some unrelated level.
  ///
  /// Pass [onClamp] to be told when the pointer actually moved. A 1.x save
  /// with a sparse `levels` map — 1.x let a host persist the pointer without a
  /// record per level — will clamp here, and with `enforceUnlockOrder` on by
  /// default in 2.0.0 every level above the new pointer then refuses to
  /// complete. That reads to the player as erased progress. Use
  /// [migrateFrom1x] once, at upgrade time, to convert such a save instead.
  static SagaProgress fromJson(
    Map<String, dynamic> json, {
    void Function(SagaProgressClamp clamp)? onClamp,
  }) {
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

    // An empty level map means "uninitialised", not "deliberately empty", and
    // does not round-trip as one. That is the deliberate choice of the two the
    // asymmetry with `extra` invites — `extra: {}` survives, `levels: {}` does
    // not. Since 2.0.0 a level with no record reads as locked, so loading an
    // empty map faithfully would produce a map on which nothing is tappable:
    // an unplayable save is a worse answer to a truncated file than a fresh
    // one. Hosts that need "no levels" as a state should carry it in `extra`.
    final resolvedLevels =
        levels.isNotEmpty ? levels : SagaProgress.initial().levels;

    // Reconcile the pointer with the map it points into. A save claiming
    // `currentMaxUnlockedLevelId: 9999` next to two recorded levels used to
    // load happily, and with `enforceUnlockOrder` on that single integer is the
    // only thing standing between a player and completing any level id. The
    // rule: the pointer may reach one past the highest *completed* level (the
    // successor that completion opens) and no further. Clamped rather than
    // thrown, matching the negative-pointer clamp above — a save that will not
    // load is worse for a player than one that loads honest.
    var highestCompleted = -1;
    for (final entry in resolvedLevels.entries) {
      if (entry.value.state == LevelCompletionState.completed &&
          entry.key > highestCompleted) {
        highestCompleted = entry.key;
      }
    }
    final ceiling = highestCompleted + 1;
    // A pointer above the earned ceiling still stands if the payload records
    // the pointed-at level as reachable in its own right — that is the host
    // that deliberately jumped ahead (a chapter-skip purchase, a debug build)
    // and wrote the record to prove it. What no longer works is lifting the
    // pointer with a record for some *other* level.
    final atPointer = resolvedLevels[unlocked];
    final selfJustified = atPointer != null &&
        atPointer.state != LevelCompletionState.locked;
    final int clamped;
    if (unlocked < 0) {
      clamped = 0;
    } else if (unlocked > ceiling && !selfJustified) {
      clamped = ceiling;
    } else {
      clamped = unlocked;
    }
    if (clamped != unlocked) {
      onClamp?.call(SagaProgressClamp(
        storedPointer: unlocked,
        clampedTo: clamped,
        completedCeiling: ceiling,
      ));
    }

    return SagaProgress(
      currentMaxUnlockedLevelId: clamped,
      levels: resolvedLevels,
      extra: extra,
    );
  }

  /// Loads a save written by 1.x **without** clamping its unlock pointer.
  ///
  /// 1.x read a missing level record as "unlocked if it sits below
  /// `currentMaxUnlockedLevelId`", so a host was free to persist a pointer of
  /// `20` beside records for levels `0`, `1` and `2` only. 2.0.0 reads a
  /// missing record as *locked* and reconciles the pointer against the
  /// completed records ([fromJson]), which turns that same save into a pointer
  /// of `3` — and with `enforceUnlockOrder` on, every level above it then
  /// refuses to complete.
  ///
  /// This entry point applies the 1.x reading instead: every id in
  /// `[0, currentMaxUnlockedLevelId]` with no record of its own is backfilled
  /// as [LevelCompletionState.unlocked], and the stored pointer is kept as
  /// written. It grants no stars and completes nothing — it only restores the
  /// reachability the player already had.
  ///
  /// It **trusts the payload's pointer**, which is exactly the guarantee
  /// [fromJson] withholds. Call it once, on a save you know your own 1.x build
  /// wrote, and persist the result with [toJson]; every load after that goes
  /// through [fromJson] as usual. Do not route untrusted or reloaded saves
  /// through it.
  ///
  /// [maxBackfill] bounds the work a hostile pointer can cause — a save
  /// claiming `2000000000` would otherwise allocate that many records. A
  /// pointer above it is clamped to it.
  static SagaProgress migrateFrom1x(
    Map<String, dynamic> json, {
    int maxBackfill = 10000,
  }) {
    final decoded = fromJson(json);
    final rawUnlocked = json['currentMaxUnlockedLevelId'];
    var pointer = rawUnlocked is num ? rawUnlocked.toInt() : 0;
    if (pointer < 0) pointer = 0;
    if (pointer > maxBackfill) pointer = maxBackfill;

    final levels = Map<int, LevelProgress>.from(decoded.levels);
    for (var id = 0; id <= pointer; id++) {
      levels[id] ??= LevelProgress(
        levelId: id,
        state: LevelCompletionState.unlocked,
      );
    }

    return SagaProgress(
      currentMaxUnlockedLevelId: pointer,
      levels: levels,
      extra: decoded.extra,
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
