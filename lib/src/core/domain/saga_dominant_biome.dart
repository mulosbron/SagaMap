import 'biome_ids.dart';
import 'models/level_data.dart';

/// Returns the most frequent biome id in [levels].
String getDominantBiomeId(List<LevelData> levels) {
  if (levels.isEmpty) return kBiomeIdForest;
  final counts = <String, int>{};
  for (final level in levels) {
    counts[level.biomeId] = (counts[level.biomeId] ?? 0) + 1;
  }
  String? dominant;
  int maxCount = 0;
  for (final entry in counts.entries) {
    if (entry.value > maxCount) {
      maxCount = entry.value;
      dominant = entry.key;
    }
  }
  return dominant ?? kBiomeIdForest;
}
