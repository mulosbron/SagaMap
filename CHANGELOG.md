# Changelog

All notable changes to this package are documented in this file.

## 2.0.0

### Added — a path renderer you can inject

`MapChunkWidget.pathRenderer` and `SagaInfiniteMapView.pathRenderer` take a
`SagaMapRenderer<CustomPainter>`. `SagaMapRenderer` described itself as "the
extension point for host-supplied renderers" while nothing in the package
depended on the type, so a host wanting its own path painter had to fork the
widget. Pass nothing and the built-in look is unchanged. Nodes stay on
`nodeBuilder`, which is documented on the interface now rather than implied.

### Performance — progress is resolved when it can have changed

The sweep that resolves every visible level's progress sat unconditionally in
`itemBuilder`, so a host whose `progressResolver` does real work paid
`levelsPerChunk x visibleChunks` lookups on every frame of a pinch, purely to
conclude nothing had changed. It now runs when the host rebuilds the view or a
chunk's levels are replaced, and not otherwise.

### Fixed — sprite sheets no longer corrupt art silently

- `SagaSpritePainter` used only half of `applyBoxFit`'s answer. A cropping fit
  (`cover`, `fitWidth`, `fitHeight`) works by sampling less than the whole
  frame; ignoring the source rect squashed the frame into the box instead of
  cropping it, so those fits quietly distorted every sprite.
- A clip is now checked against the sheet that has to supply it. Constructing
  `SagaSpriteAnimation` with a clip that overruns the sheet throws an
  `ArgumentError`; swapping to one mid-play reports the error and keeps drawing
  a frame the sheet actually has, rather than sampling outside it under nothing
  but a debug assert.
- `didUpdateWidget` branched on `image` and `clip` but not `sheet`, so a swap to
  a smaller sheet left the frame index past the end.

### Fixed — four view lifecycle defects

- A swapped `SagaMapCameraController` was never attached, so every call on the
  new handle silently did nothing. It is now attached (and the old one detached)
  in `didUpdateWidget`.
- Episode headers were absent from every scroll-offset computation, so each one
  shifted the map by a header per chunk and camera targets landed short by a
  growing margin. Declare the header's size with the new
  `SagaInfiniteMapView.episodeHeaderExtent`.
- The character vanished standing exactly on the last level of the last chunk:
  the final point has no segment leaving it, so it resolved to no pose while
  `ownsPathPosition` still claimed the position and no other chunk drew it.
- A controller swap kept the previous world's chunk contexts, which are keyed by
  chunk index alone, so a new seed rendered the old map's nodes until every
  chunk happened to rebuild.

### Breaking — the progression guard ships on, and is decided once

`enforceUnlockOrder` moved from an `execute` parameter defaulting to `false` to
a `CompleteLevelUseCase` constructor field defaulting to `true`. It used to be a
guard a host had to remember at every call site while the shipped default
accepted any level id. `execute` still takes it as an optional override for the
one call that deliberately jumps ahead.

A negative `levelId` is now refused whatever the guard says, and
`SagaProgress.fromJson` clamps `currentMaxUnlockedLevelId` to at most one past
the highest recorded level, so a tampered save cannot hand itself the pointer
the guard rests on. `fromJson` sanitises rather than trusts, and says so.

`rollBossReward` stays public — hosts need it for previews and their own
economies — with its unguarded-mint contract spelled out in full rather than in
one line. The snapshot-based first-clear guard in `execute` is documented on
`CompleteLevelResult.reward` and pinned by a test; closing it structurally needs
the deferred `InventoryRepository` injection (ADR-0003, 2.1.0).

### Breaking — an unrecorded level is now locked

`SagaNodeInteractionPolicy.canTap` treated a `null` `LevelProgress` as tappable.
An unrecorded level became a free progression skip, and the Semantics tree said
"enabled" while the game logic disagreed. It now reads as
`LevelCompletionState.locked`.

The two absences are told apart at `SagaMapRenderContext.resolveProgress`: with
no `progressResolver` at all the host is not modelling progression and every
node reads as unlocked, so a purely navigational map still works out of the box.
A resolver that returns `null` for a level is a tracked map with no record —
locked.

If you relied on the old behaviour, supply a `progressResolver` that returns an
unlocked `LevelProgress` for the levels you want open.

A single breaking release. Every item below has a copy-pasteable escape hatch,
and nothing deprecated in 1.1.0 was removed — those removals stay scheduled for
3.0.0, so the deprecated builders survive the whole 2.x line.

Six breaking changes, in the order you will hit them:

| Change | What you do about it |
| --- | --- |
| Boss levels moved by one | Nothing, or inject `bossRule` to keep 1.x placement |
| Rewards are injectable | Nothing; the defaults are the old values |
| Gates block progression | Nothing; all three hooks default to off |
| Biome ids come from config | Nothing; omitting `biomeIds` is the old sequence |
| `saveGlobalSeed` added | Implement one method on your repository |
| `flutter_svg` dropped | Take the dependency yourself and pass a `builder` |

Only two of those need code from you. The other four are behaviour or contract
changes whose defaults reproduce 1.x exactly.

`SagaProgress`'s constructor is no longer `const`: it now defensively copies
`levels` and `extra` as unmodifiable maps, so mutating a returned map throws
instead of silently corrupting persisted state (matching the inventory
repository's `List.unmodifiable` guarantee). Any `const SagaProgress(...)` call
site must drop the `const` keyword.

**Nothing new was deprecated in 2.0.0.** The removals in this release are
outright, because a deprecated `svgAsset` would have kept the `flutter_svg`
dependency alive, which was the point of removing it.

The one thing this release cannot do for you: **saved reward history**. Boss
levels moved, and the package never wrote to your `InventoryRepository`, so it
cannot migrate what it never owned. See the first section.

### BREAKING — boss levels moved by one

`isBossLevel` is now `levelId >= 0 && levelId % 15 == 14`. It was
`levelId > 0 && levelId % 15 == 0`.

Ids are zero-based, so "every fifteenth level" — the 15th, 30th and 45th a
player sees — is `id % 15 == 14`. The old formula landed on the 16th node and,
because difficulty is `1 + id % 5`, handed the boss the easiest board in the
cycle. The corrected rule aligns three systems at once: every boss id also
satisfies `id % 5 == 4`, so a boss is always a difficulty-5 board.

No signature changed, so this looks like a patch. It is not: the *meaning* of
saved data changes.

**Players may have been rewarded at ids 15/30/45 and never at 14/29/44; the
package cannot migrate this because it never writes to your
`InventoryRepository`.** Deciding whether to compensate — grant the missed
drop, or leave it — is yours, and it has to be decided before you ship 2.0.0
to an existing install base.

To keep the 1.x placement exactly, inject the old rule:

```dart
const useCase = CompleteLevelUseCase(bossRule: legacyBossRule);

bool legacyBossRule(int levelId) => levelId > 0 && levelId % 15 == 0;
```

That is why this release and the injectable rewards below ship together: the
escape hatch has to exist in the same version as the change it undoes.

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

### BREAKING — gates block progression

`SagaMapGate` used to be a helper the package exported and never called:
`clampTravelThroughGates` had exactly two references in `lib/`, its own
definition and a doc comment. A gate did nothing unless the host wired it by
hand, and even then it only slowed the character down — taps and unlocking
never heard about it.

Three new hooks close that. All three default to off, so a consumer that passes
none of them keeps 1.x behaviour exactly.

```dart
// The one gate condition, all three consumers derived from it.
bool gateOpen(int levelId) => levelId <= 29 || hasTicket;

SagaInfiniteMapView(
  gates: [SagaMapGate(pathPosition: 29, isOpen: hasTicket)],
  interactionPolicy: SagaNodeInteractionPolicy(
    isReachable: (level, progress) => gateOpen(level.id),
  ),
);

const useCase = CompleteLevelUseCase(canUnlock: gateOpen);
```

- `SagaInfiniteMapView.gates` — the view applies `clampTravelThroughGates`
  itself. A barrier you installed on the controller yourself still wins.
- `SagaNodeInteractionPolicy.isReachable` — consulted before `canTap`, so a
  vetoed node is disabled, skipped by Tab and announced as locked. A subclass
  that overrides `canLongPress` without calling `canTap` bypasses it, as before.
- `CompleteLevelUseCase.canUnlock` — vetoes opening the successor. The level
  itself still completes and a boss reward still drops; only the successor and
  `currentMaxUnlockedLevelId` stand still.

`CompleteLevelResult` gained `unlockBlocked` so a host can tell "you finished
the level" from "you finished it and the road ahead is still shut". It is
always `false` when no `canUnlock` is injected. It also gained `outcome` (a
`CompleteLevelOutcome`): `applied`, `rejectedUnreached` (the
`enforceUnlockOrder` refusal, which `unlockBlocked` alone could not tell from a
plain success) and `appliedUnlockBlocked`. `unlockBlocked` is equivalent to
`outcome == CompleteLevelOutcome.appliedUnlockBlocked`.

### BREAKING — biome ids come from config

The generator read the `const` global `kSagaBiomeIds` directly, so a host with
four realms had no way in. `SagaMapConfig` now carries the list:

```dart
final config = SagaMapConfig.defaultConfig.copyWith(
  biomeSpan: 5,
  biomeIds: myRealms,
);
```

**Omitting `biomeIds` generates the same ids as before** — it defaults to
`kSagaBiomeIds`, which is not removed and not deprecated; it is now that
default. An empty list throws an `ArgumentError` at generation rather than
dividing by zero.

Why this is breaking is semantic rather than structural: once a host supplies
its own ids, `SagaBiomeThemeResolver` starts receiving ids it has never seen.
`DefaultSagaBiomeThemeResolver` answers with the forest theme rather than
throwing, and prints one debug-mode warning per unknown id — a wrong-green map
still works, and the silence that would have hidden the mistake is gone.

`SagaBiomeTheme` gained two optional fields for art direction beyond colour:

- `assets`, an opaque `Map<String, String>` of art keys. The package never
  loads these; it hands them back to your builders. Opaque on purpose — named
  fields would freeze an asset taxonomy and a format the package does not own,
  which is the same trap as the `flutter_svg` dependency below.
- `ambientTint`, a translucent wash the chunk painter applies over background
  and path, under your node widgets.

`SagaMapConfig` also gained `copyWith`, so reaching `biomeIds` does not mean
restating the geometry.

### BREAKING — `SagaProgressRepository` gained `saveGlobalSeed`

Adding a method to an `abstract interface class` breaks every implementation.
Every implementation of `SagaProgressRepository` needs one more method:

```dart
@override
Future<void> saveGlobalSeed(int seed) async {
  await _prefs.setInt('saga_map.seed', seed);
}
```

**If your `loadGlobalSeed` wrote a default as a side effect, move that write
here.** That pattern is exactly why this is not optional: writing a seed on
read makes "load" mean "load, and possibly change the whole map", and a load
that has to run before another load is correct is not a contract anyone can
reason about. `loadGlobalSeed` now says so explicitly: implementations must not
persist as a side effect of loading.

This could have been hidden behind a default body throwing
`UnimplementedError` and shipped in 1.1.0 as non-breaking. It was not: a
supertype method that throws in a subtype is the LSP violation the SOLID
checklist names outright. One version of delay is cheaper than a permanent
hole in the contract.

Changing a stored seed regenerates the whole map — level positions, biomes and
boss rewards all derive from it. Existing `SagaProgress` keeps its level ids,
but those ids now point at different terrain.

### BREAKING — `flutter_svg` is no longer a dependency

`SagaMapBackgroundConfig.svgAsset` and `.svgAssets` are removed, and with them
the `flutter_svg` dependency and its transitive `vector_graphics`,
`vector_graphics_compiler`, `path_parsing` and `xml`. The package's direct
dependencies are now `equatable` and `fast_noise`, nothing else.

A background library had no business being a hard dependency of a layout
package: it made every consumer carry an SVG decoder to draw a PNG, and it
froze one artwork format into the API (ADR-0008).

Replace an SVG background with a builder — the package positions and scrolls
whatever it returns and loads nothing itself:

```yaml
# your pubspec.yaml — the dependency moves to your app
dependencies:
  flutter_svg: ^2.2.4
```

```dart
// before
backgroundConfig: const SagaMapBackgroundConfig.svgAsset(
  assetPath: 'assets/svg/map.svg',
  fit: BoxFit.cover,
)

// after
backgroundConfig: SagaMapBackgroundConfig.builder(
  (context, chunkIndex) =>
      SvgPicture.asset('assets/svg/map.svg', fit: BoxFit.cover),
)
```

For `svgAssets`, index your own list off `chunkIndex` — you now choose the
overflow behaviour instead of picking from the package's three:

```dart
backgroundConfig: SagaMapBackgroundConfig.builder(
  (context, chunkIndex) => SvgPicture.asset(
    assets[(chunkIndex ?? 0) % assets.length],
    fit: BoxFit.cover,
  ),
)
```

The colour, image-asset and none modes are untouched.
`buildBackgroundWidget` now takes a `BuildContext` as its first argument, since
a host-supplied builder needs one. A `builder` config ignores `fit`,
`alignment` and `overflowBehavior`: they describe placing an asset the package
loaded, and it no longer loads this one.

### Correctness — `stableHash` is now web-safe above 2^32

`stableHash`/`stableUnitValue` claimed identical output across the Dart VM and
the web, but the one line that needed 64-bit shift semantics was left raw:
`hash ^ ((value >> 32) & 0xFFFFFFFF)`. A 32-bit shift has no meaning under
dart2js, so a seed at or above 2^32 — which is every seed minted from
`DateTime.now().millisecondsSinceEpoch` (~2^40.7) — produced a **different
world on web than on native**, and web seeds ~49.7 days apart aliased onto one
world. The fold now uses integer division (`value ~/ 0x100000000`), which is
identical on both runtimes, and negative inputs are folded with an explicit
sign salt.

This **changes hash output** for two input shapes: values ≥ 2^32 on the web now
match native (previously they silently collapsed to their low 32 bits), and
negative values now hash differently everywhere. Since 2.0.0 has not been
published, nothing has persisted a map under the broken behaviour; after this
ships, any seed must reproduce the same world on every platform. The contract
is pinned by golden vectors above 2^32 that run on both `vm` and `chrome`.

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
