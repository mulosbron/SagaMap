import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

/// The seed contract: writing is part of it, and reading has no side effects.

void main() {
  group('InMemorySagaProgressRepository', () {
    test('a written seed reads back', () async {
      final repository = InMemorySagaProgressRepository();

      await repository.saveGlobalSeed(12345);

      expect(await repository.loadGlobalSeed(), 12345);
    });

    test('an unwritten seed reads the default', () async {
      final repository = InMemorySagaProgressRepository();

      expect(await repository.loadGlobalSeed(), kDefaultSagaMapSeed);
    });

    test('the constructor seed wins until something is written', () async {
      final repository = InMemorySagaProgressRepository(globalSeed: 99);

      expect(await repository.loadGlobalSeed(), 99);
      await repository.saveGlobalSeed(7);
      expect(await repository.loadGlobalSeed(), 7);
    });

    test('loading never writes', () async {
      // A load that persists a default turns "load" into "load, and possibly
      // change the whole map". Reading repeatedly must be inert.
      final repository = InMemorySagaProgressRepository(globalSeed: 3);

      for (var i = 0; i < 5; i++) {
        expect(await repository.loadGlobalSeed(), 3);
      }
      // And loading progress does not disturb the seed either.
      await repository.loadProgress();
      expect(await repository.loadGlobalSeed(), 3);
    });

    test('a new seed regenerates the map under unchanged progress', () async {
      // The documented consequence: level ids survive, the terrain under them
      // does not.
      const generator = SagaMapLevelGenerator();
      final repository = InMemorySagaProgressRepository(globalSeed: 42);

      List<LevelData> mapFor(int seed) => generator.generateLevels(
            globalSeed: seed,
            config: SagaMapConfig.defaultConfig,
            startLevelId: 0,
            count: 20,
          );

      final before = mapFor(await repository.loadGlobalSeed());
      await repository.saveGlobalSeed(43);
      final after = mapFor(await repository.loadGlobalSeed());

      expect(after.map((l) => l.id), before.map((l) => l.id));
      expect(
        after.any((l) => l.position.x != before[l.id].position.x),
        isTrue,
      );
    });
  });
}
