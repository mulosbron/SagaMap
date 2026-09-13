# 3. Making the reward system injectable via Strategy + Constructor Injection

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0; `InventoryRepository` injection
(`executeAndPersist`) and the pity rule (`SagaPityRule`) in 2.1.0.

## Context

`CompleteLevelUseCase` — the package's highest-level business logic — is
directly wired to domain rules (`complete_level_usecase.dart:95,102`):

```dart
if (!isBossLevel(levelId) || !firstClear) { ... }
reward: rollBossReward(levelId: levelId, globalSeed: globalSeed, now: now),
```

What it's wired to isn't an abstraction but compile-time constants:

- `isBossLevel` — a top-level function (`loot_table.dart:45`)
- `rollBossReward` — a top-level function that **does not accept** a table
  parameter (`:48`)
- `kMvpLootTable` — a global `const`, read directly from inside
  `rollBossReward` (`:54,57`)

Worse, `const CompleteLevelUseCase()` (line 21) accepts no dependencies at all.
Calling a top-level function in Dart is the exact counterpart of the
`new SmtpEmailService()` anti-pattern the `applying-dip` skill warns against.

Two concrete consequences:

**1. For the host:** it cannot use its own reward table, its own rarities, or
its own boss range. The production consumer therefore could not use the
package's `loot_table` + `inventory_repository` + `InventoryItem` trio **at
all**; it rewrote all of it on the app side. A whole subsystem of the package
is effectively dead code.

**2. For the package:** the reward path cannot be tested.
`complete_level_usecase_test.dart` can only exercise the reward through the
real `kMvpLootTable` — meaning adding one item to the table breaks passing
tests that never claimed anything about the table. The test is coupled to
something it never meant to verify.

## Decision

The `applying-dip` (Constructor Injection) and `applying-strategy-pattern`
recipes are applied. Rules move from constants to parameters; defaults are
preserved.

```dart
/// Decides whether a level is a boss encounter.
typedef SagaBossRule = bool Function(int levelId);

class CompleteLevelUseCase {
  const CompleteLevelUseCase({
    this.bossRule = isBossLevel,
    this.lootTable = kMvpLootTable,
  });

  /// Which levels drop a boss reward. Defaults to every fifteenth level.
  final SagaBossRule bossRule;

  /// Weighted table the reward is rolled from.
  final List<LootTableEntry> lootTable;
}

InventoryItem rollBossReward({
  required int levelId,
  required int globalSeed,
  List<LootTableEntry> table = kMvpLootTable,
  DateTime? now,
});
```

Additional decisions:

- **An empty or zero-weighted table throws `ArgumentError`.** Silently falling
  back to `kMvpLootTable` is forbidden: a host that believes its own table is
  active while the package hands out items from its default is the hardest
  kind of bug to diagnose.
- **`isBossLevel` stays public.** The reason changes: today it's public
  because there's no other way; from now on it's public because it's the
  default value of `bossRule`. This answers question B4-3 from the consumer
  report.
- **Determinism is preserved.** The `Random(levelId ^ globalSeed)` seeding is
  unchanged; the same `(levelId, globalSeed, table)` always yields the same
  item.
- **`InventoryRepository` injection is out of scope for this ADR** — deferred
  to 2.1.0 (T-14). 2.0.0 only writes the contract: *"reward is returned, not
  persisted."*

A `typedef` was chosen over a class hierarchy (`abstract class BossRule` plus
subclasses). The rule is single-method and stateless; building a class trips
the "over-engineering" red flag in the `balancing-architectural-tradeoffs`
skill. In Dart, a function type is already a fully qualified strategy.

## Consequences

### Positive
- A host can build its own reward economy inside the package; the
  `loot_table` subsystem stops being dead.
- The reward path becomes testable. Target: after T-04, no `kMvpLootTable`
  reference remains in `complete_level_usecase_test.dart`.
- SRP-1 closes on its own: `execute` becomes "apply the completion, ask the
  strategy for the reward decision"; it no longer changes when the reward
  rule changes.
- ADR-0002's breaking fix gets an escape hatch:
  `bossRule: (id) => id > 0 && id % 15 == 0` restores the old behavior
  exactly. This is why the two ADRs ship in the same version.
- A2 (`rarityOdds`) and A3 (pity) build on this decision; neither was possible
  without a table parameter.

### Negative
- The `rollBossReward` signature changes. It's source-compatible since the
  parameter is optional, but there's a behavior-breaking edge case now that an
  empty table throws.
- `CompleteLevelUseCase` gains two fields; staying `const` requires the
  defaults to be `const` expressions (`isBossLevel` is a top-level function
  reference, `kMvpLootTable` is a `const` list — both qualify).
- A host can now pass a malformed table (weights summing to 0, negative
  weights). Validation cost shifts to the package — the reason for the
  `ArgumentError` decision.
- Keeping `isBossLevel` public forecloses the chance to shrink the API
  surface. Accepted: it must be visible as the default value.

## Addendum — decisions made in 2.1.0

**`InventoryRepository` injection (T-14).** `CompleteLevelUseCase` gained an
`inventory` field. `execute` stayed synchronous: the repository returns a
`Future`, and turning `execute` into a `Future` would break every caller.
Writing lives in a separate entry point:
`Future<CompleteLevelResult> executeAndPersist(...)`.

- If the write fails, the exception **propagates**; no result is returned.
  Progress counts as unwritten; making the reward write and the progress
  record one atomic operation is not something the package controls —
  atomicity is the host's to build.
- Calling `executeAndPersist` without `inventory` throws `StateError`. A
  method named "persist" silently not writing is exactly the mistake this
  entry point exists to remove.
- `CompleteLevelResult.rewardPersisted` is `true` only when a reward was
  actually written. `execute` never writes under any condition.
- **Open edge case:** the first-clear guard still reads from the snapshot it
  was given; two calls with the same `currentProgress` both write. Owning the
  write closed the "returned reward gets dropped" hole, not this one. Pinned
  by a test.

**Pity rule (T-13 / A3).** `SagaPityRule(threshold, guaranteedRarity)`. The
counter lives on the host because it's save data; the rule stays in the
package so every consumer applies the same rule (including the `nextCounter`
reset rule).

- The counter feeds the **filter**, not the seed; determinism is preserved.
- If no entry at the eligible rarity exists (or all are zero-weighted), it
  falls back to a normal roll — no exception: a table with no rare tier is a
  legitimate economy.
- The whole table is still validated; a broken table is rejected on every
  roll, not only on unlucky ones.

## Related

- ADR-0002 (boss formula) — ships in the same version
- Task: T-04, T-12, T-13, T-14
- Finding: DIP-1, OCP-1, OCP-2, SRP-1 (`.old/docs/reports/01-solid-uyumluluk-denetimi.md`)
