import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/level_progress.dart';
import '../../core/domain/saga_dominant_biome.dart';

/// Everything a decoration or header builder needs about one chunk.
class SagaChunkContext {
  /// The index of the chunk in the infinite map.
  final int chunkIndex;

  /// The levels in this chunk.
  /// Never empty for a chunk being built, even if the chunk was previously evicted.
  final List<LevelData> levels;

  /// The progress of the levels in this chunk.
  /// Scoped to this chunk's level ids, not the whole map.
  final Map<int, LevelProgress> progress;

  /// The dominant biome id of this chunk, calculated based on the levels.
  final String dominantBiomeId;

  /// Creates a context for one chunk.
  ///
  /// [levels] and [progress] are copied into unmodifiable views, and
  /// [dominantBiomeId] is derived from [levels], so the context is a stable
  /// snapshot a builder can hold without the map changing under it.
  SagaChunkContext({
    required this.chunkIndex,
    required List<LevelData> levels,
    required Map<int, LevelProgress> progress,
  })  : levels = List.unmodifiable(levels),
        progress = Map.unmodifiable(progress),
        dominantBiomeId = getDominantBiomeId(levels);
}
