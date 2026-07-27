import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

void main() {
  test('public API basic models work', () {
    const level = LevelData(
      id: 1,
      position: SagaPoint(0.1, 0.2),
      biomeId: kBiomeIdForest,
    );

    final progress = SagaProgress.initial();

    expect(level.id, 1);
    expect(progress.currentMaxUnlockedLevelId, 0);
    expect(progress.levels.containsKey(0), isTrue);
  });
}
