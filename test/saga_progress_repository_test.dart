import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/src/adapters/repositories/in_memory_saga_progress_repository.dart';
import 'package:saga_map/src/core/domain/saga_seed_constants.dart';

void main() {
  group('InMemorySagaProgressRepository', () {
    test('round-trip save and load global seed', () async {
      final repository = InMemorySagaProgressRepository();
      
      await repository.saveGlobalSeed(12345);
      final seed = await repository.loadGlobalSeed();
      
      expect(seed, 12345);
    });

    test('loadGlobalSeed returns default seed when nothing is written', () async {
      final repository = InMemorySagaProgressRepository();
      
      final seed = await repository.loadGlobalSeed();
      
      expect(seed, kDefaultSagaMapSeed);
    });
  });
}
