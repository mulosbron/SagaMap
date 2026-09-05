import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// Coverage for the domain and configuration surface that shipped untested.

void main() {
  group('SagaMapBackgroundConfig', () {
    const paths = ['a.png', 'b.png', 'c.png'];

    String? resolve(
      SagaMapBackgroundConfig config,
      int chunkIndex,
    ) {
      final widget = config.buildBackgroundWidget(null as dynamic, chunkIndex: chunkIndex);
      return widget is Image ? (widget.image as AssetImage).assetName : null;
    }

    test('indexes assets directly while they last', () {
      const config = SagaMapBackgroundConfig.imageAssets(assetPaths: paths);
      expect(resolve(config, 0), 'a.png');
      expect(resolve(config, 2), 'c.png');
    });

    test('loop wraps past the end', () {
      const config = SagaMapBackgroundConfig.imageAssets(
        assetPaths: paths,
        overflowBehavior: SagaMapBackgroundOverflowBehavior.loop,
      );
      expect(resolve(config, 3), 'a.png');
      expect(resolve(config, 7), 'b.png');
    });

    test('clampLast repeats the final asset', () {
      const config = SagaMapBackgroundConfig.imageAssets(
        assetPaths: paths,
        overflowBehavior: SagaMapBackgroundOverflowBehavior.clampLast,
      );
      expect(resolve(config, 3), 'c.png');
      expect(resolve(config, 99), 'c.png');
    });

    test('empty renders nothing past the end', () {
      const config = SagaMapBackgroundConfig.imageAssets(
        assetPaths: paths,
        overflowBehavior: SagaMapBackgroundOverflowBehavior.empty,
      );
      expect(config.buildBackgroundWidget(null as dynamic, chunkIndex: 3), isA<SizedBox>());
    });

    test('none and colour modes need no asset', () {
      expect(
        const SagaMapBackgroundConfig.none().buildBackgroundWidget(null as dynamic),
        isA<SizedBox>(),
      );
      expect(
        const SagaMapBackgroundConfig.color(color: Colors.red)
            .buildBackgroundWidget(null as dynamic),
        isA<ColoredBox>(),
      );
    });
  });

  group('getDominantBiomeId', () {
    LevelData level(int id, String biomeId) =>
        LevelData(id: id, position: const SagaPoint(0.5, 0), biomeId: biomeId);

    test('returns the most frequent biome', () {
      expect(
        getDominantBiomeId([
          level(0, kBiomeIdForest),
          level(1, kBiomeIdDesert),
          level(2, kBiomeIdDesert),
        ]),
        kBiomeIdDesert,
      );
    });

    test('falls back to forest for an empty chunk', () {
      expect(getDominantBiomeId(const []), kBiomeIdForest);
    });

    test('breaks ties deterministically', () {
      final levels = [level(0, kBiomeIdGlacier), level(1, kBiomeIdDesert)];
      expect(getDominantBiomeId(levels), getDominantBiomeId(levels));
    });
  });

  group('loot table', () {
    test('marks every fifteenth level a boss, except level zero', () {
      expect(isBossLevel(0), isFalse);
      expect(isBossLevel(15), isTrue);
      expect(isBossLevel(30), isTrue);
      expect(isBossLevel(14), isFalse);
    });

    test('rolls the same reward for the same level and seed', () {
      final now = DateTime.utc(2026, 1, 1);
      final first = rollBossReward(levelId: 15, globalSeed: 42, now: now);
      final second = rollBossReward(levelId: 15, globalSeed: 42, now: now);

      expect(first.itemId, second.itemId);
      expect(first.obtainedFromLevelId, 15);
      expect(first.obtainedAt, now);
    });

    test('only ever rolls items from the table', () {
      final ids = kMvpLootTable.map((entry) => entry.itemId).toSet();
      for (var levelId = 15; levelId <= 600; levelId += 15) {
        final reward = rollBossReward(levelId: levelId, globalSeed: 3);
        expect(ids, contains(reward.itemId));
      }
    });
  });

  group('deserialization hardening', () {
    test('a malformed LevelProgress payload does not throw', () {
      // A tampered or corrupt save must never crash the app. Every field is
      // read defensively; nonsense coerces to a safe default.
      expect(
        () => LevelProgress.fromJson(const {
          'levelId': 'not a number',
          'state': 42,
          'stars': 'lots',
          'lastPlayedAt': 999,
        }),
        returnsNormally,
      );

      final restored = LevelProgress.fromJson(const {});
      expect(restored.levelId, 0);
      expect(restored.state, LevelCompletionState.locked);
      expect(restored.stars, 0);
      expect(restored.lastPlayedAt, isNull);
    });

    test('an absurd star count is clamped on load', () {
      expect(
        LevelProgress.fromJson(const {'levelId': 1, 'stars': 2147483647}).stars,
        kMaxLevelStars,
      );
      expect(
        LevelProgress.fromJson(const {'levelId': 1, 'stars': -9}).stars,
        0,
      );
    });

    test('a non-string timestamp is ignored rather than fatal', () {
      // The old code did `json['lastPlayedAt'] as String` after a null check,
      // which threw on a numeric value.
      expect(
        LevelProgress.fromJson(const {'levelId': 1, 'lastPlayedAt': 12345})
            .lastPlayedAt,
        isNull,
      );
    });

    test('a negative unlock pointer is clamped to zero', () {
      final restored = SagaProgress.fromJson(const {
        'currentMaxUnlockedLevelId': -5,
        'levels': <String, dynamic>{},
      });
      expect(restored.currentMaxUnlockedLevelId, 0);
    });

    test('SagaProgress tolerates a garbage payload', () {
      expect(
        () => SagaProgress.fromJson(const {
          'currentMaxUnlockedLevelId': 'x',
          'levels': 'not a map',
        }),
        returnsNormally,
      );
    });
  });

  group('resource bounds', () {
    const generator = ProceduralBiomeGenerator();

    test('an oversized terrain grid is rejected, not allocated', () {
      // Without the cap this would try to allocate several 100k×100k matrices
      // and exhaust memory.
      expect(
        () => generator.generate(
          seed: 1,
          config: const TerrainMapConfig(width: 100000, height: 100000),
        ),
        throwsA(isA<InvalidTerrainConfigException>()),
      );
    });

    test('a single oversized dimension is rejected', () {
      expect(
        () => generator.generate(
          seed: 1,
          config: const TerrainMapConfig(
            width: kMaxTerrainDimension + 1,
            height: 4,
          ),
        ),
        throwsA(isA<InvalidTerrainConfigException>()),
      );
    });

    test('a grid within bounds still works', () {
      final terrain = generator.generate(
        seed: 1,
        config: const TerrainMapConfig(width: 64, height: 64),
      );
      expect(terrain.width, 64);
    });

    test('biomeSpan of zero is rejected at construction', () {
      expect(
        () => SagaMapConfig(minX: 0.2, maxX: 0.8, stepHeight: 0.08, biomeSpan: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('serialization', () {
    test('InventoryItem survives a round trip', () {
      final item = InventoryItem(
        itemId: 'ancient_crown_01',
        itemName: 'Ancient Crown',
        rarity: InventoryRarity.legendary,
        obtainedFromLevelId: 30,
        obtainedAt: DateTime.utc(2026, 3, 2, 10, 30),
      );

      final restored = InventoryItem.fromJson(item.toJson());

      expect(restored.itemId, item.itemId);
      expect(restored.rarity, InventoryRarity.legendary);
      expect(restored.obtainedFromLevelId, 30);
      expect(restored.obtainedAt, item.obtainedAt);
    });

    test('InventoryItem tolerates a corrupt payload', () {
      final restored = InventoryItem.fromJson(const {});
      expect(restored.itemId, 'unknown_item');
      expect(restored.rarity, InventoryRarity.common);
      expect(restored.obtainedAt.millisecondsSinceEpoch, 0);
    });

    test('an unknown rarity falls back to common', () {
      expect(InventoryRarity.fromString('mythic'), InventoryRarity.common);
      expect(InventoryRarity.fromString('rare'), InventoryRarity.rare);
    });

    test('LevelProgress survives a round trip', () {
      final progress = LevelProgress(
        levelId: 4,
        state: LevelCompletionState.completed,
        stars: 3,
        lastPlayedAt: DateTime.utc(2026, 5, 5),
      );

      final restored = LevelProgress.fromJson(progress.toJson());

      expect(restored.levelId, 4);
      expect(restored.state, LevelCompletionState.completed);
      expect(restored.stars, 3);
      expect(restored.lastPlayedAt, progress.lastPlayedAt);
    });

    test('SagaProgress survives a round trip', () {
      const progress = SagaProgress(
        currentMaxUnlockedLevelId: 3,
        levels: {
          0: LevelProgress(
              levelId: 0, state: LevelCompletionState.completed, stars: 2),
          3: LevelProgress(levelId: 3, state: LevelCompletionState.unlocked),
        },
      );

      final restored = SagaProgress.fromJson(progress.toJson());

      expect(restored.currentMaxUnlockedLevelId, 3);
      expect(restored.levels.keys.toSet(), {0, 3});
      expect(restored.levels[0]?.stars, 2);
    });

    test('an empty level map falls back to the initial state', () {
      // Documented behaviour, not an accident: a payload with no levels is
      // treated as a fresh save rather than an unplayable map.
      final restored = SagaProgress.fromJson(const {
        'currentMaxUnlockedLevelId': 0,
        'levels': <String, dynamic>{},
      });
      expect(restored.levels[0]?.state, LevelCompletionState.unlocked);
    });

    test('SagaProgress.initial unlocks only level zero', () {
      final initial = SagaProgress.initial();
      expect(initial.currentMaxUnlockedLevelId, 0);
      expect(initial.levels[0]?.state, LevelCompletionState.unlocked);
      expect(initial.levels[1], isNull);
    });
  });

  group('in-memory repositories', () {
    test('inventory stores and returns items', () async {
      final repository = InMemoryInventoryRepository();
      expect(await repository.getItems(), isEmpty);

      await repository.addItem(
        InventoryItem(
          itemId: 'forest_hat_01',
          itemName: 'Forest Hat',
          rarity: InventoryRarity.common,
          obtainedFromLevelId: 15,
          obtainedAt: DateTime.utc(2026),
        ),
      );

      final items = await repository.getItems();
      expect(items, hasLength(1));
      expect(() => items.add(items.first), throwsUnsupportedError);
    });

    test('progress repository round-trips and defaults its seed', () async {
      final repository = InMemorySagaProgressRepository();
      expect(await repository.loadGlobalSeed(), kDefaultSagaMapSeed);

      final loaded = await repository.loadProgress();
      expect(loaded.currentMaxUnlockedLevelId, 0);

      await repository.saveProgress(
        loaded.copyWith(currentMaxUnlockedLevelId: 9),
      );
      expect((await repository.loadProgress()).currentMaxUnlockedLevelId, 9);
    });

    test('an explicit seed is honoured', () async {
      final repository = InMemorySagaProgressRepository(globalSeed: 1234);
      expect(await repository.loadGlobalSeed(), 1234);
    });
  });

  group('ProceduralBiomeGenerator', () {
    const generator = ProceduralBiomeGenerator();
    const config = TerrainMapConfig(width: 16, height: 12);

    test('fills every cell of the requested grid', () {
      final terrain = generator.generate(seed: 42, config: config);

      expect(terrain.width, 16);
      expect(terrain.height, 12);
      expect(terrain.cells, hasLength(12));
      expect(terrain.cells.first, hasLength(16));
      for (final row in terrain.cells) {
        for (final cell in row) {
          expect(cell.occupancy, anyOf(0, 1));
          expect(cell.biomeIndex, inInclusiveRange(0, 2));
        }
      }
    });

    test('cells agree with the occupancy and biome layers', () {
      final terrain = generator.generate(seed: 7, config: config);
      for (var y = 0; y < terrain.height; y++) {
        for (var x = 0; x < terrain.width; x++) {
          expect(terrain.cells[y][x].occupancy, terrain.occupancy[y][x]);
          expect(terrain.cells[y][x].biomeIndex, terrain.biomeIndices[y][x]);
        }
      }
    });

    test('the same seed produces the same terrain', () {
      expect(
        generator.generate(seed: 5, config: config),
        equals(generator.generate(seed: 5, config: config)),
      );
    });

    test('different seeds produce different terrain', () {
      expect(
        generator.generate(seed: 5, config: config),
        isNot(equals(generator.generate(seed: 6, config: config))),
      );
    });

    test('rejects a degenerate config', () {
      expect(
        () => generator.generate(
          seed: 1,
          config: const TerrainMapConfig(width: 0, height: 4),
        ),
        throwsA(isA<InvalidTerrainConfigException>()),
      );
      expect(
        () => generator.generate(
          seed: 1,
          config: const TerrainMapConfig(width: 4, height: 4, frequency: 0),
        ),
        throwsA(isA<InvalidTerrainConfigException>()),
      );
    });

    test('an InvalidTerrainConfigException is a SagaDomainException', () {
      const exception = InvalidTerrainConfigException('bad');
      expect(exception, isA<SagaDomainException>());
      expect(exception.toString(), contains('bad'));
    });
  });

  group('SagaMapConfig', () {
    test('spans the levels a chunk holds', () {
      const config = SagaMapConfig.defaultConfig;
      expect(config.spanForLevelCount(20), closeTo(0.08 * 20, 1e-12));
    });

    test('exposes its lateral band', () {
      const config = SagaMapConfig.defaultConfig;
      expect(config.lateralBounds.min, config.minX);
      expect(config.lateralBounds.max, config.maxX);
    });
  });

  test('the no-op logger swallows output', () {
    const logger = NoopSagaLogger();
    expect(() {
      logger.debug('x');
      logger.error('y', Exception('z'), StackTrace.current);
    }, returnsNormally);
  });
}
