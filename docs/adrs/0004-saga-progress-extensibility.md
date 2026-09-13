# 4. SagaProgress extensibility: an opaque `extra` field

Date: 2026-09-05

## Status

Accepted — `extra` implemented in 1.1.0; `saveGlobalSeed` in 2.0.0;
`spentStars` and `LevelProgress.starsByMode` in 2.1.0.

## Context

`SagaProgress` carries only two fields (`saga_progress.dart:4-11`):
`currentMaxUnlockedLevelId` and `Map<int, LevelProgress> levels`.
`LevelProgress` is `levelId / state / stars / lastPlayedAt`.

Data the production consumer needs tied to the map, with no counterpart in the
package:

- spent star count (star economy)
- opened chest ids
- first-entered realms
- separate star scores per alternate game mode
- a mistake-free streak counter

None of it fits in `SagaProgress`, so the consumer wrote **a second repository
keeping keys parallel to the package's own JSON in the same box.** One store,
two record layers; keeping them in sync is now the host's job, and nothing
enforces it.

This is the exact opposite of what the `applying-ocp` skill describes: the
model is closed for extension, and the host's only way out is to route around
the package.

## Decision

`SagaProgress` and `LevelProgress` each gain an opaque `extra` field:

```dart
/// Host-owned data the package stores but never interprets.
///
/// Round-tripped through [toJson]/[fromJson] verbatim, so a host can keep spent
/// stars, opened chests or per-mode scores next to progression without running a
/// second persistence layer alongside this one. The package reads nothing from
/// it and will never claim a key.
final Map<String, dynamic> extra;
```

Rules:

- Defaults to `const {}`; existing constructor calls compile unchanged.
- `toJson()` **never writes the key at all** when `extra` is empty — bit
  parity with old records is preserved.
- `fromJson()` produces `{}` if the key is missing or not a `Map` (resilience
  against malformed records, in line with the existing rigor at
  `saga_progress.dart:59-66`).
- The package reads no key inside `extra` and will never claim one in the
  future.

### Options rejected

**`SagaProgressRepository<T extends SagaProgress>` (generic repository).**
Type-safe, but every signature becomes generic and every existing consumer
breaks. The type safety gained doesn't offset the compatibility lost.

**A separate extension registry.** Cleaner, but means two serialization paths,
two files and a registry lifecycle. The over-engineering warning in
`balancing-architectural-tradeoffs` applies: too heavy for a package with one
known consumer.

### On `saveGlobalSeed` (ISP-1)

`SagaProgressRepository` is asymmetric (`saga_progress_repository.dart:4-13`):
there's `loadGlobalSeed()` with no write counterpart. The consumer was forced
to write the seed **as a side effect inside `loadGlobalSeed()`** — a "load"
function writing to disk is the contract forcing the client into a dirty
implementation. A "regenerate the map / change the seed" feature is also
impossible at the contract level.

`Future<void> saveGlobalSeed(int seed)` is added. **In 2.0.0, not 1.1.0**:
adding a method to an `abstract interface class` is source-breaking for any
host implementing the interface, and the only way to hide that breakage (a
default body that throws `UnimplementedError`) is exactly what the LSP item in
the `verifying-solid-compliance` checklist forbids. One version of delay is
cheaper than a lasting LSP violation.

A no-side-effects rule is added to `loadGlobalSeed`'s doc comment.

## Consequences

### Positive
- A host keeps its own data next to progression without writing a second
  persistence layer; the risk of the two layers drifting apart disappears.
- Three features deferred to 2.1.0 (star economy T-16, per-mode scores T-18,
  chest tracking) become solvable on the host side **today** — if the package
  lags, the cost is a stopgap, not a permanent block.
- `LevelProgress.extra` is a natural home for per-mode star scores.
- Serialization stays in one place; the package's JSON becomes the single
  source of truth.

### Negative
- **No type safety.** Whether `extra['spentStars']` is an `int` or a `String`
  isn't known to the compiler. The host must write its own read/write
  wrappers.
- **Key-collision risk.** If the package ever decides to put a key into
  `extra`, it overwrites the host's data. To guard against this, the decision
  text carries the commitment "the package claims no key" — that commitment is
  binding.
- **Bloat risk.** `extra` can grow without bound; a large `extra` is
  serialized on every save. The doc comment needs a "keep it small" warning.
- When first-class fields are added later (T-16 `spentStars`), a migration
  note is needed for a host that had built a stopgap inside `extra`.
- Because `saveGlobalSeed` landed in 2.0.0, the consumer carries the seed-write
  stopgap for one more version.

## Addendum — two fields promoted to first-class in 2.1.0

Two features that could be stopgapped through `extra` were moved into the
package. The `extra` commitment is unchanged: the package still reads no key
inside `extra`, so it does not auto-migrate an old record like
`extra['app.spent_stars']` — the migration note lives in the CHANGELOG.

**Star economy (T-16).** `SagaProgress.spentStars` (default `0`) and
`availableStars`.

- `totalStars` stayed on the extension; `availableStars` was added there too.
  Moving it onto the class would break the `SagaProgressStars(progress).totalStars`
  call form — a break a minor version cannot make. There is one definition.
- Spending has a single path: `SagaProgress? spendStars(int amount)`.
  Insufficient stars is an ordinary moment in play, not an exception, so the
  return is nullable — a nullable return makes the compiler catch an ignored
  rejected purchase. `amount <= 0` throws `ArgumentError`.
- The constructor rejects a negative value or one above `totalStars` with
  `ArgumentError`; `fromJson` clamps the same values instead (a loaded record
  is data that must load, a constructor call is code that can be fixed).
- `toJson` omits the key when `spentStars == 0`; 2.0.0 JSON stays bit-for-bit
  identical.

**Replay modes (T-18).** `LevelProgress.starsByMode` and `execute(modeId:)`.

- The default mode is `null`; its score stays in `stars`. `''`, whitespace
  only, and `'default'` throw `ArgumentError` — otherwise the default mode
  would have two scores that could disagree.
- A mode run **does not unlock**, does not change `stars` or `state`, and is
  never consulted by `canUnlock`; otherwise a hard mode run would double-count
  progression.
- A mode run **never drops a boss reward**; the reward belongs to the first
  clear, and the first clear belongs to the default mode.
- Mode stars don't count toward `totalStars` and cannot be spent.

## Related

- Task: T-03, T-09, T-16, T-18
- Finding: ISP-1 (`.old/docs/reports/01-solid-uyumluluk-denetimi.md`)
- `.old/docs/reports/04-surumleme-ve-gecis-plani.md` §5 (T-09 version decision)
