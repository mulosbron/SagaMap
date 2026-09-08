# Contributing

## Runtime guards for divisors

A value used as a divisor gets a **runtime** guard, never an `assert`. Asserts
are stripped from release builds, which is precisely where a host's own data —
and therefore a misconfigured divisor — arrives.

The canonical example is `SagaMapConfig.biomeSpan`: the `const` constructor can
only `assert(biomeSpan > 0)`, so `SagaMapLevelGenerator.generateLevels`
re-checks it and throws `ArgumentError.value` before `levelId ~/ biomeSpan` can
divide by zero. The same shape applies to `chunkSpanNormalized`
(`SagaMapCoordinates.relativeAlong`), the zoom range
(`SagaMapZoomConfig.clamp`) and sprite-sheet geometry
(`SagaSpriteSheet.resolvedColumns`).

Follow it everywhere a number is divided by configuration:

- a bad **argument** throws `ArgumentError.value` at the point of division;
- a constructed object that has drifted into an invalid state throws
  `StateError`;
- the constructor keeps its `assert` as the debug-time signal.

## Platform-parity suites and the browser run

`stableHash` has to give the same answer on the VM and on the web, where an
`int` is a double and a 64-bit shift has no meaning. A VM-only run cannot see
that divergence, so those suites are tagged `platform-parity` and **must live
in `test/parity/`**.

That directory is not a convention. The browser job runs
`flutter test --platform chrome --tags platform-parity test/parity`, bounded by
the directory, because `--tags` alone still *loads* every suite under the
browser and the ones touching `dart:io` fail to load before any filtering
happens. A tagged suite left outside `test/parity/` would therefore run on the
VM only — silently. `release_hygiene_test.dart` fails on one.

### The browser run cannot be verified locally

`flutter test --platform chrome` has been observed hanging with no output for
15+ minutes on a Windows development machine, for any suite including a trivial
one — Chrome would not launch for the test runner at all. This is a known
limitation of the local setup, not a property of the tests.

**Treat CI as the only check for web parity.** Do not conclude from a local
hang that a parity suite is broken, and do not "fix" a parity suite based on
local browser behaviour. Push and read the `test (chrome)` job.

## Screenshots

Two kinds live under `doc/screenshots/`, and they are not interchangeable.

**Goldens** (`test/golden/goldens/`) are the regression net. They render a
synthetic chunk with hand-authored levels and plain shapes — no icons, no
glyphs, no fonts — so the same commit produces the same bytes on any machine.
A visual change fails a test. Regenerate deliberately:

```bash
flutter test --update-goldens test/golden
```

**Device screenshots** (`doc/screenshots/demo_*.png`) are photographs of the
example app on a real device: real assets, real fonts, real device pixel ratio.
Nothing compares them, so a device or font change moves them silently. They
exist to show a reader what the package looks like, not to catch a regression —
which is why the goldens sit alongside rather than being replaced by them.

Recapture them with a device or emulator booted:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d <device-id>
```

The driver writes them at the device's own resolution, which for a modern
phone is around 150 KB each. **Halve them before committing** — every byte
under `doc/` ships in the published archive, and a 1080-wide phone screenshot
is four times what a README renders:

```bash
python -c "
from PIL import Image; import glob
for f in glob.glob('doc/screenshots/demo_*.png'):
    im = Image.open(f); w, h = im.size
    im.resize((w // 2, h // 2), Image.LANCZOS).convert(
        'P', palette=Image.ADAPTIVE, colors=192).save(f, optimize=True)
"
```

That step took the seven 2.0.0 screenshots from 1081 KB to 160 KB. If it is
skipped, `dart pub publish --dry-run` will show the archive growing by roughly
a megabyte.
