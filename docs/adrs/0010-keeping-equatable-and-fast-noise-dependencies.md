# 10. Keeping the `equatable` and `fast_noise` dependencies

Date: 2026-09-07

## Status

Accepted — 2.0.0.

## Context

ADR-0008 dropped `flutter_svg` on the grounds that it was a mandatory
dependency carried for a single optional feature. The same reasoning applies,
at a smaller scale, to two more dependencies:

```yaml
# equatable + fast_noise: ProceduralBiomeGenerator.
equatable: ^2.0.5
fast_noise: ^2.0.0
```

Both are used in exactly **one** file inside `lib/`:
`core/domain/terrain/biome_noise_generator.dart` (175 lines). A consumer that
doesn't generate procedural terrain — that is, any setup where the host
supplies its own biome map, which is the supported path since ADR-0007 —
carries both for free.

This isn't an oversight; it's an unwritten tradeoff. It needs an explicit
rationale so it doesn't look inconsistent next to ADR-0008.

## Decision

| Option | Pro | Con |
|---|---|---|
| **A. Keep both** | Procedural terrain works out of the box; two small, pure Dart packages | A consumer who doesn't use it carries two dependencies |
| B. Replace `equatable` with hand-written `==`/`hashCode` | One dependency removed | Hand-written equality in three classes; the rest of the package already hand-writes it (13 `operator ==`) |
| C. Move `fast_noise` into a separate `saga_map_terrain` package | The core stays entirely pure | Two packages, two versions, two CHANGELOGs — the same reasoning ADR-0008 rejected |
| D. Reimplement noise generation inside the package | Zero dependencies | Writing Perlin/simplex correctly and fast is a maintenance burden not worth the weight it saves |

**A is chosen**, but the difference from ADR-0008 is written down explicitly:

`flutter_svg` came with a **drawing library** and its transitive dependencies
(`vector_graphics`, `xml`, `path_parsing`), and it directly contradicted the
package's own philosophy — "the host supplies assets." `equatable` and
`fast_noise`, by contrast, are pure Dart, have essentially no transitive
dependencies, and provide something that isn't an asset a host could supply —
it's the package's own domain logic.

Option B can be revisited separately in 2.1.0: the rest of the package already
hand-writes equality, so `equatable` already stands alone as an exception.
It isn't dropped today because the gain (one pure Dart package) doesn't offset
the cost (hand-written equality and its tests in three classes).

## Consequences

### Positive

- Procedural terrain works with no extra setup.
- The distinction from ADR-0008 is now explicit: the question isn't "is there
  a dependency" but "does this dependency carry something the host could have
  supplied."

### Negative

- A consumer that supplies its own biome map carries both packages for free.
- `equatable` keeps a pattern the rest of the package doesn't follow, confined
  to one file; this inconsistency remains (to be revisited in 2.1.0).
