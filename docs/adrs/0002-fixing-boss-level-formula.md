# 2. Fixing the boss level formula and shipping 2.0.0

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

`lib/src/core/domain/loot_table.dart:45`:

```dart
bool isBossLevel(int levelId) => levelId > 0 && levelId % 15 == 0;
```

Per ADR-0001, `id` is zero-based, so this function counts id 15, 30, 45 as
bosses — that is, the **16th, 31st, 46th level** the player sees. "A boss every
15 levels" means `id % 15 == 14`.

That this is not a typo but an internal inconsistency is proven by the
package's own difficulty formula (`saga_map_level_generator.dart:52`):

```dart
difficulty: 1 + (levelId % 5)
```

| id | What the player sees | Difficulty | Today's boss | `% 15 == 14` |
|---|---|---|---|---|
| 14 | level 15 | **5 (hardest)** | ✗ | ✓ |
| 15 | level 16 | **1 (easiest)** | ✓ | ✗ |
| 29 | level 30 | **5** | ✗ | ✓ |
| 30 | level 31 | **1** | ✓ | ✗ |

Today the package **declares the easiest board in the cycle the boss.** The
player doesn't see this as a bug; they assume it's by design and conclude the
boss is easy. The most expensive kind of silent wrong.

The existing test pins the bug down (`test/saga_domain_test.dart:89-95`):

```dart
test('marks every fifteenth level a boss, except level zero', () {
  expect(isBossLevel(15), isTrue);
  expect(isBossLevel(14), isFalse);
});
```

The test's title contradicts its body: "every fifteenth level" is level 15,
and level 15 is id 14. The test protects the bug while believing it verifies
the right thing.

The example app reproduces the same bug (`example/lib/main.dart:349`).

## Decision

The formula is fixed:

```dart
/// Whether [levelId] is a boss level.
///
/// Ids are zero-based (see [LevelData.id]), so "every fifteenth level" — the
/// 15th, 30th, 45th a player sees — is `id % 15 == 14`, not `id % 15 == 0`.
/// The latter lands on the 16th node and, because difficulty is `1 + id % 5`,
/// hands the boss the easiest board in the cycle.
bool isBossLevel(int levelId) => levelId >= 0 && levelId % 15 == 14;
```

The test, the example and the test title are updated to match.

This change is **breaking and requires 2.0.0.** No signature changes and no
field moves, so by semver it looks like a patch; it isn't. Existing players'
recorded reward history shifts by one level — the *meaning* of stored data
changes. That is a major change under this package's own versioning policy
(see `.old/docs/reports/04-surumleme-ve-gecis-plani.md` §2).

Deferring the fix was rejected. The package has one known consumer and the cost
of fixing it is at its lowest possible point today; every new consumer grows
the debt.

## Consequences

### Positive
- The boss now always lands on difficulty 5; three systems (boss, difficulty,
  milestone) align automatically — `id % 15 == 14` coincides with
  `id % 5 == 4`.
- The test title now matches its body; the test genuinely verifies "every
  fifteenth level."
- The example app demonstrates correct behavior and becomes copy-pasteable.

### Negative
- **Players with saved progress are affected:** id 15/30/45 may grant a reward
  a second time; id 14/29/44 may never have granted one. The package cannot
  migrate this, because rewards live in the host's `InventoryRepository` and
  the package never writes there (ADR-0003). The compensation decision belongs
  to the host and must be called out explicitly in the CHANGELOG.
- Shipping 2.0.0 means a manual upgrade for consumers pinned to `^1.0.0`.
- A host that needs the old behavior wants an escape hatch; ADR-0003's
  `bossRule` injection provides it:
  `CompleteLevelUseCase(bossRule: (id) => id > 0 && id % 15 == 0)`.
  This is why the two ADRs ship in the same version.

## Related

- ADR-0001 (id contract) — the basis for this decision
- ADR-0003 (injectable reward) — provides the backward-compat escape hatch
- Task: T-01, T-22
