/// Computes the normalized chunk fraction (0.0 to 1.0) for a given level.
///
/// The levels in a chunk are evenly distributed over the chunk's scroll axis,
/// accounting for edge inset at both ends.
double chunkFractionForLevel({
  required int levelIndexInChunk,
  required int levelsPerChunk,
  double edgeInsetFraction = 0.0,
}) {
  if (levelsPerChunk <= 0) {
    throw ArgumentError.value(levelsPerChunk, 'levelsPerChunk', 'must be positive');
  }
  if (levelIndexInChunk < 0 || levelIndexInChunk >= levelsPerChunk) {
    throw ArgumentError.value(levelIndexInChunk, 'levelIndexInChunk', 'out of bounds');
  }
  
  final clampedInset = edgeInsetFraction.clamp(0.0, 0.5);
  if (levelsPerChunk == 1) {
    return 0.5;
  }
  
  final availableSpan = 1.0 - (2 * clampedInset);
  final step = availableSpan / (levelsPerChunk - 1);
  return clampedInset + (levelIndexInChunk * step);
}
