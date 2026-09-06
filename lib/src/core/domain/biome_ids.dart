library;

/// Forest biome identifier used by level and theme systems.
const String kBiomeIdForest = 'forest';

/// Desert biome identifier used by level and theme systems.
const String kBiomeIdDesert = 'desert';

/// Glacier biome identifier used by level and theme systems.
const String kBiomeIdGlacier = 'glacier';

/// Ordered biome ids used by deterministic generator cycling.
///
/// This is the default value of `SagaMapConfig.biomeIds`, not a hard limit:
/// a host passes its own list there and the generator cycles through that
/// instead. Kept as a `const` global for exactly that purpose.
const List<String> kSagaBiomeIds = [
  kBiomeIdForest,
  kBiomeIdDesert,
  kBiomeIdGlacier,
];
