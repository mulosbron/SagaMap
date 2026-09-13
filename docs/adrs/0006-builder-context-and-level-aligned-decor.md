# 6. Giving builders a chunk context and adding level-aligned decor

Date: 2026-09-05

## Status

Accepted — implemented in 1.1.0.

## Context

### Problem 1 — builders are blind

The decoration and chapter-header builders only receive `chunkIndex`:

```dart
// saga_map_decoration.dart:87-90
typedef SagaMapDecorationBuilder = List<SagaMapDecoration> Function(
  BuildContext context,
  int chunkIndex,
);

// saga_infinite_map_view.dart:143
final Widget? Function(BuildContext context, int chunkIndex)? episodeHeaderBuilder;
```

When a host places decor on a chunk, it can't see that chunk's `LevelData`:
**neither `biomeId` nor `difficulty` reaches the builder.**
`controller.chunkLevels(index)` exists, but it has two problems: (a) it
requires reaching from inside the builder into the controller, and (b) it
returns an empty list for an evicted chunk
(`saga_infinite_map_controller.dart:86`) — a timing-dependent contract.

The practical result: the package generates a `biomeId` for every level
(`saga_map_level_generator.dart:51`), and the production consumer **never read
it at all** — it built its own realm mapping from the chunk index instead. The
field the package produces is dead.

### Problem 2 — a level-aligned band is computed by hand

There's no way to place a full-width panel (a milestone, a boss banner)
aligned with a specific level:

- `besidePath(pathPosition: n)` → the point sits on the path; as the path
  curves it drifts sideways, unusable for a full-width band.
- `atFraction(chunkFraction: ...)` → the host must solve the fraction math
  itself, accounting for `alongEdgeInsetFraction`
  (`saga_infinite_map_view.dart:90`).

The consumer's code has an 8-line comment deriving this formula. That
knowledge belongs inside the package: the package knows the geometry, the host
is guessing.

## Decision

### Decision 1 — `SagaChunkContext`

Builders receive a single context object:

```dart
/// Everything a decoration or header builder needs about one chunk.
class SagaChunkContext {
  final int chunkIndex;
  final List<LevelData> levels;
  final Map<int, LevelProgress> progress;

  /// The biome most of this chunk sits in, already resolved.
  final String dominantBiomeId;
}

typedef SagaMapDecorationBuilder =
    List<SagaMapDecoration> Function(BuildContext context, SagaChunkContext chunk);

typedef SagaEpisodeHeaderBuilder =
    Widget? Function(BuildContext context, SagaChunkContext chunk);
```

`dominantBiomeId` is computed with the package's existing `getDominantBiomeId`
(`saga_dominant_biome.dart`) — free to add to the context, and it makes the
`biomeId` field usable for the first time.

The context is **pushed, not pulled**: the builder never reaches into the
controller; it's built once during the chunk lifecycle and handed over. This
also closes the empty-list-for-evicted-chunk problem.

A single object was chosen over separate `levels`, `progress`, `biome`
parameters: adding a field later won't break the signature.

### Decision 2 — `SagaMapDecoration.atLevel`

```dart
/// A full-width band aligned with one level, spanning the chunk laterally.
///
/// Unlike [besidePath], this ignores the path's lateral wander: the band sits at
/// the level's position along the scroll axis and stretches edge to edge. The
/// along-axis fraction accounts for the view's `alongEdgeInsetFraction`, so the
/// band lines up with the node even when the chunk has end insets.
const SagaMapDecoration.atLevel({ required int levelId, ... });

/// Along-axis fraction of the chunk box for one level, edge insets included.
double chunkFractionForLevel({
  required int levelIndexInChunk,
  required int levelsPerChunk,
  double edgeInsetFraction = 0,
});
```

The helper function is also exported, so a host laying out its own decor
doesn't have to re-derive the formula.

### Migration

The old `SagaMapDecorationBuilder` signature is marked `@Deprecated` but **not
removed**:

```dart
@Deprecated('Use decorationBuilder with SagaChunkContext. Removed in 3.0.0.')
```

`SagaInfiniteMapView` accepts both parameters; if both are given, an `assert`
warns and the new one wins. This lets the decision ship **in 1.1.0, without
breaking anything.**

## Consequences

### Positive
- `biomeId` and `difficulty` reach the host for the first time; the fields the
  package produces stop being dead.
- The builder no longer needs to reach into the controller — the
  timing-dependent empty-list problem closes.
- Placing a milestone or boss banner becomes one line; the geometry knowledge
  stays inside the package.
- `SagaChunkContext` carries the same payload T-15's (`onChunkEnter`) will
  need — two features share one type.
- Non-breaking: fits in 1.1.0.

### Negative
- **Performance caveat:** `SagaChunkContext` must be built once per chunk
  lifecycle, not on every `build`; otherwise garbage generation rises during
  scrolling. This is one of T-05's acceptance criteria.
- Two parallel builder signatures live for a whole major version;
  `SagaInfiniteMapView` and `MapChunkWidget` must carry both.
- `SagaMapDecoration` gains a third constructor; the invariant that the three
  are mutually exclusive must be enforced manually (`assert`).
- `chunkFractionForLevel` grows the public API surface; changing the formula
  later would be breaking. Accepted: hiding the knowledge only pushes the host
  toward re-deriving it wrong.

## Related

- Task: T-05, T-10, T-15
- `.old/docs/reports/05-c4-genisleme-noktalari.md` (extension-seam inventory)
