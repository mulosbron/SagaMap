# 8. Dropping the flutter_svg dependency

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

`pubspec.yaml` carries `flutter_svg: ^2.2.4`, and its own comment names the
single call site:

```yaml
# flutter_svg: SagaMapBackgroundConfig.svgAsset.
flutter_svg: ^2.2.4
```

So the entire package forces a drawing library and its transitive dependencies
(`vector_graphics`, `xml`, `path_parsing`) for a single optional feature. A
consumer that doesn't use SVG — the production consumer uses webp — carries
this weight for free.

This also contradicts what the package itself declares. From `pubspec.yaml`:

> This package is consumed from host apps.
> Host applications provide and register their own background assets.

The package says "the host supplies assets" but special-cases exactly one
format and pulls its loader into its own dependencies.

## Decision

Options:

| Option | Pro | Con |
|---|---|---|
| **A. A `WidgetBuilder` hook** | Dependency drops entirely; the host supplies whatever format it wants; consistent with the stated philosophy | Consumers of `svgAsset` must change code |
| B. A separate `saga_map_svg` package | Convenience preserved | Two packages, two versions, two CHANGELOGs — disproportionate for a single maintainer |
| C. Leave it | Zero work | Every consumer carries a library it doesn't use |

**A is chosen.** In place of `SagaMapBackgroundConfig.svgAsset`:

```dart
class SagaMapBackgroundConfig {
  /// Builds the background layer. The package positions and scrolls whatever
  /// this returns; it loads nothing itself.
  ///
  /// For an SVG, add flutter_svg to your own app and return SvgPicture.asset.
  /// README "Custom backgrounds" shows the five-line equivalent.
  final WidgetBuilder? backgroundBuilder;
}
```

`flutter_svg` is removed from `dependencies`. The README gets a five-line
recipe for reproducing the same look with `flutter_svg` — the feature isn't
lost, only its ownership moves.

Option B looks aligned with the spirit of the `preventing-vendor-lock-in`
skill, but is the wrong scale here: publishing a separate package for a loader
wrapper writes more maintenance cost than the convenience it buys. The correct
abstraction is for the package to not know the format at all.

Whether `svgAsset` should be **removed or deprecated** in 2.0.0: since the
field becomes non-functional once the dependency drops, keeping it deprecated
has no purpose — it's removed in 2.0.0, with the replacement shown in the
CHANGELOG.

## Consequences

### Positive
- The package's dependency graph is now bounded by `equatable` + `fast_noise`;
  both are genuinely core (`ProceduralBiomeGenerator`).
- Download size and build time drop for every consumer that doesn't use SVG.
- The package makes no assumption about background format: webp, png,
  gradient, `CustomPaint`, animation — all equally supported.
- The "host provides its own assets" claim in `pubspec.yaml` becomes true.

### Negative
- **Breaking:** a consumer using `svgAsset` must add `flutter_svg` to its own
  `pubspec` and write five lines. The README needs a copy-pasteable example.
- The "batteries included" convenience is gone; one more step for a new
  consumer that wants to start with SVG.
- Once the package stops testing `flutter_svg` version compatibility, any
  incompatibility a host hits falls outside the package's field of view.
  Accepted: this should already be the host's dependency to manage.

## Related

- Task: T-20
- Skill: `preventing-vendor-lock-in`
