library;

/// Forest biome identifier used by level and theme systems.
const String kBiomeIdForest = 'forest';

/// Desert biome identifier used by level and theme systems.
const String kBiomeIdDesert = 'desert';

/// Glacier biome identifier used by level and theme systems.
const String kBiomeIdGlacier = 'glacier';

/// Ordered biome ids used by deterministic generator cycling.
const List<String> kSagaBiomeIds = [
  kBiomeIdForest,
  kBiomeIdDesert,
  kBiomeIdGlacier,
];
