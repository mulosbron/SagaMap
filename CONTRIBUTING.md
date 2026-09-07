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
