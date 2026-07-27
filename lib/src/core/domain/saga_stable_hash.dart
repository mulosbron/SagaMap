/// Deterministic integer hashing for seed derivation.
///
/// `Object.hash` must not be used for anything persisted or regenerated: it
/// mixes in `identityHashCode(Object)`, which is randomised per program run, so
/// the same inputs produce different results on every launch. A map generated
/// from it would rearrange itself every time the app restarted.
///
/// These functions use a fixed-constant murmur3 finaliser, with every
/// multiplication split into 16-bit halves so the intermediate values stay below
/// 2^53 and behave identically on the web, where Dart ints are doubles.
library;

const int _mask32 = 0xFFFFFFFF;

/// 32-bit multiply that is exact on both native and web number representations.
int _mul32(int a, int b) {
  final aLow = a & 0xFFFF;
  final aHigh = (a >> 16) & 0xFFFF;
  final low = aLow * b;
  final high = ((aHigh * b) & 0xFFFF) << 16;
  return (low + high) & _mask32;
}

/// murmur3 finaliser: avalanches a 32-bit value.
int _fmix32(int value) {
  var hash = value & _mask32;
  hash ^= hash >> 16;
  hash = _mul32(hash, 0x85EBCA6B);
  hash ^= hash >> 13;
  hash = _mul32(hash, 0xC2B2AE35);
  hash ^= hash >> 16;
  return hash & _mask32;
}

/// Combines [values] into a stable 32-bit hash.
///
/// Identical inputs always yield an identical result — across runs, platforms
/// and releases.
int stableHash(List<int> values) {
  var hash = 0x811C9DC5;
  for (final value in values) {
    hash = _fmix32(hash ^ (value & _mask32));
    // Fold in the high bits so ids beyond 2^32 still separate.
    hash = _fmix32(hash ^ ((value >> 32) & _mask32));
  }
  return hash & _mask32;
}

/// Stable hash of [values] mapped to the `[0, 1)` range.
double stableUnitValue(List<int> values) => stableHash(values) / 0x100000000;
