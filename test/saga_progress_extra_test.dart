import 'package:flutter_test/flutter_test.dart';
import 'package:saga_map/src/core/domain/models/level_progress.dart';
import 'package:saga_map/src/core/domain/models/saga_progress.dart';
import 'package:saga_map/src/core/domain/usecases/complete_level_usecase.dart';

void main() {
  group('SagaProgress.extra', () {
    test('omits extra key when empty', () {
      final progress = SagaProgress.initial();
      final json = progress.toJson();
      expect(json.containsKey('extra'), isFalse);
    });

    test('reads 1.0.0 format seamlessly', () {
      final json100 = {
        'currentMaxUnlockedLevelId': 2,
        'levels': {
          '0': {
            'levelId': 0,
            'state': 'completed',
            'stars': 3,
          },
        },
      };
      final progress = SagaProgress.fromJson(json100);
      expect(progress.extra, isEmpty);
      expect(progress.currentMaxUnlockedLevelId, 2);
    });

    test('survives round-trip intact', () {
      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 0,
        levels: {},
        extra: {'app.played_times': 42},
      );
      final json = progress.toJson();
      final restored = SagaProgress.fromJson(json);
      expect(restored.extra, equals({'app.played_times': 42}));
    });

    test('preserves nested Maps and Lists in round-trip', () {
      final progress = SagaProgress(
        currentMaxUnlockedLevelId: 0,
        levels: {},
        extra: {
          'app.nested': {
            'foo': 'bar',
            'list': [1, 2, 3],
          },
        },
      );
      final json = progress.toJson();
      final restored = SagaProgress.fromJson(json);
      expect(
        restored.extra['app.nested'],
        equals({
          'foo': 'bar',
          'list': [1, 2, 3],
        }),
      );
    });

    test('yields empty map on invalid string type', () {
      final jsonBad = {
        'currentMaxUnlockedLevelId': 0,
        'levels': {},
        'extra': 'bozuk',
      };
      final progress = SagaProgress.fromJson(jsonBad);
      expect(progress.extra, isEmpty);
    });

    test('yields empty map on null type', () {
      final jsonNull = {
        'currentMaxUnlockedLevelId': 0,
        'levels': {},
        'extra': null,
      };
      final progress = SagaProgress.fromJson(jsonNull);
      expect(progress.extra, isEmpty);
    });

    test('copyWith isolates extra changes', () {
      final original = SagaProgress(
        currentMaxUnlockedLevelId: 5,
        levels: {},
        extra: {'app.a': 1},
      );
      final modified = original.copyWith(extra: {'app.a': 2});
      expect(modified.currentMaxUnlockedLevelId, 5);
      expect(modified.extra, {'app.a': 2});
      expect(original.extra, {'app.a': 1}); // No mutation
    });
  });

  group('LevelProgress.extra', () {
    test('omits extra key when empty', () {
      const level = LevelProgress(
        levelId: 1,
        state: LevelCompletionState.unlocked,
      );
      final json = level.toJson();
      expect(json.containsKey('extra'), isFalse);
    });

    test('reads 1.0.0 format seamlessly', () {
      final json100 = {
        'levelId': 1,
        'state': 'unlocked',
        'stars': 0,
      };
      final level = LevelProgress.fromJson(json100);
      expect(level.extra, isEmpty);
      expect(level.levelId, 1);
    });

    test('survives round-trip intact', () {
      const level = LevelProgress(
        levelId: 1,
        state: LevelCompletionState.completed,
        extra: {'app.streak': 5},
      );
      final json = level.toJson();
      final restored = LevelProgress.fromJson(json);
      expect(restored.extra, equals({'app.streak': 5}));
    });
    
    test('yields empty map on invalid string type', () {
      final jsonBad = {
        'levelId': 1,
        'state': 'completed',
        'extra': 'bozuk',
      };
      final level = LevelProgress.fromJson(jsonBad);
      expect(level.extra, isEmpty);
    });

    test('yields empty map on null type', () {
      final jsonNull = {
        'levelId': 1,
        'state': 'completed',
        'extra': null,
      };
      final level = LevelProgress.fromJson(jsonNull);
      expect(level.extra, isEmpty);
    });
    
    test('preserves extra on re-completion', () {
      final originalProgress = SagaProgress(
        currentMaxUnlockedLevelId: 1,
        levels: {
          1: const LevelProgress(
            levelId: 1,
            state: LevelCompletionState.completed,
            stars: 2,
            extra: {'app.score': 9000},
          ),
          2: const LevelProgress(
            levelId: 2,
            state: LevelCompletionState.unlocked,
          ),
        },
      );
      
      const useCase = CompleteLevelUseCase();
      final result = useCase.execute(
        currentProgress: originalProgress,
        levelId: 1,
        globalSeed: 123,
        stars: 3,
      );
      
      final updatedLevel = result.nextProgress.levels[1]!;
      expect(updatedLevel.stars, 3);
      expect(updatedLevel.extra, equals({'app.score': 9000}));
    });
  });
}
