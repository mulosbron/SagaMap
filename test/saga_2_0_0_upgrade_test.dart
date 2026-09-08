import 'dart:convert';
import 'dart:io';

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

/// Map config these escape-hatch tests generate against.
const _upgradeConfig = SagaMapConfig.defaultConfig;

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
    // Pins CHANGELOG 2.0.0, row 1: "Boss levels moved by one".
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

    // Pins CHANGELOG 2.0.0, row 2: "Rewards are injectable".
    test('the reward defaults are unchanged', () {
      // "Defaults are preserved" is the claim in the changelog; this is it.
      const useCase = CompleteLevelUseCase();
      // `same`, not equality: a bare function value would be read as a
      // predicate matcher and silently pass on nonsense.
      expect(useCase.bossRule, same(isBossLevel));
      expect(useCase.lootTable, same(kMvpLootTable));
      expect(useCase.canUnlock, isNull);
    });

    // Pins CHANGELOG 2.0.0, row 3: "Gates block progression".
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

    // Pins CHANGELOG 2.0.0, row 4: "Biome ids come from config".
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

    // A-07.02. The changelog names `saveGlobalSeed` as one of only two items
    // that need code from the host — "implement one method on your repository"
    // — and this gate never called it. The escape hatch nobody exercises is
    // the one that breaks.
    //
    // Pins CHANGELOG 2.0.0, row 5: "`saveGlobalSeed` added".
    test('saveGlobalSeed is implementable and round-trips', () async {
      final repository = InMemorySagaProgressRepository();

      // The default is minted, not zero, and reading twice is stable.
      final minted = await repository.loadGlobalSeed();
      expect(await repository.loadGlobalSeed(), minted);

      await repository.saveGlobalSeed(4242);
      expect(await repository.loadGlobalSeed(), 4242);

      // The seed a host writes is the seed the map generates from, which is
      // the whole reason the method exists — and the reason the trust boundary
      // in its doc comment is a boundary.
      const generator = SagaMapLevelGenerator();
      final atMinted = generator.generateLevels(
        globalSeed: minted,
        config: _upgradeConfig,
        startLevelId: 0,
        count: 3,
      );
      final at4242 = generator.generateLevels(
        globalSeed: 4242,
        config: _upgradeConfig,
        startLevelId: 0,
        count: 3,
      );
      expect(at4242.first.position.x, isNot(atMinted.first.position.x));
    });

    // A-07.03. `flutter_svg` was dropped, and the changelog's escape hatch is
    // "take the dependency yourself and pass a `builder`". The gate checked
    // that the *other* background modes still worked and never built the
    // builder mode at all — so the one path a 1.1.0 SVG host must migrate to
    // was the one path untested.
    //
    // Pins CHANGELOG 2.0.0, row 10: "`SagaProgress` is no longer `const`".
    test('SagaProgress copies defensively instead of being const', () {
      final levels = <int, LevelProgress>{
        0: const LevelProgress(
          levelId: 0,
          state: LevelCompletionState.completed,
        ),
      };
      final extra = <String, dynamic>{'tickets': 2};

      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 1,
        levels: levels,
        extra: extra,
      );

      // The escape hatch is simply dropping `const`; what you get for it is
      // that a caller mutating a returned map throws rather than silently
      // rewriting state the host believes it persisted.
      expect(
          () => progress.levels[5] = const LevelProgress(
                levelId: 5,
                state: LevelCompletionState.unlocked,
              ),
          throwsUnsupportedError);
      expect(() => progress.extra['tickets'] = 99, throwsUnsupportedError);

      // And the copy is a copy: mutating the source map afterwards does not
      // reach inside.
      levels[9] = const LevelProgress(
        levelId: 9,
        state: LevelCompletionState.unlocked,
      );
      extra['tickets'] = 99;
      expect(progress.levels.containsKey(9), isFalse);
      expect(progress.extra['tickets'], 2);
    });

    // Pins CHANGELOG 2.0.0, row 11: "`copyWith` getter signatures for
    // nullable fields".
    test('the nullable copyWith fields take a getter, and can clear', () {
      final stamp = DateTime.utc(2026, 5, 1, 9, 30);
      final progress = LevelProgress(
        levelId: 4,
        state: LevelCompletionState.completed,
        stars: 2,
        lastPlayedAt: stamp,
      );

      // Omit it: untouched. This is what the old `lastPlayedAt: null` meant,
      // and the only thing it could mean.
      expect(progress.copyWith(stars: 3).lastPlayedAt, stamp);

      // `() => value`: the migration for anyone who passed a value directly.
      final moved = DateTime.utc(2026, 6, 2);
      expect(progress.copyWith(lastPlayedAt: () => moved).lastPlayedAt, moved);

      // `() => null`: newly expressible at all.
      expect(progress.copyWith(lastPlayedAt: () => null).lastPlayedAt, isNull);

      // The same shape on the responsive config, where the unconstrained
      // lateral extent was unreachable once set.
      final config = SagaMapResponsiveConfig.defaults.copyWith(
        maxLateralExtentPolicy: () => const SagaMapValuePolicy.all(400),
      );
      expect(config.maxLateralExtentPolicy, isNotNull);
      expect(
        config
            .copyWith(maxLateralExtentPolicy: () => null)
            .maxLateralExtentPolicy,
        isNull,
      );
    });

    // Pins CHANGELOG 2.0.0, rows 6 and 12: "`flutter_svg` dropped" and
    // "`buildBackgroundWidget` takes a `BuildContext`" — the call below is
    // the migrated form.
    testWidgets('SagaMapBackgroundConfig.builder is the way back to SVG',
        (tester) async {
      var builderCalls = 0;
      final config = SagaMapBackgroundConfig.builder(
        (context, chunkIndex) {
          builderCalls++;
          // Stands in for `SvgPicture.asset(...)`: the package no longer knows
          // or cares what this widget is, which is the point of the change.
          return const ColoredBox(
            color: Color(0xFF123456),
            child: SizedBox.expand(key: ValueKey('host-svg')),
          );
        },
      );

      expect(config.kind, SagaMapBackgroundKind.builder);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => config.buildBackgroundWidget(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(builderCalls, greaterThan(0));
      expect(find.byKey(const ValueKey('host-svg')), findsOneWidget);
    });

    testWidgets('a map renders with the builder background in place',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      const generator = SagaMapLevelGenerator();
      final controller = SagaInfiniteMapController(
        sectionsPerChunk: 10,
        initialChunkCount: 2,
        chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
          globalSeed: 42,
          config: _upgradeConfig,
          startLevelId: chunkIndex * sectionsPerChunk,
          count: sectionsPerChunk,
        ),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SagaInfiniteMapView(
              controller: controller,
              chunkExtent: 600,
              chunkSpanNormalized: _upgradeConfig.spanForLevelCount(10),
              biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
              backgroundConfig: SagaMapBackgroundConfig.builder(
                (context, chunkIndex) => const ColoredBox(
                  color: Color(0xFF123456),
                  child: SizedBox.expand(),
                ),
              ),
              nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(MapChunkWidget), findsWidgets);
    });

    // Pins CHANGELOG 2.0.0, row 6: "`flutter_svg` dropped" — the modes
    // that did *not* change, beside the builder tests above that did.
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

  // Pins CHANGELOG 2.0.0, row 9: "The unlock pointer is reconciled against its
  // records", and the "Migration — 1.x saves" section beside it.
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

  group('the version gate names what it pins (A-07)', () {
    // A gate that does not say which promise each test keeps drifts out of
    // step with the promises silently — which is how `saveGlobalSeed` and the
    // `flutter_svg` builder ended up as the only two items needing host code
    // and the only two the gate never exercised.
    test('every numbered breaking-change row is pinned by a test', () {
      final changelog = File('CHANGELOG.md').readAsStringSync();
      final start = changelog.indexOf('\n## 2.0.0');
      final next = changelog.indexOf('\n## ', start + 1);
      final section =
          changelog.substring(start, next < 0 ? changelog.length : next);

      final rows = RegExp(r'^\| (\d+) \| .* \| .* \|$', multiLine: true)
          .allMatches(section)
          .map((m) => int.parse(m.group(1)!))
          .toSet();
      expect(rows, isNotEmpty);

      final source =
          File('test/saga_2_0_0_upgrade_test.dart').readAsStringSync();
      // `rows 6 and 12` pins both, so every number in the clause counts.
      final pinned = <int>{
        for (final m in RegExp(r'Pins CHANGELOG 2\.0\.0, rows? ([\d and,]+)')
            .allMatches(source))
          ...RegExp(r'\d+')
              .allMatches(m.group(1)!)
              .map((n) => int.parse(n.group(0)!)),
      };

      // Rows whose "what you do about it" column is "Nothing" need no hatch to
      // pin; the six that ask for host code, plus the save-format ones, do.
      const mustBePinned = {1, 2, 3, 4, 5, 6, 9, 10, 11, 12};
      final missing = mustBePinned.difference(pinned).toList()..sort();

      expect(
        missing,
        isEmpty,
        reason: 'these breaking-change rows have no test naming them: '
            '$missing. Add a `// Pins CHANGELOG 2.0.0, row N:` comment to the '
            'test that exercises the escape hatch, or write that test.',
      );
      expect(
        pinned.difference(rows),
        isEmpty,
        reason: 'a test pins a changelog row that does not exist',
      );
    });
  });
}
