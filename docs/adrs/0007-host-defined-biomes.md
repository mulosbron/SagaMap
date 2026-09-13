# 7. Exposing biome ids to the host and adding an asset hook to the theme

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

The biome system is closed at two points:

**1. The list is a `const` global.** `kSagaBiomeIds` is fixed at three ids
(`biome_ids.dart:13`) and the generator reads it directly
(`saga_map_level_generator.dart:51`):

```dart
biomeId: kSagaBiomeIds[biomeIndex % kSagaBiomeIds.length],
```

`SagaMapConfig.biomeSpan` makes the **length** of the cycle configurable but
not its **contents**. A host that wants four biomes has no path to extend it.

**2. The theme has no asset hook.** The consumer report says `SagaBiomeTheme`
"only carries 4 colors"; that's not accurate — the class carries 12 fields
(`saga_biome_theme.dart:4-37`): gradients, walked/unwalked path colors, stroke
widths, shadow tokens. The color palette is rich enough.

What's actually missing is the inability to define per-biome **visual
assets**: path-stone texture, node sprite, ground texture. The theme can only
paint, not dress.

The compound result of both: the production consumer has 10 realms, and built
a parallel `SagaRealm` structure instead of using the biome system. The
package's biome subsystem goes unused.

## Decision

### Decision 1 — the biome list moves to config

```dart
class SagaMapConfig {
  /// Biome ids the generator cycles through, in order.
  ///
  /// Defaults to the built-in three. A host with its own realms passes its own
  /// list; [biomeSpan] then sets how many levels each one covers.
  final List<String> biomeIds;   // default: kSagaBiomeIds
}
```

- `kSagaBiomeIds` **is not removed or deprecated** — it remains the default
  value.
- An empty list throws `ArgumentError` (no division by zero in the cycle).
- When `biomeIds` isn't supplied, the generated `biomeId` sequence stays
  byte-identical to 1.x.

### Decision 2 — an opaque asset map on the theme

```dart
class SagaBiomeTheme {
  /// Optional art keys for this biome, resolved by the host.
  ///
  /// The package never loads these; it hands them back to the node and path
  /// builders so one biome can look different from another beyond its colours.
  final Map<String, String> assets;   // default: const {}

  /// A wash applied over the chunk, for biome mood beyond the palette.
  final Color? ambientTint;
}
```

`assets` was chosen opaque — over named fields like `String? pathStoneAsset` or
`String? nodeSprite`. Rationale: the package doesn't **load** these assets, it
only carries them. Named fields would freeze an asset taxonomy the package has
no business knowing; an opaque map lets the host use its own keys and avoids
repeating the trap the package fell into with `flutter_svg` (an assumption
about format, see ADR-0008).

### Breaking scope

`biomeIds` is a **semantic** break: when a host supplies its own list,
`biomeId` values change and `SagaBiomeThemeResolver` encounters unknown ids.
The resolver's fallback behavior must be documented. Goes into 2.0.0.

## Consequences

### Positive
- A host with 10 realms can use the package's biome system without building a
  parallel `SagaRealm` structure; together with ADR-0006, `biomeId` becomes
  functional end to end for the first time (generated → reaches the builder →
  resolved into a theme).
- The `assets` map enables per-biome art direction without the package
  becoming an asset loader.
- `OCP-3` closes: adding a new biome no longer requires changing the package.

### Negative
- **No type safety:** biome ids stay `String`; a misspelled id isn't caught at
  compile time, only falls through in theme resolution at runtime. An `enum`
  was rejected because it would make a host-defined list impossible.
- `SagaBiomeThemeResolver`'s unknown-id behavior is now a contract item;
  leaving it undefined would let a host's map silently mis-color.
- Because `assets` is opaque, there's no IDE completion; keys must be
  demonstrated in the README.
- The interaction between `biomeSpan` and `biomeIds.length` (how many levels
  before a biome changes, how many before the cycle closes) adds a new concept
  to learn; the docs need an example table.

## Related

- Task: T-11
- ADR-0006 (builder context) — gets `biomeId` to the host
- Finding: OCP-3 (`.old/docs/reports/01-solid-uyumluluk-denetimi.md`)
