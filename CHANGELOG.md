# Changelog

All notable changes to this package are documented in this file.

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
