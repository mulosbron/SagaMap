# saga_map

`saga_map` is a Flutter package for building world-map style level progression UIs.

It provides:

- responsive layout policies
- background layers (SVG, image, solid color, multi-segment)
- interaction policy/handler primitives
- level generation and progression utilities
- a character that walks the path, in any visual format
- curved paths, a walked/upcoming split, scenery, episode headers, parallax and gates

## Screenshots

The images below are the package's own rendering output (from the golden
tests), so they show exactly what it draws.

| Curved path (vertical) | Walked vs. upcoming | Curved path (horizontal) |
| --- | --- | --- |
| ![Curved vertical path](doc/screenshots/curved_path_vertical.png) | ![Walked path lit up](doc/screenshots/walked_path.png) | ![Curved horizontal path](doc/screenshots/curved_path_horizontal.png) |

- **Curved path** â€” `pathCurvature` bends the line between nodes; the nodes
  stay put. Continuous across chunk seams.
- **Walked vs. upcoming** â€” the stretch the player has covered is drawn in the
  bright colour, the road ahead dimmed, split exactly under the character.

Run the demo (`cd example && flutter run`) for the whole feature set live: a
walking character, pinch zoom, scenery, episode banners, parallax, gates, and a
control panel to toggle each one.

## Installation

```bash
flutter pub add saga_map
```

```dart
import 'package:saga_map/saga_map.dart';
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:saga_map/saga_map.dart';

class WorldMapScreen extends StatelessWidget {
  const WorldMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final levels = <LevelData>[
      const LevelData(
        id: 1,
        position: SagaPoint(0.20, 0.08),
        biomeId: kBiomeIdForest,
      ),
      const LevelData(
        id: 2,
        position: SagaPoint(0.35, 0.16),
        biomeId: kBiomeIdDesert,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Saga Map')),
      body: MapChunkWidget(
        levels: levels,
        chunkIndex: 0,
        chunkExtent: 900,
        chunkSpanNormalized: 1.0,
        biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
        interactionPolicy: const SagaNodeInteractionPolicy(
          emitTapForLockedNode: false,
          emitTapForCompletedNode: true,
        ),
        nodeBuilder: (context, level, layout) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.indigo,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${level.id}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

This quick start mirrors the real package usage in `example/lib/main.dart`
with `MapChunkWidget`, `SagaInfiniteMapView`, `SagaMapLevelGenerator`,
and `CompleteLevelUseCase`.

## Level ids

Level ids are zero-based. The first level a player sees on the map has `id == 0`.
Wherever a player reads the number, you must display `id + 1`.

| Context | What to use | Example |
| --- | --- | --- |
| Storage | `level.id` | Saved progress uses `0` for the first node |
| Logic | `level.id` | Generator seeds, boss math (`id % 15 == 0`) |
| UI | `id + 1` | "Level 1", screen-reader announcements |

```dart
// Inside your nodeBuilder:
Text(
  '${level.id + 1}',
  style: const TextStyle(color: Colors.white),
)
```

The function `isBossLevel(levelId)` is public because callers need to know if a level was a boss to display the appropriate icon before it is played.

## Versioning

This package follows [Semantic Versioning](https://semver.org/).

A change is breaking (requires a major version bump) if it breaks:
1. **Compilation:** A public signature changes or is removed.
2. **Saved data format:** Existing serialized progress can no longer be read.
3. **Saved data meaning:** Reading old data behaves differently (e.g. altering the deterministic sequence of levels).

**Deprecation policy:** Nothing marked `@Deprecated` is removed in the same major version. It will emit a warning until the next major release.

**Upcoming breaking changes in 2.0.0:**
- Boss milestones land on `id % 5 == 4` instead of `id % 15 == 0` (ADR-0002).
- Drops `flutter_svg` from the core package (ADR-0008).

## Public API Design

Only import this file from your app:

```dart
import 'package:saga_map/saga_map.dart';
```

`lib/src` is internal implementation detail and is not part of the stable API contract.
Avoid direct imports like `package:saga_map/src/...` in app code.

The package keeps a "showroom + kitchen" boundary:
- showroom: `lib/saga_map.dart` (stable public API)
- kitchen: `lib/src/**` (internal organization and implementation)

## Main Features

### Background layer

```dart
backgroundConfig: const SagaMapBackgroundConfig.svgAsset(
  assetPath: 'assets/svg/map_horizontal.svg',
  fit: BoxFit.cover,
)
```

### Orientation

`pathAxis` is the single switch between a vertical and a horizontal map. It
drives coordinate mapping, which viewport dimension counts as lateral, and the
scroll direction of `SagaInfiniteMapView` â€” there is no separate scroll axis to
keep in sync.

```dart
final responsiveResolver = SagaResponsiveResolver(
  config: SagaMapResponsiveConfig.defaults.copyWith(
    pathAxis: SagaMapPathAxis.horizontal,
  ),
);
```

Sizes are expressed along the path axis, never as width/height:

- `chunkExtent` â€” pixels the chunk occupies along the path axis (height when
  vertical, width when horizontal).
- `chunkSpanNormalized` â€” normalized span the chunk covers along that axis. It
  must equal `stepHeight * levelsPerChunk`; use
  `SagaMapConfig.spanForLevelCount()` rather than hardcoding it.
- `maxLateralExtentPolicy` â€” caps the *lateral* axis only, so it never shortens
  the direction the path travels in.

The cross axis fills whatever space the parent gives it, so a horizontal map
belongs in a horizontally scrollable parent and a vertical map in a vertical
one. `SagaInfiniteMapView` handles this for you.

### Responsive policies

Breakpoints always resolve from the real viewport width, on both orientations â€”
a long horizontal map on a phone still resolves as `mobile`.

```dart
final responsiveResolver = SagaResponsiveResolver(
  config: SagaMapResponsiveConfig.defaults.copyWith(
    nodeSizePolicy: const SagaMapValuePolicy(
      mobile: 1.20,
      tablet: 1.0,
      desktop: 0.95,
      ultra4k: 0.9,
    ),
    // Same value everywhere.
    nodeSpacingPolicy: const SagaMapValuePolicy.all(1.0),
  ),
);
```

Every policy affects rendering:

| Policy | Effect |
| --- | --- |
| `nodeSizePolicy` | Node visual size. |
| `zoomPolicy` | Node size and path stroke width together. |
| `nodeSpacingPolicy` | Chunk extent along the path axis, so the gap between nodes. |
| `interactionRadiusPolicy` | Touch target relative to visual size. |
| `cameraPaddingPolicy` | Pixels reserved at each end of the lateral axis. |
| `maxLateralExtentPolicy` | Cap on the lateral axis; never the path axis. |
| `scrollSensitivityPolicy` | Drag distance multiplier while scrolling. |

Node visual size and touch target are separate. Visual size is
`baseNodeSize * nodeSize * zoom`; the touch target is derived from it via
`interactionRadius` and floored at `minTouchTarget` (44dp). A node can therefore
shrink below the accessibility minimum visually while staying comfortably
tappable.

`zoomPolicy` is the viewport-driven baseline; user pinch zoom multiplies it.

### Pinch zoom

```dart
SagaInfiniteMapView(
  zoomConfig: const SagaMapZoomConfig(min: 0.5, max: 3),
  onZoomChanged: (zoom) => setState(() => _zoom = zoom),
  // ...
)
```

Leaving `zoomConfig` null keeps the map at a fixed scale.

Zoom is applied to the **layout**, not as a paint transform: the chunk really
becomes larger. The enclosing list therefore keeps a correct scroll extent,
chunk recycling keeps working, hit testing needs no inverse mapping, and the
path is rasterised at its final size instead of being magnified.

One finger scrolls, two fingers zoom. The pinch recognizer stays out of the
gesture arena until a second finger lands, then claims it immediately â€” waiting
for movement would lose the race to the scrollable underneath, which sits deeper
in the tree and is offered each event first. The known limit of that approach:
a pinch begun *after* a one-finger drag has already captured the arena will
scroll rather than zoom, until the fingers lift.

### Progress-aware interaction

```dart
MapChunkWidget(
  levels: levels,
  chunkIndex: 0,
  chunkExtent: 900,
  chunkSpanNormalized: 1.0,
  biomeThemeResolver: const DefaultSagaBiomeThemeResolver(),
  progressResolver: (level) => progressByLevel[level.id],
  interactionHandler: SagaNodeInteractionHandler(
    onNodeTap: (level) => debugPrint('Tapped ${level.id}'),
  ),
  nodeBuilder: (context, level, layout) => const SizedBox.shrink(),
)
```

### Path roundness

`pathCurvature` runs from `0` â€” straight lines between nodes, the default â€” to
`1`, a fully rounded spline in the style of a casual world map.

```dart
SagaInfiniteMapView(
  pathCurvature: 0.8,
  // ...
)
```

The spline interpolates, so raising the value bends the line between nodes
without moving the nodes themselves. Each control handle points from the
previous node towards the next, which is what makes the curve enter and leave a
node on one smooth tangent, and its length is capped at half its segment â€” that
cap is why `1` is safe rather than folding the line into a cusp. At `0` the
handles collapse onto the endpoints and the result is exactly the straight
polyline.

A curved path needs `kSagaPathNeighborCount` levels of context on each side of a
chunk to stay smooth across a seam, because a curve's shape depends on its
surroundings. `SagaInfiniteMapView` supplies them; if you drive `MapChunkWidget`
yourself, fill `leadingNeighbors` and `trailingNeighbors`.

### Accessibility

Nodes are exposed to screen readers as buttons carrying the level number, its
state and star count, and are marked disabled when the interaction policy
rejects taps. Override the label to localise:

```dart
MapChunkWidget(
  semanticsLabelBuilder: (level, progress) => 'BÃ¶lÃ¼m ${level.id}',
  // ...
)
```

Visual size and touch target are independent, so a node can shrink below 44dp
while staying comfortably tappable. Right-to-left layouts mirror a horizontal
map's path axis; vertical maps are unaffected.

Nodes are keyboard-reachable: Tab moves between them in **level order** (not
paint order), and Enter or Space activates the focused node. Shift+F10 or the
context-menu key triggers the long-press action. Locked nodes are skipped. Draw a focus ring by reacting to `SagaNodeInteractionState.focused`,
which is emitted only when focus arrives by keyboard:

```dart
interactionHandler: SagaNodeInteractionHandler(
  onNodeFocusChange: (level, state) => setState(() {
    focusedLevelId = state == SagaNodeInteractionState.focused ? level.id : null;
  }),
)
```

### Bounded memory

```dart
SagaInfiniteMapController(
  chunkLoader: loadChunk,
  maxRetainedChunks: 12,
)
```

A target rather than a hard cap: chunks currently on screen are never dropped,
so a budget below the visible working set is exceeded rather than thrashing.
Evicted chunks reload when scrolled back to, which is safe because loaders are
deterministic.

### Determinism

Level positions come from `(globalSeed, levelId)` alone, via `stableHash`. That
means:

- Generating chunk 10,000 costs the same as chunk 0 â€” no replay from level zero.
- The same seed produces the same map on every run, platform and release, so
  saved progress keeps pointing at the same map.

Do not use `Object.hash` for anything you persist or regenerate: it mixes in
`identityHashCode(Object)`, which is randomised per program run.

### Domain utilities

```dart
const generator = SagaMapLevelGenerator();
final levels = generator.generateLevels(
  globalSeed: 42,
  config: SagaMapConfig.defaultConfig,
  startLevelId: 0,
  count: 50,
);
```

You can also track star collections without duplicate loops:

``dart
final stars = progress.starsInRange(0, 10);
final perfect = progress.isRangePerfect(0, 10);
``

### Rewards

```dart
final result = completeLevelUseCase.execute(
  currentProgress: progress,
  levelId: level.id,
  globalSeed: 42,
);
if (result.reward != null) {
  await inventoryRepository.add(result.reward!);
}
```

### Character on the path

A character walks the map, Candy-Crush style. The library computes where it is,
which way it faces and what it is doing; the host draws it, so any format plugs
in â€” sprite sheet, Lottie, Rive, GIF, plain Flutter.

```dart
final character = SagaCharacterController(vsync: this);

SagaInfiniteMapView(
  character: SagaCharacter(
    controller: character,
    builder: (context, state) => YourAvatar(
      walking: state.motion == SagaCharacterMotion.walking,
      facingLeft: state.facesLeft,
    ),
  ),
  followCharacter: true,          // camera keeps it in view
  initialPathPosition: 12,        // opens where the player left off
  // ...
);

// After a level completes:
await character.moveTo(13);       // walks there, node by node
```

Position is a fractional level index (`4.5` is halfway between levels 4 and 5),
measured by distance along the curve so the pace stays even. Movement steps node
by node with a pause on each, resumes from where it got to if interrupted, and
honours reduced-motion. Scrolling and pinch zoom lock while it travels so the
user cannot drag the map out from under the camera.

`SagaCharacterGait.hop` arcs between nodes instead of walking.

Sprite sheets have no ready package, so one is built in â€” dependency-free,
horizontal strips by default (`SagaSpriteSheet(frameWidth: 60, frameHeight: 60,
frameCount: 6)` is a 360Ã—60 image), plus vertical and grid, `loop`/`once`/
`pingPong`, and `FilterQuality.none` for crisp pixel art:

```dart
SagaSpriteAnimation(
  image: const AssetImage('assets/hero_walk.png'),
  sheet: const SagaSpriteSheet(frameWidth: 60, frameHeight: 60, frameCount: 6),
  clip: const SagaSpriteClip(count: 6, fps: 12),
)
```

### Walked path, scenery, headers, parallax, gates

```dart
SagaInfiniteMapView(
  // Bright behind the player, dim ahead â€” set the theme's upcoming colours and:
  pathProgressPosition: highestLevelReached.toDouble(),
  pathCurvature: 0.8,

  // Trees, houses, clouds â€” positioned by the library, drawn by you, below nodes:
  decorationBuilder: (context, chunkIndex) => [
    SagaMapDecoration.besidePath(
      pathPosition: chunkIndex * 10 + 3,
      lateralOffset: 120,
      builder: (context) => const Icon(Icons.park),
    ),
  ],

  // A banner before a chunk:
  episodeHeaderBuilder: (context, i) =>
      i.isEven ? EpisodeBanner('World ${i ~/ 2 + 1}') : null,

  // A layer that lags the scroll for depth:
  parallaxBackground: const SkyGradient(),
  parallaxFactor: 0.4,
)
```

A gate holds the character back until the host opens it â€” the "ask 3 friends" or
"spend a ticket" barrier. Whether it is open is your call; the library just
stops the character:

```dart
character.barrier = (from, to) => clampTravelThroughGates(
  [SagaMapGate(pathPosition: 30, isOpen: hasTicket)],
  from,
  to,
);
```

### Storing your own data

The progression model includes an extra field, a Map<String, dynamic> where the host application can store custom data without changing the package models. 
The package preserves this data and never interprets it.

`dart
final progress = SagaProgress(
  currentMaxUnlockedLevelId: 0,
  levels: {
    0: LevelProgress(
      levelId: 0,
      state: LevelCompletionState.completed,
      stars: 2,
      extra: const {'app.no_mistake_streak': 10}, // per-level data
    ),
  },
  extra: const {'app.spent_stars': 5, 'app.opened_chests': 2}, // global data
);
`

> **Note**: Keys should be namespaced (e.g., using an pp. prefix) to avoid future collisions. Keep the stored data small, as it is serialized on every save.

## Example App

See [`example/lib/main.dart`](example/lib/main.dart) for a full showcase:

- map rendering with background modes
- infinite map controller usage
- generator and progression use-case demo

Run it:

```bash
cd example
flutter pub get
flutter run
```

## Testing

```bash
flutter analyze
flutter test
```

Golden tests carry the `golden` tag. Their output depends on the host renderer,
so on a platform that does not match the committed references either regenerate
them or skip them:

```bash
flutter test --exclude-tags golden          # skip
flutter test --update-goldens test/golden   # regenerate after an intended change
```

## Changelog

All notable changes are documented in [`CHANGELOG.md`](CHANGELOG.md).

## License

This package is licensed under the MIT License. See [`LICENSE`](LICENSE).




