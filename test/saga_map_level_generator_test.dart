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
}
