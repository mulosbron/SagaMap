import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// The 2.0.0 release gate: what a consumer already has on disk, and in its
/// source, still works.
///
/// Every breaking item in 2.0.0 ships with an escape hatch. These tests pin the
/// hatches, so a later refactor cannot quietly close one.

/// Verbatim payload as 1.1.0 wrote it: string level keys, an `extra` map, and
/// no fields 2.0.0 added. Frozen as a literal on purpose — regenerating it from
/// today's `toJson` would test the round-trip against itself.
const String _savedBy110 = '''
{
  "currentMaxUnlockedLevelId": 16,
  "levels": {
    "0": {
      "levelId": 0,
      "state": "completed",
      "stars": 3,
      "lastPlayedAt": "2026-04-28T20:00:00.000Z"
    },
    "14": {
      "levelId": 14,
      "state": "completed",
      "stars": 2,
      "lastPlayedAt": "2026-05-01T09:30:00.000Z",
      "extra": {"bookmarked": true}
    },
    "15": {
      "levelId": 15,
      "state": "completed",
      "stars": 1
    },
    "16": {
      "levelId": 16,
      "state": "unlocked",
      "stars": 0
    }
  },
  "extra": {"lastWorld": "verdant", "tickets": 2}
}
''';

/// A second 1.1.0 payload, written the way 1.x actually let a host write one:
/// a pointer far ahead of a **sparse** `levels` map. 1.x read a missing record
/// as "unlocked if it sits below the pointer", so persisting a record per level
/// was never required.
///
/// The frozen fixture above cannot exercise this: its pointer is 16 and its
/// highest record is 16, so the 2.0.0 reconciliation is a no-op there and the
/// version gate never sees the hazard it exists to guard.
const String _sparseSavedBy110 = '''
{
  "currentMaxUnlockedLevelId": 20,
  "levels": {
    "0": {
      "levelId": 0,
      "state": "completed",
      "stars": 3
    },
    "1": {
      "levelId": 1,
      "state": "completed",
      "stars": 2
    },
    "2": {
      "levelId": 2,
      "state": "completed",
      "stars": 1
    }
  },
  "extra": {"lastWorld": "verdant"}
}
''';

/// The 1.0.0 / 1.1.0 boss formula, the documented way back.
bool _legacyBossRule(int levelId) => levelId > 0 && levelId % 15 == 0;

void main() {
  group('a save written by 1.1.0 loads in 2.0.0', () {
    final json = jsonDecode(_savedBy110) as Map<String, dynamic>;
    final progress = SagaProgress.fromJson(json);

    test('the library fields survive', () {
      expect(progress.currentMaxUnlockedLevelId, 16);
      expect(progress.levels.keys.toList()..sort(), [0, 14, 15, 16]);
      expect(progress.levels[0]?.state, LevelCompletionState.completed);
      expect(progress.levels[0]?.stars, 3);
      expect(progress.levels[0]?.lastPlayedAt, DateTime.utc(2026, 4, 28, 20));
      expect(progress.levels[16]?.state, LevelCompletionState.unlocked);
    });

    test('host-owned extra survives at both levels', () {
      expect(progress.extra['lastWorld'], 'verdant');
      expect(progress.extra['tickets'], 2);
      expect(progress.levels[14]?.extra['bookmarked'], true);
    });

    test('re-saving keeps everything', () {
      final reloaded = SagaProgress.fromJson(progress.toJson());

      expect(reloaded.currentMaxUnlockedLevelId,
          progress.currentMaxUnlockedLevelId);
      expect(reloaded.extra, progress.extra);
      expect(reloaded.levels[14]?.extra, progress.levels[14]?.extra);
      expect(reloaded.levels[0]?.stars, 3);
    });

    test('completing on top of it still works', () {
      const useCase = CompleteLevelUseCase();

      final result = useCase.execute(
        currentProgress: progress,
        levelId: 16,
        globalSeed: 42,
        stars: 2,
      );

      expect(
          result.nextProgress.levels[17]?.state, LevelCompletionState.unlocked);
      expect(result.nextProgress.currentMaxUnlockedLevelId, 17);
      // Untouched levels, and the host's data on them, are carried through.
      expect(result.nextProgress.levels[14]?.extra['bookmarked'], true);
      expect(result.nextProgress.extra['tickets'], 2);
    });
  });

  group('every 2.0.0 breaking change has a working escape hatch', () {
    test('bossRule restores the 1.x boss placement', () {
      const legacy = CompleteLevelUseCase(bossRule: _legacyBossRule);
      // enforceUnlockOrder ships on, so the player has to have got here.
      final start = SagaProgress(
        currentMaxUnlockedLevelId: 15,
        levels: {
          for (var id = 0; id <= 15; id++)
            id: LevelProgress(
              levelId: id,
              state: LevelCompletionState.unlocked,
            ),
        },
      );

      expect(
        legacy
            .execute(currentProgress: start, levelId: 15, globalSeed: 42)
            .reward,
        isNotNull,
      );
      expect(
        legacy
            .execute(currentProgress: start, levelId: 14, globalSeed: 42)
            .reward,
        isNull,
      );
    });

    test('the reward defaults are unchanged', () {
      // "Defaults are preserved" is the claim in the changelog; this is it.
      const useCase = CompleteLevelUseCase();
      // `same`, not equality: a bare function value would be read as a
      // predicate matcher and silently pass on nonsense.
      expect(useCase.bossRule, same(isBossLevel));
      expect(useCase.lootTable, same(kMvpLootTable));
      expect(useCase.canUnlock, isNull);
    });

    test('the gate hooks default to 1.x behaviour', () {
      const policy = SagaNodeInteractionPolicy();
      expect(policy.isReachable, isNull);

      const level = LevelData(id: 3, position: SagaPoint(0, 0), biomeId: 'x');
      expect(
        policy.canTap(
          level,
          const LevelProgress(levelId: 3, state: LevelCompletionState.unlocked),
        ),
        isTrue,
      );

      const useCase = CompleteLevelUseCase();
      final result = useCase.execute(
        currentProgress: SagaProgress.initial(),
        levelId: 0,
        globalSeed: 1,
      );
      expect(result.unlockBlocked, isFalse);
      expect(
          result.nextProgress.levels[1]?.state, LevelCompletionState.unlocked);
    });

    test('omitting biomeIds generates the same ids as before', () {
      expect(SagaMapConfig.defaultConfig.biomeIds, kSagaBiomeIds);

      const generator = SagaMapLevelGenerator();
      final levels = generator.generateLevels(
        globalSeed: 42,
        config: SagaMapConfig.defaultConfig,
        startLevelId: 0,
        count: 160,
      );
      for (final level in levels) {
        final expected = kSagaBiomeIds[
            (level.id ~/ SagaMapConfig.defaultConfig.biomeSpan) %
                kSagaBiomeIds.length];
        expect(level.biomeId, expected, reason: 'level ${level.id}');
      }
    });

    test('the non-SVG background modes are untouched', () {
      const none = SagaMapBackgroundConfig.none();
      const colour = SagaMapBackgroundConfig.color(color: Color(0xFF112233));
      const image =
          SagaMapBackgroundConfig.imageAsset(assetPath: 'assets/world.png');

      expect(none.kind, SagaMapBackgroundKind.none);
      expect(colour.kind, SagaMapBackgroundKind.color);
      expect(image.kind, SagaMapBackgroundKind.imageAsset);
      expect(image.assetPath, 'assets/world.png');
    });
  });

  group('a sparse 1.x save has a named way across (A-01)', () {
    final json = jsonDecode(_sparseSavedBy110) as Map<String, dynamic>;

    test('a plain load reconciles the pointer, and does not do it silently',
        () {
      final clamps = <SagaProgressClamp>[];
      final progress = SagaProgress.fromJson(json, onClamp: clamps.add);

      // Three completions open exactly one successor, so 20 becomes 3. That is
      // the behaviour the CHANGELOG's "Migration — 1.x saves" section names;
      // what must never come back is it happening with nothing reported.
      expect(progress.currentMaxUnlockedLevelId, 3);
      expect(clamps, hasLength(1));
      expect(clamps.single.storedPointer, 20);
      expect(clamps.single.lostGround, isTrue);
    });

    test('and with the order guard on, every level above it shuts', () {
      final progress = SagaProgress.fromJson(json);
      final result = const CompleteLevelUseCase().execute(
        currentProgress: progress,
        levelId: 11,
        globalSeed: 3,
      );
      expect(result.outcome, CompleteLevelOutcome.rejectedUnreached);
    });

    test('migrateFrom1x is the escape hatch, and it is exported', () {
      final progress = SagaProgress.migrateFrom1x(json);

      expect(progress.currentMaxUnlockedLevelId, 20);
      expect(progress.levels[11]?.state, LevelCompletionState.unlocked);
      expect(progress.levels[0]?.stars, 3);
      expect(progress.extra['lastWorld'], 'verdant');

      // The player can play on, and the migrated save no longer clamps.
      final result = const CompleteLevelUseCase().execute(
        currentProgress: progress,
        levelId: 11,
        globalSeed: 3,
      );
      expect(result.outcome, CompleteLevelOutcome.applied);

      final clamps = <SagaProgressClamp>[];
      SagaProgress.fromJson(progress.toJson(), onClamp: clamps.add);
      expect(clamps, isEmpty);
    });
  });

  group('nothing deprecated in 1.1.0 was removed', () {
    // 1.1.0 promised these survive the whole 2.x line. Naming them here is what
    // makes a stray cleanup in 2.x fail a test instead of a consumer's build.
    test('the legacy builder typedefs are still nameable', () {
      // ignore: deprecated_member_use_from_same_package
      const SagaMapLegacyDecorationBuilder? decorations = null;
      // ignore: deprecated_member_use_from_same_package
      const SagaLegacyEpisodeHeaderBuilder? headers = null;

      expect(decorations, isNull);
      expect(headers, isNull);
    });

    test('the legacy builder parameters still take a bare chunk index', () {
      final view = SagaInfiniteMapView(
        controller: SagaInfiniteMapController(
          sectionsPerChunk: 10,
          chunkLoader: (chunkIndex, sectionsPerChunk) => const [],
        ),
        chunkExtent: 600,
        chunkSpanNormalized: 0.8,
        biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
        nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
        // ignore: deprecated_member_use_from_same_package
        decorationBuilder: (context, chunkIndex) => const [],
        // ignore: deprecated_member_use_from_same_package
        episodeHeaderBuilder: (context, chunkIndex) => null,
      );
      addTearDown(view.controller.dispose);

      // ignore: deprecated_member_use_from_same_package
      expect(view.decorationBuilder, isNotNull);
      // ignore: deprecated_member_use_from_same_package
      expect(view.episodeHeaderBuilder, isNotNull);
    });
  });
}
