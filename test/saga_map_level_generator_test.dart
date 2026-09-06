import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

void main() {
  group('SagaMapLevelGenerator', () {
    test('generates deterministic level data for same input', () {
      const generator = SagaMapLevelGenerator();

      final first = generator.generateLevels(
        globalSeed: 42,
        config: SagaMapConfig.defaultConfig,
        startLevelId: 0,
        count: 8,
      );
      final second = generator.generateLevels(
        globalSeed: 42,
        config: SagaMapConfig.defaultConfig,
        startLevelId: 0,
        count: 8,
      );

      expect(second.length, first.length);
      for (var i = 0; i < first.length; i++) {
        expect(second[i].id, first[i].id);
        expect(second[i].biomeId, first[i].biomeId);
        expect(second[i].position.x, first[i].position.x);
        expect(second[i].position.y, first[i].position.y);
      }
    });

    test('a level is identical regardless of which chunk requested it', () {
      const generator = SagaMapLevelGenerator();
      const config = SagaMapConfig.defaultConfig;

      // The whole chunked map rests on this: chunk 3 and a single-level request
      // must agree on where level 60 sits, or the path breaks at every seam.
      final asChunk = generator.generateLevels(
        globalSeed: 7,
        config: config,
        startLevelId: 60,
        count: 20,
      );
      final wholeRun = generator.generateLevels(
        globalSeed: 7,
        config: config,
        startLevelId: 0,
        count: 80,
      );

      for (final level in asChunk) {
        expect(level, equals(wholeRun[level.id]));
      }
    });

    test('level positions advance by exactly stepHeight', () {
      const generator = SagaMapLevelGenerator();
      const config = SagaMapConfig.defaultConfig;

      final levels = generator.generateLevels(
        globalSeed: 3,
        config: config,
        startLevelId: 500,
        count: 5,
      );

      // Accumulated addition would have drifted by this depth; the renderer
      // compares these against a multiplied chunk origin.
      for (final level in levels) {
        expect(
          level.position.y,
          moreOrLessEquals(level.id * config.stepHeight, epsilon: 1e-12),
        );
      }
    });

    test('a deep chunk costs no more than a shallow one', () {
      const generator = SagaMapLevelGenerator();
      const config = SagaMapConfig.defaultConfig;

      List<LevelData> run(int startLevelId) => generator.generateLevels(
            globalSeed: 5,
            config: config,
            startLevelId: startLevelId,
            count: 20,
          );

      run(0);
      final shallow = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        run(0);
      }
      shallow.stop();

      final deep = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        run(500000);
      }
      deep.stop();

      // Generation used to replay the sequence from level zero, making this
      // ratio grow without bound. Generous bound: this asserts the absence of
      // O(startLevelId) work, not a precise timing.
      expect(
        deep.elapsedMicroseconds,
        lessThan(shallow.elapsedMicroseconds * 10 + 10000),
      );
    });

    test('keeps generated x positions within config limits', () {
      const config = SagaMapConfig(
        minX: 0.15,
        maxX: 0.60,
        stepHeight: 0.05,
        biomeSpan: 10,
      );
      const generator = SagaMapLevelGenerator();
      final levels = generator.generateLevels(
        globalSeed: 99,
        config: config,
        startLevelId: 0,
        count: 40,
      );

      expect(levels, isNotEmpty);
      for (final level in levels) {
        expect(level.position.x, inInclusiveRange(config.minX, config.maxX));
      }
    });
  });

  group('SagaMapConfig.biomeIds', () {
    const generator = SagaMapLevelGenerator();

    List<String> biomesFor(SagaMapConfig config, int count) => generator
        .generateLevels(
          globalSeed: 42,
          config: config,
          startLevelId: 0,
          count: count,
        )
        .map((level) => level.biomeId)
        .toList();

    test('omitting biomeIds generates exactly the 1.x sequence', () {
      // The 1.x generator read `kSagaBiomeIds` directly. Anything else here is
      // a silent re-theming of every existing map.
      const config = SagaMapConfig.defaultConfig;
      final generated = biomesFor(config, 400);

      for (var levelId = 0; levelId < generated.length; levelId++) {
        final expected = kSagaBiomeIds[
            (levelId ~/ config.biomeSpan) % kSagaBiomeIds.length];
        expect(generated[levelId], expected, reason: 'level $levelId');
      }
      expect(config.biomeIds, kSagaBiomeIds);
    });

    test('a ten-id list cycles through all ten', () {
      final realms = [for (var i = 0; i < 10; i++) 'realm_$i'];
      final config =
          SagaMapConfig.defaultConfig.copyWith(biomeSpan: 5, biomeIds: realms);

      final generated = biomesFor(config, 50);
      expect(generated.toSet(), realms.toSet());
      for (var levelId = 0; levelId < 50; levelId++) {
        expect(generated[levelId], realms[levelId ~/ 5],
            reason: 'level $levelId');
      }
    });

    test('a one-id list puts every level in the same biome', () {
      final config =
          SagaMapConfig.defaultConfig.copyWith(biomeIds: const ['only']);
      expect(biomesFor(config, 200).toSet(), {'only'});
    });

    test('an empty list throws instead of dividing by zero', () {
      final config =
          SagaMapConfig.defaultConfig.copyWith(biomeIds: const <String>[]);

      expect(
        () => generator.generateLevels(
          globalSeed: 1,
          config: config,
          startLevelId: 0,
          count: 1,
        ),
        throwsArgumentError,
      );
    });

    test('biomeSpan and list length together set the cycle length', () {
      // span 5 x 10 ids: the cycle closes after 50 levels, and level 50 is
      // back on the first realm.
      final realms = [for (var i = 0; i < 10; i++) 'realm_$i'];
      final config =
          SagaMapConfig.defaultConfig.copyWith(biomeSpan: 5, biomeIds: realms);

      final generated = biomesFor(config, 105);
      expect(generated[0], 'realm_0');
      expect(generated[49], 'realm_9');
      expect(generated[50], 'realm_0');
      expect(generated[100], 'realm_0');
    });

    test('duplicate ids weight a biome rather than being deduplicated', () {
      final config = SagaMapConfig.defaultConfig.copyWith(
        biomeSpan: 1,
        biomeIds: const ['forest', 'forest', 'desert'],
      );

      expect(biomesFor(config, 6),
          ['forest', 'forest', 'desert', 'forest', 'forest', 'desert']);
    });

    test('copyWith leaves the other fields alone', () {
      const base = SagaMapConfig.defaultConfig;
      final copy = base.copyWith(biomeIds: const ['a']);

      expect(copy.minX, base.minX);
      expect(copy.maxX, base.maxX);
      expect(copy.stepHeight, base.stepHeight);
      expect(copy.biomeSpan, base.biomeSpan);
      expect(copy.biomeIds, const ['a']);
    });
  });
}
