# 9. Treating a client-side rolled reward as advisory

Date: 2026-09-07

## Status

Accepted — implemented in 2.0.0.

## Context

The boss reward is a pure function: `rollBossReward` seeds itself with
`levelId ^ globalSeed`, and the same triple `(levelId, globalSeed, table)`
always yields the same item. This is a property the package has wanted from
the start — the same seed should produce the same world, a bug should be
replayable, golden tests should be stable.

2.0.0 added `saveGlobalSeed` (ADR-0004). The seed can now be written by the
host. For a player holding the device, that means:

1. change the saved seed,
2. run `rollBossReward(levelId: 14, globalSeed: candidateSeed)` offline,
   before clearing the boss,
3. find the seed that drops the legendary item, save it, then clear the boss.

This isn't an "exploit" but a direct consequence of the architecture: a pure,
deterministic function running on the client has its input written by that
same client. Yet the package's own comments talk about "first-clear integrity"
inside `execute` (`complete_level_usecase.dart`), and a host that promotes
inventory to a server can trust that phrase and inherit the hole.

## Decision

| Option | Pro | Con |
|---|---|---|
| **A. Write down the trust boundary, don't change behavior** | Reproducibility preserved; golden tests and debugging stay intact; host builds its own authority on top | Seed manipulation stays free |
| B. Mix an un-choosable value into the roll (first-clear timestamp, a per-install salt) | Seed manipulation stops being free | Same seed no longer gives the same world; determinism, the property ADR-0004 and the golden tests depend on, is lost |
| C. Leave the reward entirely to the host | Package claims nothing | The "working default" that ships with `kMvpLootTable` is gone |

**A is chosen.** Determinism and client-side integrity can't be had at the same
time: one requires that output be computable from input, the other requires
exactly that this be prevented. In a package that runs on the client, as long
as the device's owner can write the input, the second can never actually be
guaranteed — calling it "prevented" without a server-side authority produces
only the illusion of a barrier, not the barrier itself.

So the package keeps determinism and writes the boundary explicitly:
**a client-side rolled reward is advisory, not authoritative.** A host that
wants authority rolls the reward server-side; `rollBossReward` remains there to
*preview* what would drop.

Option B could in principle use a salt, but the salt is also stored on the
device; since the player can read the salt too, the cost rises without moving
the boundary. Only determinism is lost.

## Consequences

### Positive

- The same seed produces the same world and the same reward; golden tests, bug
  report reproduction, and `--platform chrome` parity (T-03) are preserved.
- The boundary is written down: `saveGlobalSeed` and `rollBossReward` doc
  comments and the README security note say the same thing — the host knows
  what it's inheriting.
- A path is open and single-step for a host that wants server authority: roll
  the reward server-side, demote the client-side call to a preview.

### Negative

- For a player holding the device, seed manipulation stays free.
- The package cannot guarantee "first-clear integrity" on its own; the
  first-clear guard inside `execute` is a convenience, not a security boundary
  (T-13).
