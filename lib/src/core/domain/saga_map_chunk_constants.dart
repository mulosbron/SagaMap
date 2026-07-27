/// Default section count generated per infinite-map chunk.
///
/// Used as the default `sectionsPerChunk` of [SagaInfiniteMapController].
const int kSagaMapChunkSize = 20;

// A `kSagaMapMaxLevelCount` constant used to live here as a "safety cap for
// total level count". Nothing enforced it, and a default ceiling would be wrong
// for a map that advertises itself as endless. Bound a map explicitly with
// `SagaInfiniteMapController.maxChunkCount`, or its memory with
// `maxRetainedChunks`.
