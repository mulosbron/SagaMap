# 11. Reconciling the unlock pointer with records, and an explicit migration entry for 1.x

Date: 2026-09-07

## Status

Accepted — implemented in 2.0.0.

## Context

`694bca7` bundled two mutually dependent changes into the same version:

1. `SagaProgress.fromJson` started clamping `currentMaxUnlockedLevelId` to
   `max(levels.keys) + 1`.
2. `CompleteLevelUseCase.enforceUnlockOrder` defaulted to `true`.

An audit (`sast/verification-report-2.0.0.md`, V-1 and V-2) showed both were
incomplete:

**The clamp counted every key.** Record state was never read, so a single
forged record in `locked` state could carry the ceiling wherever it wanted.
Verified by running it: loading
`{'currentMaxUnlockedLevelId': 999999, 'levels': {'0': unlocked, '999998':
locked}}` left the pointer at 999999, and with the guard on,
`CompleteLevelUseCase()` completed 999998 anyway. That is, 2.0.0's most visible
security claim — "a tampered record can't grant itself the pointer the guard
relies on" — didn't hold.

**The clamp silently hit 1.x installs.** 1.x read a level with no record as
"unlocked if it's under the pointer," so it was entirely normal for a 1.x
host to persist a sparse `levels` map alongside an advanced pointer. When
2.0.0 loads the same record, the pointer drops, and `enforceUnlockOrder` then
rejects every level above it. For the player, that's progress erased. The
CHANGELOG described the clamp only as a tamper defense and never mentioned
migration.

## Decision

**The ceiling folds over completed records, but a pointer can also justify
itself with its own record.**

The rule in one sentence: *a pointer must be justified either by a completion
below it, or by its own record — never by an unrelated level's record.*

- `completed` is the only state the package itself writes as the outcome of
  play; it's the only record the ceiling can fold over. With no completions at
  all, the ceiling is `0`.
- If the record **at the pointer itself** is `unlocked` or `completed`, the
  pointer stays as is. This is a host deliberately skipping ahead — a
  chapter-skip purchase, a debug build, `enforceUnlockOrder: false` — and it
  said so by writing the record. Folding only over completions would corrupt
  this host's records on every load.

An attacker can of course write `999999: unlocked`; but then they've written a
record for exactly the level they wanted. What closes is this: **a level's
record is no longer a claim about some other level.** A save file is entirely
under the host's control, so there is no absolute security boundary to be won
here (ADR-0009); what's won is that the pointer is now internally consistent
with the file itself.

**The clamp is kept, its silence is not** (option (a) from the audit):
`fromJson` accepts an optional `onClamp` callback and hands back a
`SagaProgressClamp` whenever the pointer actually moved. Default behavior is
unchanged — `fromJson` runs on every load and stays quiet by default — but it
is no longer unreportable.

**An explicit migration entry is also added** (option (c) from the audit):
`SagaProgress.migrateFrom1x` backfills every id with no record in the
`[0, pointer]` range as `unlocked`, keeping the stored pointer as is. It
grants no stars and completes nothing; it only restores the accessibility 1.x
reads used to grant. `maxBackfill` (default `10000`) bounds the work a hostile
pointer could force.

## Consequences

- The audit's V-1 attack payload now drops the pointer to `0`; 999998 can no
  longer be completed with the guard on.
- `migrateFrom1x` **trusts the stored pointer** — that's exactly the guarantee
  `fromJson` withholds. Its contract: call it only on a payload you know your
  own 1.x build wrote, once, at upgrade time; persist the result; every load
  after that goes through `fromJson` again.
- A fresh save file's ceiling is now `0`, not `1`: `initial()` writes level 0
  as `unlocked`, not `completed`. Nothing cleared means nothing unlocked.
- `SagaProgressClamp` is a new public type, exported via `saga_map.dart`.
- The migration is documented under a "Migration — 1.x saves" heading in the
  2.0.0 CHANGELOG and the README's "Upgrading from 1.x" section; the version
  gate (`test/saga_2_0_0_upgrade_test.dart`) now carries a second 1.1.0
  fixture, with a **gap**, that actually triggers the clamp. In the old
  fixture the pointer was 16 and the highest completion 15, so the clamp was a
  no-op there — the danger never passed through that gate at all.
