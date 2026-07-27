import 'saga_seed_constants.dart';
import 'saga_stable_hash.dart';

/// Creates deterministic puzzle seed from map seed, level id and version.
int puzzleSeedForLevel(
  int globalMapSeed,
  int levelId,
  int puzzleVersion,
) {
  return stableHash([globalMapSeed, levelId, puzzleVersion]);
}

/// Convenience overload that uses current [kPuzzleVersion].
int puzzleSeedForLevelWithDefaultVersion(int globalMapSeed, int levelId) {
  return puzzleSeedForLevel(globalMapSeed, levelId, kPuzzleVersion);
}
