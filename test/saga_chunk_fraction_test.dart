import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/saga_map.dart';

void main() {
  group('chunkFractionForLevel', () {
    test('throws if levelsPerChunk is <= 0', () {
      expect(() => chunkFractionForLevel(levelIndexInChunk: 0, levelsPerChunk: 0), throwsArgumentError);
    });

    test('throws if levelIndex is out of bounds', () {
      expect(() => chunkFractionForLevel(levelIndexInChunk: -1, levelsPerChunk: 2), throwsArgumentError);
      expect(() => chunkFractionForLevel(levelIndexInChunk: 2, levelsPerChunk: 2), throwsArgumentError);
    });

    test('centers single level', () {
      expect(chunkFractionForLevel(levelIndexInChunk: 0, levelsPerChunk: 1, edgeInsetFraction: 0.1), 0.5);
    });

    test('distributes levels evenly without inset', () {
      expect(chunkFractionForLevel(levelIndexInChunk: 0, levelsPerChunk: 3), 0.0);
      expect(chunkFractionForLevel(levelIndexInChunk: 1, levelsPerChunk: 3), 0.5);
      expect(chunkFractionForLevel(levelIndexInChunk: 2, levelsPerChunk: 3), 1.0);
    });

    test('distributes levels evenly with inset', () {
      expect(chunkFractionForLevel(levelIndexInChunk: 0, levelsPerChunk: 3, edgeInsetFraction: 0.1), 0.1);
      expect(chunkFractionForLevel(levelIndexInChunk: 1, levelsPerChunk: 3, edgeInsetFraction: 0.1), 0.5);
      expect(chunkFractionForLevel(levelIndexInChunk: 2, levelsPerChunk: 3, edgeInsetFraction: 0.1), 0.9);
    });
  });
}
