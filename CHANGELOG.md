# Changelog

All notable changes to this package are documented in this file.

## 2.0.0

A single breaking release. Every item below has a copy-pasteable escape hatch,
and nothing deprecated in 1.1.0 was removed — those removals are scheduled for
3.0.0.

### BREAKING — rewards are injectable

`CompleteLevelUseCase` no longer calls `isBossLevel` and `kMvpLootTable`
directly. Both are constructor parameters now, and both keep their old values
as defaults, so `const CompleteLevelUseCase()` behaves exactly as it did in
1.x.

```dart
const useCase = CompleteLevelUseCase(
  bossRule: myBossRule,   // bool Function(int levelId), defaults to isBossLevel
  lootTable: myTable,     // List<LootTableEntry>, defaults to kMvpLootTable
);
```

`rollBossReward` gained an optional `table` parameter, also defaulting to
`kMvpLootTable`, so existing calls compile unchanged.

What did change behaviourally: an empty table, a negative weight or weights
totalling `0` now throw an `ArgumentError` instead of silently rolling against
`kMvpLootTable`. If you were relying on that fall back — you were not, it was
unreachable with the built-in table — pass `kMvpLootTable` explicitly.

`isBossLevel` stays public. Its reason for being public changed: it used to be
the only way to ask the question, and it is now the default value of
`bossRule`, which a default value has to be to stay overridable.

See [ADR-0003](docs/adrs/0003-odul-sistemini-enjekte-edilebilir-kilmak.md).

## 1.1.0

No breaking changes: a consumer on `^1.0.0` upgrades without touching its code.
Saved progress written by 1.0.0 loads unchanged, and progress with an empty
`extra` serialises byte-for-byte as 1.0.0 did.

### Added

- `SagaProgress.extra` and `LevelProgress.extra` for host-owned data that
  round-trips through JSON without touching the library's own fields.
- `SagaProgressStars` extension for star counting and range analysis
  (`totalStars`, `starsInRange`, `completedCountInRange`, `isRangePerfect`).
- `LootTableOdds` extension with `totalWeight`, `probabilityOf` and
  `rarityOdds` to compute precise drop rates from loot table weights.
- `SagaChunkContext`, carrying a chunk's levels, progress and dominant biome.
- `chunkDecorationBuilder` and `chunkEpisodeHeaderBuilder` on
  `SagaInfiniteMapView` (and `chunkDecorationBuilder` on `MapChunkWidget`),
  which receive a `SagaChunkContext` instead of a bare chunk index.
- `SagaMapDecoration.atLevel`, a band aligned to a level rather than to raw
  coordinates. It spans the chunk's full lateral width and ignores the path's
  wander.
- `onChunkEnter` and `onLevelReached` listeners on `SagaInfiniteMapView`, with
  hysteresis so scrolling back and forth across a seam does not spam them.
- `SagaNodeInteractionPolicy.canLongPress`, controlling when a long press is
  accepted.
- `onLevelLongPress` convenience callback on `SagaInfiniteMapView`.
- The long-press action is reachable from the keyboard (Shift+F10 and the
  context-menu key) and exposed to screen readers.

### Changed

- Locked nodes no longer emit long-press callbacks by default. This is the one
  intentional behaviour change in this release; restore the old behaviour with
  a `SagaNodeInteractionPolicy` subclass overriding `canLongPress`.

### Deprecated

These keep working and only emit a warning; they are scheduled for removal in
3.0.0, so they survive the whole 2.x line.

- `decorationBuilder` and `episodeHeaderBuilder`, which take a bare chunk
  index, along with the `SagaMapLegacyDecorationBuilder` and
  `SagaLegacyEpisodeHeaderBuilder` typedefs. They keep their 1.0.0 signatures
  and behaviour — use `chunkDecorationBuilder` and `chunkEpisodeHeaderBuilder`
  for the context-aware versions. Passing both a builder and its `chunk`
  counterpart asserts.

### Fixed

- Screen readers announced the first level as "Level 0".
- `SagaMapDecoration.atLevel` was never handled by the chunk renderer: it
  crashed with a null-check on `pathPosition`, and collapsed to a zero-size box
  past that. It now renders as the documented band, aligned to its level.
- `onChunkEnter` handed listeners a context with an empty `progress` map when
  the chunk had not been rendered yet. It now resolves progress the same way
  the builders do.
- `MapChunkWidget.chunkContext` was a required parameter, which would have
  broken existing hosts. It is optional and derived from the widget's own
  levels, chunk index and progress resolver when omitted.

### Docs

- Level ids are documented as zero-based.
- README gains golden-rendered screenshots of the 1.1.0 additions, plus a note
  that a chunk paints its own base background when `backgroundConfig` is
  `none()`, which covers decorations.
- ADR-0001, ADR-0004 and ADR-0006 are now `Accepted`.

### Example

- The demo showcases every 1.1.0 addition: context-aware decoration and episode
  builders, `atLevel` boss bands, `onChunkEnter` / `onLevelReached` /
  `onLevelLongPress`, loot drop-rate odds, star totals, and a bookmark stored in
  `LevelProgress.extra`.

### Coming in 2.0.0

Pre-announced breaking changes, so hosts can plan:

- Boss milestones move to `id % 5 == 4` from `id % 15 == 0` (ADR-0002).
- `flutter_svg` is dropped from the core package (ADR-0008).

## 1.0.0

First stable release.

### Map

- Vertical and horizontal level paths. `pathAxis` is the single source of
  truth for orientation: it drives coordinate mapping, which viewport
  dimension counts as lateral, and the scroll direction.
- Curved paths via `pathCurvature`, from `0` (straight) to `1` (fully
  rounded). The spline interpolates, so nodes stay put and only the line
  between them bends.
- The walked stretch of path is painted apart from the road ahead
  (`pathProgressPosition` plus the theme's upcoming colours).
- Infinite chunked scrolling with lazy loading, an optional chunk budget,
  and eviction for long maps.
- Pinch-to-zoom applied at the layout level, so the scroll extent stays
  correct and the path is rasterised at its final size.
- Right-to-left support: a horizontal map mirrors its path axis.
- Responsive policies for node size, spacing, zoom, touch target, camera
  padding, lateral extent and scroll sensitivity — each resolved per
  breakpoint from the real viewport.
- Background layers: solid colour, image, SVG, and multi-asset sequences
  with loop / clamp / empty overflow behaviour.
- Scenery via `decorationBuilder`, episode banners via
  `episodeHeaderBuilder`, and a parallax layer that lags the scroll.

### Character

- A character that walks the path, with the library computing position,
  facing and motion while the host draws it — so sprite sheets, Lottie,
  Rive, GIF or plain Flutter all plug into the same builder.
- Arc-length parameterisation, so travel keeps an even pace through curves
  rather than crawling and racing.
- `SagaCharacterController`: step-by-step movement with a per-node pause,
  distance-proportional timing, interruption that resumes in place, a
  hopping gait, and reduced-motion support.
- Camera following, an opening position so a returning player resumes where
  they left off, and `SagaMapCameraController` for scrolling to a level on
  demand.
- Optional gates that hold the character back until the host opens them.
- A dependency-free sprite-sheet player: horizontal, vertical and grid
  layouts, clip ranges, loop / once / ping-pong, 2x and 3x assets, and
  `FilterQuality.none` for crisp pixel art.

### Domain

- Deterministic level generation from a seed, with each level derived from
  `(globalSeed, levelId)` alone — generating a deep chunk costs the same as
  the first, and the same seed always produces the same map across runs and
  platforms.
- Progression models with JSON persistence, a completion use-case that
  keeps the best run and only unlocks forward, and a weighted boss loot
  table that rewards on first clear.
- Repository contracts with in-memory implementations for demos and tests.
- Procedural biome/terrain generation with bounded allocation.

### Accessibility

- Level nodes are exposed to screen readers as buttons carrying the level
  number, state and star count, disabled when the interaction policy
  rejects taps.
- Keyboard navigation: Tab visits nodes in level order rather than paint
  order, Enter and Space activate, and locked nodes are skipped.
- Visual size and touch target are independent, so a node can shrink below
  the 44dp accessibility minimum visually while staying comfortably
  tappable.
- Animations are suppressed when the platform asks for reduced motion.

### Robustness

- Deserialization tolerates malformed or tampered saves: every field is
  type-checked rather than cast, and impossible states are clamped on load.
- Generation and terrain allocation are bounded, so a bad configuration
  fails fast instead of exhausting memory.
