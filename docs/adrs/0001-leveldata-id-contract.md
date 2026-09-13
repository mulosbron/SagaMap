# 1. LevelData.id contract: zero-based, id + 1 in display

Date: 2026-09-05

## Status

Accepted — implemented in 1.1.0.

## Context

The base of `LevelData.id` is written down nowhere. `README.md` never raises the
question, not even at line 458. The result is the source contradicting itself:

| Site | Assumption |
|---|---|
| `saga_map_level_generator.dart:34` — `levelId = startLevelId + offset`, host passes `0` for the first chunk | zero-based |
| `saga_map_level_generator.dart:52` — `difficulty: 1 + (levelId % 5)`, id 0 → difficulty 1 (easiest) | zero-based |
| `saga_progress.dart:14-25` — `SagaProgress.initial()` unlocks level `0` | zero-based |
| `loot_table.dart:45` — `isBossLevel(id) => id > 0 && id % 15 == 0` | **one-based** |
| `widget_renderer_adapter.dart:37` — `'Level ${level.id}'` | raw index |

Four of five call sites are zero-based, one isn't, and one is undecided. This is
not a coding mistake; it is the inevitable result of an unwritten contract. The
first consumer in production (SudokuLens) tripped on exactly this point and
reported it.

Downstream issues: H1 (a boss level slips), H2 (the screen reader says
"Level 0"), B4-2 (README stays silent), B4-4 (the example reproduces the bug).

## Decision

`LevelData.id` **is zero-based.** This is already the dominant assumption in the
code and is the contract `SagaProgress.initial()` and the generator share; it
cannot change.

Two rules follow:

1. **Storage and logic use the raw `id`.** Unlocking, progression, persistence,
   list access — all of it zero-based.
2. **Every number shown to the player is `id + 1`.** The digit on the node, the
   screen-reader label, the chapter title, any text like "level 15".

The contract is written in three places:
- one sentence in the `LevelData` class doc,
- a "Level ids" heading in `README.md`,
- the doc comment of every function whose decision depends on the base
  (`isBossLevel`, `defaultSagaNodeSemanticsLabel`).

## Consequences

### Positive
- The four downstream issues (H1, H2, B4-2, B4-4) collapse into enforcing one
  contract.
- The mistake a new consumer would otherwise make first is closed off.
- `difficulty`, `isBossLevel` and the milestone systems align on the same base:
  `id % 15 == 14` coincides with `id % 5 == 4`, so the boss always lands on the
  hardest board.
- Every future API decision now has a reference to answer against ("is this
  number raw, or display?").

### Negative
- Fixing `isBossLevel` is breaking (see ADR-0002); writing the contract down
  automatically forces a major version.
- Host code keeps a constant mental translation between `id` and `id + 1`. A
  dedicated `DisplayLevelNumber` type could close that gap, but a single-field
  wrapper type costs more at this scale than it buys — rejected.
- Existing consumers need to audit whether their own UI shows `id` raw.

## Related

- ADR-0002 (boss formula)
- Task: T-19, T-02, T-01, T-22
