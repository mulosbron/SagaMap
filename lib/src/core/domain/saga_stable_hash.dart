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

/// Marker mixed in for a negative input, so `-n` and `n` do not collide.
const int _signSalt = 0x9E3779B9;

/// Combines [values] into a stable 32-bit hash.
///
/// Identical inputs always yield an identical result — across runs, platforms
/// and releases. Values above 2^32 and negative values are supported and hash
/// identically on the Dart VM and under dart2js; see
/// `test/saga_stable_hash_test.dart` for the golden vectors that pin it.
int stableHash(List<int> values) {
  var hash = 0x811C9DC5;
  for (final value in values) {
    // The sign is carried explicitly rather than through the high word: a
    // 64-bit two's-complement representation does not exist on the web, where
    // ints are doubles, so `value >> 32` would disagree across platforms for
    // every negative input.
    final negative = value < 0;
    final magnitude = negative ? -value : value;

    hash = _fmix32(hash ^ (magnitude & _mask32));
    // Fold in the high bits so ids beyond 2^32 still separate. Integer
    // division, not `>> 32`: a 32-bit shift is undefined on the web, where it
    // silently truncates to the low word instead — the one line in this file
    // that needed 64-bit shift semantics and could not have them.
    hash = _fmix32(hash ^ ((magnitude ~/ 0x100000000) & _mask32));
    if (negative) hash = _fmix32(hash ^ _signSalt);
  }
  return hash & _mask32;
}

/// Stable hash of [values] mapped to the `[0, 1)` range.
double stableUnitValue(List<int> values) => stableHash(values) / 0x100000000;
