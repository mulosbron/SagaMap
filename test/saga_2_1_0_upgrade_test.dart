import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// The 2.1.0 release gate: a minor release, so nothing a 2.0.0 consumer has on
/// disk or in its source may notice the upgrade.

/// Verbatim payload in the shape 2.0.0's `toJson` writes: a null
/// `lastPlayedAt` spelled out, `extra` only where non-empty, and none of the
/// keys 2.1.0 added. Frozen as a literal on purpose — regenerating it from
/// today's `toJson` would test the round trip against itself.
///
/// The host here is the one ADR-0004 anticipated: it kept a spent-star ledger
/// and a pity counter in `extra`, and a per-mode score in a level's `extra`,
/// because 2.0.0 had nowhere else to put them.
const String _savedBy200 = '''
{
  "currentMaxUnlockedLevelId": 15,
  "levels": {
    "0": {
      "levelId": 0,
      "state": "completed",
      "stars": 3,
      "lastPlayedAt": "2026-09-01T10:00:00.000Z"
    },
    "14": {
      "levelId": 14,
      "state": "completed",
      "stars": 2,
      "lastPlayedAt": "2026-09-02T18:30:00.000Z",
      "extra": {"app.hard_stars": 1, "bookmarked": true}
    },
    "15": {
      "levelId": 15,
      "state": "unlocked",
      "stars": 0,
      "lastPlayedAt": null
    }
  },
  "extra": {"app.spent_stars": 4, "app.pity": 3}
}
''';

void main() {
  final json = jsonDecode(_savedBy200) as Map<String, dynamic>;

  group('290.06 — a 2.0.0 save loads in 2.1.0', () {
    final progress = SagaProgress.fromJson(json);

    test('the library fields load as written', () {
      expect(progress.currentMaxUnlockedLevelId, 15);
      expect(progress.levels.keys.toList()..sort(), [0, 14, 15]);
      expect(progress.levels[14]?.stars, 2);
      expect(progress.totalStars, 5);
    });

    test('the new fields load at their defaults', () {
      expect(progress.spentStars, 0);
      expect(progress.availableStars, 5);
      for (final level in progress.levels.values) {
        expect(level.starsByMode, isEmpty, reason: 'level ${level.levelId}');
      }
    });

    test('the host workarounds in extra are carried, not interpreted', () {
      // The package never claims an `extra` key (ADR-0004), so a ledger kept
      // there before 2.1.0 is the host's to migrate, on its own schedule.
      expect(progress.extra['app.spent_stars'], 4);
      expect(progress.extra['app.pity'], 3);
      expect(progress.levels[14]?.extra['app.hard_stars'], 1);
    });
  });

  group('290.07 — with the new fields at their defaults, 2.0.0 JSON out', () {
    test('toJson reproduces the 2.0.0 payload exactly', () {
      final progress = SagaProgress.fromJson(json);
      expect(progress.toJson(), jsonDecode(_savedBy200));
    });

    test('and so does the JSON text, key for key', () {
      final progress = SagaProgress.fromJson(json);
      expect(
        jsonDecode(jsonEncode(progress.toJson())),
        jsonDecode(_savedBy200),
      );
    });

    test('a completion in the default mode adds no 2.1.0 key', () {
      final result = const CompleteLevelUseCase().execute(
        currentProgress: SagaProgress.fromJson(json),
        levelId: 15,
        globalSeed: 42,
        now: DateTime.utc(2026, 9, 13),
      );
      final encoded = jsonEncode(result.nextProgress.toJson());
      expect(encoded.contains('spentStars'), isFalse);
      expect(encoded.contains('starsByMode'), isFalse);
    });
  });

  group('290.05 — no required parameter was added', () {
    test('every 2.0.0 call shape still compiles and runs', () async {
      // Each call below is written exactly as a 2.0.0 consumer wrote it. A new
      // required parameter anywhere on this path fails to compile this file.
      const useCase = CompleteLevelUseCase();
      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 14,
        levels: {
          14: const LevelProgress(
            levelId: 14,
            state: LevelCompletionState.unlocked,
          ),
        },
      );
      final result = useCase.execute(
        currentProgress: progress,
        levelId: 14,
        globalSeed: 7,
      );
      final item = rollBossReward(levelId: 14, globalSeed: 7);
      final copy = progress.copyWith(currentMaxUnlockedLevelId: 14);
      final level = const LevelProgress(
        levelId: 1,
        state: LevelCompletionState.locked,
      ).copyWith(stars: 1);

      expect(result.reward?.itemId, item.itemId);
      expect(copy, progress);
      expect(level.stars, 1);
      expect(
        CompleteLevelResult(nextProgress: progress).outcome,
        CompleteLevelOutcome.applied,
      );
    });
  });
}
