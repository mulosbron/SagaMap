# 5. Promoting the gate from a movement barrier to a progress barrier

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

`SagaMapGate` and `clampTravelThroughGates` (`saga_map_gate.dart`) model the
gate as a **movement** barrier. The doc comment says so outright: "The library
positions the gate and stops the character at it."

A source scan shows a heavier picture than that:

```
$ grep -rn "clampTravelThroughGates" lib
lib/src/rendering/character/saga_character_controller.dart:39:  /// [clampTravelThroughGates].   ← a doc comment only
lib/src/rendering/character/saga_map_gate.dart:36:double clampTravelThroughGates(  ← the definition itself
```

So the function is **never called anywhere** inside the package. It has no
`gates` parameter on `SagaInfiniteMapView`
(`saga_infinite_map_view.dart:60-152`). The gate is a helper function the
package exports but never uses itself: if the host doesn't call it by hand,
the gate does nothing.

Worse, the gate is wired into none of three systems:

| System | Aware of the gate |
|---|---|
| Character walking | ❌ host must call it manually |
| Node tap (`SagaNodeInteractionPolicy`) | ❌ |
| Unlocking (`CompleteLevelUseCase`) | ❌ `:69` unconditionally does `levelId + 1` |

Result: the "don't open the next block until the previous boss is cleared"
mechanic **does not exist** in the package. The production consumer rewrote it
on the host side as `BossRules.isUnlocked(...)`, **replacing** the package's
own unlock logic entirely. The package's own progression model is disabled.

Conceptual root cause: in game design a gate is a **progress** barrier; the
package treats it as a visual/movement barrier. The model itself is
incomplete.

## Decision

The gate is wired into the progression system through three seams. All three
are optional; when none is supplied, behavior stays byte-identical to 1.x.

**1. Interaction — tapping consults the gate**
```dart
class SagaNodeInteractionPolicy {
  /// Host veto on reaching a node at all — a closed gate, a ticket, a purchase.
  ///
  /// Consulted before [canTap]: returning false makes the node unreachable
  /// regardless of its recorded progress state, and the node is announced,
  /// focused and cursored as locked.
  final bool Function(LevelData level, LevelProgress? progress)? isReachable;
}
```

**2. Progression — unlocking consults the gate**
```dart
class CompleteLevelUseCase {
  /// Vetoes unlocking the successor. Returning false completes the level but
  /// leaves the next one locked — the gate stays shut.
  final bool Function(int levelId)? canUnlock;
}
```

**3. Rendering — the package carries the gates**
```dart
class SagaInfiniteMapView {
  /// Barriers on the path. The view applies [clampTravelThroughGates] itself.
  final List<SagaMapGate> gates;
}
```

**Whether the gate is open** stays the host's call — a ticket, a friend, a
purchase is game economy, not map geometry. The package only propagates the
consequences of that decision into all three systems at once.

Writing gate state into the package's own model (`SagaProgress`) was rejected:
gate conditions are game-specific and depend on data the package can't know.
The hook is the right level of abstraction.

## Consequences

### Positive
- The gate concept is completed: the same gate stops the character, blocks the
  tap, and blocks the unlock. Three systems, one source of truth.
- The host no longer needs to **replace** the package's progression logic;
  extending it is enough. Today, `CompleteLevelUseCase` was effectively
  unusable for this.
- `isReachable` aligns with accessibility for free: an unreachable node is
  skipped in Tab order and announced as "locked" to the screen reader, because
  `canTap` already drives all three at once
  (`widget_renderer_adapter.dart:127-135`).
- With the `gates` parameter, the gate becomes for the first time a concept the
  package itself uses; the exported-but-unused-function anomaly closes.

### Negative
- **A new outcome appears in `CompleteLevelResult`:** "completed, but the
  successor didn't unlock." A host that doesn't read this can't show the
  player why they can't progress. The result object may need a descriptive
  field (`unlockBlocked`) — to be settled during implementation.
- Two new hooks, two new ways to misuse them: if `isReachable` and `canUnlock`
  disagree (a level that's tappable but never unlocks), a strange state
  results. Doc comments must show how the two are meant to be used together.
- `canUnlock` creates a concept that overlaps with the `enforceUnlockOrder`
  flag. The relationship needs to be made explicit: `enforceUnlockOrder` guards
  backward (blocks skipping ahead), `canUnlock` guards forward (the gate).
- `SagaInfiniteMapView` gains one more parameter; the class is already 657
  lines (an SRP-1 note). Gate logic should move to a separate helper, not be
  embedded in `build`.
- Breaking: the semantic change and new signatures require 2.0.0.

## Related

- Task: T-06
- Finding: DIP-2, OCP-4 (`.old/docs/reports/01-solid-uyumluluk-denetimi.md`)
