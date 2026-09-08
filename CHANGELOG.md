# Changelog

All notable changes to this package are documented in this file.

## 2.0.0

### Fixed — the paths taken when something already went wrong

- `SagaMapBackgroundConfig` takes an `errorBuilder`. A mistyped asset path
  rendered a blank chunk with only a console line behind it: the map looked
  loaded and was not, and the host had no API-level signal at all.
- Loader failures no longer interpolate host exception text raw and unbounded
  onto a player's screen. The detail is clipped in debug and dropped in release,
  where a `toString()` can carry a URL, a token or a file path.
- `splitPathAtProgress` returns empty for a chunk with no levels instead of
  throwing a `StateError`; an empty chunk is a normal state while one loads.
- `onLevelReached` is documented as best-effort: it needs the level's chunk in
  memory, so it is dropped for an evicted or still-loading chunk and not
  re-fired later.
- The camera and the chunk layout now round the chunk extent in the same order
  relative to zoom. Rounding before scaling put the camera's idea of a chunk
  boundary a fraction of a pixel from the layout's, drifting further with each
  chunk.

### Fixed — value-object defects

Three of these are breaking: rows 11 and 13 of the table below.

- **BREAKING.** `LevelProgress.copyWith(lastPlayedAt:)` and
  `SagaMapResponsiveConfig.copyWith(maxLateralExtentPolicy:)` take a getter
  (`() => null`) instead of a value, so `null` can mean "clear this" rather than
  only "leave it alone" — the documented unconstrained lateral extent was
  unreachable once set.

  *Escape hatch:* wrap the value you were passing.

  ```dart
  progress.copyWith(lastPlayedAt: () => stamp);   // was: lastPlayedAt: stamp
  progress.copyWith(lastPlayedAt: () => null);    // now expressible at all
  ```

- **BREAKING.** `LootTableEntry` is compared by value.
  `LootTableOdds.probabilityOf` looks an entry up with `contains`, which was
  reference equality: asking about a field-identical copy threw instead of
  answering. Code that relied on two equal entries being distinct — using them
  as separate `Set` or `Map` keys — now sees one.
- **BREAKING.** `LevelProgress` is compared by value too. The view diffs
  resolved progress against cached progress, so a host resolver returning a
  fresh instance per call reported a change on every sweep. Same caveat: equal
  records are now one key, not two.
- An empty `levels` map is documented as meaning uninitialised rather than made
  to round-trip: since an unrecorded level now reads as locked, loading one
  faithfully would produce a map on which nothing is tappable.

### Added — a path renderer you can inject

`MapChunkWidget.pathRenderer` and `SagaInfiniteMapView.pathRenderer` take a
`SagaMapRenderer<CustomPainter>`. `SagaMapRenderer` described itself as "the
extension point for host-supplied renderers" while nothing in the package
depended on the type, so a host wanting its own path painter had to fork the
widget. Pass nothing and the built-in look is unchanged. Nodes stay on
`nodeBuilder`, which is documented on the interface now rather than implied.

### Added — `progressListenable`, for the host that never rebuilds

`SagaInfiniteMapView.progressListenable` takes anything that notifies when
`progressResolver`'s answers may have moved: a `ChangeNotifier` game state, a
`ValueNotifier<SagaProgress>`, a `Listenable.merge` of several.

It exists because the sweep's other trigger has a hole in it. Progress is
re-resolved when the host rebuilds the view *with a new widget instance*, and a
host that stores the view in a field or puts it under a `const` subtree hands
Flutter the same instance every time — the framework then skips the update
entirely and `didUpdateWidget` never runs. That host, the one being careful
about rebuilds, never saw progress refresh at all.

The view only listens; it never disposes what it is given. The full "when is
progress re-resolved" contract is on the field's doc comment.

### Performance — progress is resolved when it can have changed

The sweep that resolves every visible level's progress sat unconditionally in
`itemBuilder`, so a host whose `progressResolver` does real work paid
`levelsPerChunk x visibleChunks` lookups on every frame of a pinch, purely to
conclude nothing had changed.

It now runs when it can matter, and not otherwise. Exactly four things trigger
it: a chunk with no context yet, a chunk whose level list the controller has
replaced, a rebuild of the view with a new widget instance, and a notification
from `progressListenable`.

That last one is new, and it closes the hole in the third. A host that stores
the view in a field or puts it under a `const` subtree hands Flutter the same
widget instance every time, so the framework skips the update and
`didUpdateWidget` never runs — meaning the host being most careful about
rebuilds was the one that never saw progress refresh at all. Pass whatever
already changes when progress does:

```dart
SagaInfiniteMapView(
  progressResolver: (level) => gameState.progressFor(level.id),
  progressListenable: gameState,   // a ChangeNotifier, ValueNotifier, ...
  // ...
)
```

The refresh is also no longer gated on the resolved progress alone. A chunk
whose levels were replaced while every level's progress stayed identical used
to keep a context describing the *previous* list, so a decoration or header
builder read one world's `LevelData` while the widget beside it drew another's.

`onChunkEnter` is served from this same sweep now. It used to run a second,
separate resolution of the whole chunk, which handed the host a context the
builders had never seen and paid the cost this section exists to remove.

### Breaking — `SagaProgress` compares by value, and `fromJson` sanitises its keys

`SagaProgress` now has `==` and `hashCode`. 2.0.0 gave `LevelProgress` value
equality because the view diffs resolved progress against cached progress, and a
host resolver building a fresh instance per call — the obvious way to write one
— reported a change on every sweep. The identical mistake sat one level up: a
host returning a fresh `SagaProgress` per call had the same diff-thrash on a
bigger object. A principle applied to half its cases is more misleading than one
applied to none.

`levels` is compared entry by entry, which is `LevelProgress`'s own equality and
therefore bounded by the number of recorded levels. `extra` is compared shallowly
by its entries' own equality, for the reason `LevelProgress.extra` is: it is
host-owned JSON, and a deep walk of arbitrary nested maps is not something a
per-frame diff can afford. If you keep large nested structures in `extra`, carry
a revision counter in it rather than relying on this comparison.

`fromJson` also closes the last two gaps in its key handling:

- A **negative** level key is skipped. A negative level is an impossible state
  everywhere else in the class — the unlock pointer is raised to `0`, and
  `CompleteLevelUseCase` refuses a negative id whatever the order guard says —
  and the map key was the one door left open.
- A record whose own `levelId` **disagrees with its key** is corrected to the
  key. `{'-5': {'levelId': 7, ...}}` used to load with the two never compared,
  after which code looking a level up by key and code reading `levelId` gave
  different answers about the same record. Corrected rather than dropped,
  matching how every other field there is sanitised.

The full `fromJson` contract is now stated in one list on the method itself.

### Fixed — misconfiguration is refused where it is written

Three configuration errors survived into release builds and then failed from a
paint, a frame or more away from the line that caused them. Debug builds caught
all three with asserts; release builds, where the asserts are gone, did not.

- `SagaMapConfig.spanForLevelCount` throws an `ArgumentError` on a non-positive
  `levelCount` in every build mode. Its release error used to name
  `chunkSpanNormalized` — the field the *result* is assigned to, not the
  argument that was wrong — and sent hosts looking in the wrong place.
- A `SagaSpriteSheet` that resolves to no columns now names the field its own
  layout reads. The message was "must have at least one column" whatever the
  layout, but a horizontal sheet has one column per frame and never reads
  `columns`.
- A `SagaMapZoomConfig` whose range cannot describe a range is refused where the
  view accepts it, during setup, instead of returning NaN from every `clamp`
  call once a pinch begins.

`SagaMapZoomConfig` and `SagaSpriteSheet` keep their `const` constructors: hosts
write them inside otherwise-const subtrees, and a constructor that validates
cannot be `const`. The checks live at the point of acceptance instead.

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

### Fixed — chunk contexts describe the chunk beside them

A chunk whose level list was replaced while its resolved progress stayed
identical kept the context it already had, so the host's decoration and header
builders were handed the *previous* world's `LevelData` while the widget beside
them drew the new one. The refresh now fires on a replaced list as well as
changed progress.

A chunk evicted while still on screen was drawn blank rather than from its
cached levels, because the cache pruning that bounded memory deleted the very
context the fallback reads. Such chunks are kept until their reload lands.

### Fixed — four view lifecycle defects

- A swapped `SagaMapCameraController` was never attached, so every call on the
  new handle silently did nothing. It is now attached (and the old one detached)
  in `didUpdateWidget`.
- Episode headers were absent from every scroll-offset computation, so each one
  shifted the map by a header per chunk and camera targets landed short by a
  growing margin. Declare the header's size with the new
  `SagaInfiniteMapView.episodeHeaderExtent`; a constructor assert catches an
  extent with no builder to fill it. `onChunkEnter` counts the same headers, so
  it no longer names a chunk the player is nowhere near deep into a scroll.
- The character vanished standing exactly on the last level of the last chunk:
  the final point has no segment leaving it, so it resolved to no pose while
  `ownsPathPosition` still claimed the position and no other chunk drew it.
- A controller swap kept the previous world's chunk contexts, which are keyed by
  chunk index alone, so a new seed rendered the old map's nodes until every
  chunk happened to rebuild. It also kept three high-water marks over the old
  world's numbering, which is the half of that fix that was missing: in the new
  world `onLevelReached` stayed silent for every level the *previous* one had
  already passed, `onChunkEnter` compared against a stale last index, and the
  opening scroll — already recorded as done — never ran again. A controller
  swap now clears all of it in one place.

### Breaking — the progression guard ships on, and is decided once

`enforceUnlockOrder` moved from an `execute` parameter defaulting to `false` to
a `CompleteLevelUseCase` constructor field defaulting to `true`. It used to be a
guard a host had to remember at every call site while the shipped default
accepted any level id. `execute` still takes it as an optional override for the
one call that deliberately jumps ahead.

A negative `levelId` is now refused whatever the guard says, and
`SagaProgress.fromJson` reconciles `currentMaxUnlockedLevelId` against the
records beside it — a pointer must be justified by its own record or by a
completion below it, never by a record for some unrelated level — so a tampered
save cannot hand itself the pointer the guard rests on. `fromJson` sanitises
rather than trusts, and says so. If you have 1.x saves in the wild, read
**Migration — 1.x saves** below before shipping.

`rollBossReward` stays public — hosts need it for previews and their own
economies — with its unguarded-mint contract spelled out in full rather than in
one line. The snapshot-based first-clear guard in `execute` is documented on
`CompleteLevelResult.reward` and pinned by a test; closing it structurally needs
the deferred `InventoryRepository` injection (ADR-0003, 2.1.0).

### Migration — 1.x saves

**Read this before you ship 2.0.0 to an install base.** Two changes in this
release meet in one place, and together they can make a returning player look
like they lost their progress.

1. `SagaProgress.fromJson` now reconciles `currentMaxUnlockedLevelId` against
   the records beside it. The pointer may reach one past the highest
   **completed** level, or stand where the payload records the pointed-at level
   as `unlocked`/`completed` in its own right. A pointer justified by neither is
   clamped down.
2. `enforceUnlockOrder` is on by default, so every level above that pointer then
   refuses to complete.

1.x read a missing level record as "unlocked if it sits below the pointer", so a
1.x host was free to persist a pointer of `20` beside records for levels `0`,
`1` and `2` only. Loaded by 2.0.0, that save's pointer becomes `3`.

**If your 1.x build wrote a record for every level the player reached, you are
not affected** — those saves reconcile to the same pointer they stored.

The escape hatch, run once at upgrade time:

```dart
// Only for a payload you know your own 1.x build wrote. It trusts the stored
// pointer, which is exactly the guarantee `fromJson` withholds.
final migrated = SagaProgress.migrateFrom1x(savedJson);
await repository.saveProgress(migrated);   // persist, then never call it again
```

It backfills every id in `[0, currentMaxUnlockedLevelId]` that has no record as
`unlocked`, grants no stars and completes nothing — it restores exactly the
reachability the 1.x reading gave. `maxBackfill` (default `10000`) bounds the
work an absurd stored pointer can cause.

To find out whether you are affected at all, ask `fromJson` — clamping is silent
by default, but not unreportable:

```dart
SagaProgress.fromJson(savedJson, onClamp: (clamp) {
  if (clamp.lostGround) {
    analytics.log('saga_pointer_clamped', {'from': clamp.storedPointer});
  }
});
```

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

A single breaking release, and nothing deprecated in 1.1.0 was removed — those
removals stay scheduled for 3.0.0, so the deprecated builders survive the whole
2.x line.

Nineteen breaking changes. Six need code from you; the rest are behaviour or
contract changes, and the "what you do about it" column says when the answer is
nothing.

| # | Change | What you do about it |
| --- | --- | --- |
| 1 | Boss levels moved by one | Nothing, or inject `bossRule` to keep 1.x placement |
| 2 | Rewards are injectable | Nothing; the defaults are the old values |
| 3 | Gates block progression | Nothing; all three hooks default to off |
| 4 | Biome ids come from config | Nothing; omitting `biomeIds` is the old sequence |
| 5 | `saveGlobalSeed` added | **Implement one method on your repository** |
| 6 | `flutter_svg` dropped | **Take the dependency yourself and pass a `builder`** |
| 7 | `enforceUnlockOrder` defaults on | Nothing, or pass `false` where you jump ahead |
| 8 | An unrecorded level is now locked | Nothing, or return an unlocked `LevelProgress` |
| 9 | The unlock pointer is reconciled against its records | **1.x saves: see Migration below** |
| 10 | `SagaProgress` is no longer `const` | **Drop `const` at the call site** |
| 11 | `copyWith` getter signatures for nullable fields | **Pass `() => value` instead of `value`** |
| 12 | `buildBackgroundWidget` takes a `BuildContext` | **Pass the context through** |
| 13 | `LootTableEntry` and `LevelProgress` compare by value | Nothing; identity comparisons become equality |
| 14 | Assert-only divisor guards are now runtime exceptions | Nothing, unless your config was already invalid |
| 15 | A gate exactly on a move's destination now blocks | Nothing; this is what a gate was documented to do |
| 16 | `stableHash` output changed above 2^32 and for negatives | Nothing; nothing has shipped under the old output |
| 17 | A width in no breakpoint interval resolves differently | Nothing; the old answer was always desktop |
| 18 | `SagaProgress` compares by value | Nothing; identity comparisons become equality |
| 19 | `fromJson` skips negative level keys and corrects a record's `levelId` to its key | Nothing, unless you relied on the two disagreeing |

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

### BREAKING — assert-only divisor guards became runtime exceptions

`biomeSpan`, `chunkSpanNormalized`, the zoom range and sprite-sheet columns were
divisors and clamp bounds guarded only by `assert`. Asserts are stripped from
release builds, and a host's own configuration arrives in exactly those builds,
so a zero or negative value divided by zero or produced `NaN` deep inside the
painter — a blank or scrambled map with no error attached to it.

Each is now a runtime guard at the point of use, throwing in every build mode.

**What changes for you:** a misconfiguration that used to draw an empty map now
**throws in release**. If you were shipping an invalid config and had not
noticed — a `chunkSpanNormalized` of `0`, a zoom range with `min > max`, a
sprite sheet with `0` columns — the failure moves from silent to loud. Validate
your configuration values before you construct the widget; the exceptions name
the field.

### BREAKING — a gate exactly on a move's destination now blocks

Both gate branches were strictly open on the destination side, so a gate sitting
exactly on a move's destination was skipped: the character landed on it, and the
next move skipped it again from the origin side. Two moves crossed the only
progression barrier the package enforces itself.

The destination bound is closed now, and `moveTo` re-asks the barrier per step,
so a gate that closes mid-walk stops the character where it closed.

**What changes for you:** if you placed gates on integer level positions and
built around them being passable, they now block. That was always the documented
contract; the code did not keep it.

### BREAKING — a width in no breakpoint interval resolves to the widest it is past

The built-in breakpoint bounds are inclusive integers while `resolveBreakpoint`
takes a `double`, so `450.5` — split-screen, a resized web window, browser zoom,
a device reporting `411.42857142857144` — matched no interval and fell through
to a hard-coded desktop. The narrowest screens the package supports were given
desktop sizing and touch targets a quarter smaller.

A width in no interval now resolves to the widest breakpoint it is past, which
closes the seams for host-supplied bounds too without asking them to be restated
as half-open.

**What changes for you:** nothing to write. Fractional widths that used to
resolve to desktop now resolve to the breakpoint they are actually in, which is
the answer you configured.

### Added — `retainedChunkIndices` and the chunk cache bound

`SagaInfiniteMapController.retainedChunkIndices` is new public API. The view
kept a second, unbounded per-chunk cache that `maxRetainedChunks` never reached,
so the documented memory bound measured only the controller's half; the view
prunes in step with eviction through this getter. `reloadingChunkIndices` is its
complement, so a chunk evicted while still visible is drawn from cached levels
until its reload lands rather than blank.

**Known limitation.** `maxRetainedChunks` bounds the cache at load time but not
during a scroll: chunks requested since the last eviction are protected from it,
and that protected set is only cleared once the cache is back under budget, so
once a scrolling view is over budget with everything requested, eviction stops.
Leaving it unset (the default) retains everything, which is the documented
behaviour either way.

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

// `const` works because `gateOpen` is a top-level function; a closure or a
// method tear-off would need `final` here.
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

`SagaCharacterController.jumpTo` **deliberately does not consult gates**, and
now says so. It is the placement primitive — restoring a saved position,
a level select, a chapter-skip purchase, a debug tool — and a gate governs
travel, not where the character is standing; clamping there would drag a
restored save back behind a gate the player passed long ago. For an instant
move that gates *do* govern, ask for the move and turn the animation off:

```dart
controller.jumpTo(14);                   // place: gates ignored
controller.moveTo(14, animate: false);   // move: gates respected
```

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
**BREAKING.** `buildBackgroundWidget` now takes a `BuildContext` as its first
argument, since a host-supplied builder needs one. *Escape hatch:* pass the
context you already have — `config.buildBackgroundWidget(context, ...)`. A `builder` config ignores `fit`,
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

- Boss milestones move to `id % 15 == 14` from `id % 15 == 0` (ADR-0002).
  (The 1.1.0 note said `id % 5 == 4`, which is the difficulty alignment the new
  rule happens to guarantee, not the rule itself.)
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
