# Performance & Architecture Governance Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement render repaint isolation in `MapChunkWidget`, resolve the eviction latch in `SagaInfiniteMapController`, and synchronize the ADR-0011 entry in `docs/adrs/README.md`.

**Architecture:** 
- Render optimization leverages Flutter's `RepaintBoundary` to isolate animated character ticks from the static spline/background canvas.
- Controller eviction is refined to prune stale chunks while protecting only the active working set around the current read index.
- Architectural catalog synchronization ensures complete traceability for ADR-0011.

**Tech Stack:** Flutter, Dart, Flutter Test.

## Global Constraints
- Zero breaking changes to public APIs.
- All existing 688 unit tests, golden tests, and 49 release hygiene tests must remain green.
- No new external package dependencies.

---

### Task 1: Repaint Boundary Isolation in `MapChunkWidget`

**Files:**
- Modify: `lib/src/rendering/widgets/map_chunk_widget.dart:303-315`
- Test: `test/map_chunk_widget_test.dart`

**Interfaces:**
- Consumes: `chunkPainter: CustomPainter`, `_SagaCharacterLayer`
- Produces: Isolated repaint boundaries in widget tree

- [ ] **Step 1: Add widget test asserting `RepaintBoundary` wrappers exist**

In `test/map_chunk_widget_test.dart`:
```dart
testWidgets('chunk painter and character layer are wrapped in RepaintBoundary', (tester) async {
  // Build MapChunkWidget with character and verify RepaintBoundary ancestors
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapChunkWidget(
          chunkIndex: 0,
          levels: const [],
          config: SagaMapConfig.defaultConfig,
          character: const SagaCharacter(
            assetPath: 'assets/character.png',
            size: Size(32, 32),
          ),
          // ... minimal required params
        ),
      ),
    ),
  );
  expect(find.byType(RepaintBoundary), findsAtLeastNWidgets(2));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/map_chunk_widget_test.dart`
Expected: FAIL (fewer RepaintBoundary widgets found than expected).

- [ ] **Step 3: Wrap `CustomPaint` and `_SagaCharacterLayer` with `RepaintBoundary`**

In `lib/src/rendering/widgets/map_chunk_widget.dart`:
```dart
Positioned.fill(
  child: RepaintBoundary(
    child: CustomPaint(painter: chunkPainter),
  ),
),
...nodeWidgets,
if (character != null)
  Positioned.fill(
    child: RepaintBoundary(
      child: _SagaCharacterLayer(
        character: character!,
        renderContext: renderContext,
        characterKey: characterKey,
      ),
    ),
  ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/map_chunk_widget_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify goldens pass with RepaintBoundary in place**

Run: `flutter test test/golden/`
Expected: All golden tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/rendering/widgets/map_chunk_widget.dart test/map_chunk_widget_test.dart
git commit -m "perf: isolate chunk painter and character layer with RepaintBoundary"
```

---

### Task 2: Eviction Latch Fix in `SagaInfiniteMapController`

**Files:**
- Modify: `lib/src/rendering/controllers/saga_infinite_map_controller.dart:170-194`
- Test: `test/saga_chunk_retention_test.dart`

**Interfaces:**
- Consumes: `_requestedSinceEviction: Set<int>`, `maxRetainedChunks: int?`, `_lastRequestedIndex: int`
- Produces: Continuous mid-scroll eviction without frozen working-set latch

- [ ] **Step 1: Write test in `test/saga_chunk_retention_test.dart` for mid-scroll eviction**

Add test verifying that scrolling across 10 chunks with `maxRetainedChunks: 3` keeps total retained count bounded near 3, evicting chunks far behind:
```dart
testWidgets('mid-scroll eviction continues to evict far chunks', (tester) async {
  final harness = _controller(maxRetainedChunks: 3, initialChunkCount: 8);
  addTearDown(harness.controller.dispose);
  await harness.controller.initialize();

  // Scroll forward sequentially through 6 chunks
  for (var i = 0; i < 6; i++) {
    harness.controller.chunkLevels(i);
  }
  // Eviction should keep retained count close to budget, dropping far chunks (e.g. chunk 0)
  expect(harness.controller.retainedChunkCount, lessThanOrEqualTo(4));
  expect(harness.controller.chunkLevels(0), isEmpty);
});
```

- [ ] **Step 2: Run test to verify it fails or exposes the latch**

Run: `flutter test test/saga_chunk_retention_test.dart`
Expected: Test fails if candidate list was empty and chunk 0 was not evicted.

- [ ] **Step 3: Update `_evictIfNeeded` in `saga_infinite_map_controller.dart`**

Ensure `_requestedSinceEviction` only protects indices in the immediate neighborhood of `_lastRequestedIndex` (e.g. `(index - _lastRequestedIndex).abs() <= 1` or up to budget size):
```dart
void _evictIfNeeded() {
  final budget = maxRetainedChunks;
  if (budget == null) return;

  if (_chunks.length > budget) {
    // Only protect chunks close to the current read anchor; far-away chunks can be evicted.
    final protectedRadius = budget <= 2 ? 1 : (budget ~/ 2);
    final candidates = _chunks.keys
        .where((index) {
          final isNear = (index - _lastRequestedIndex).abs() <= protectedRadius;
          return !isNear || !_requestedSinceEviction.contains(index);
        })
        .toList()
      ..sort((a, b) {
        final byDistance = (a - _lastRequestedIndex)
            .abs()
            .compareTo((b - _lastRequestedIndex).abs());
        return byDistance != 0 ? byDistance : b.compareTo(a);
      });

    for (final index in candidates.reversed) {
      if (_chunks.length <= budget) break;
      _chunks.remove(index);
    }
  }

  if (_chunks.length <= budget) {
    _requestedSinceEviction.clear();
  } else {
    // Prune requested indices that are far away from current read position
    _requestedSinceEviction.removeWhere((i) => (i - _lastRequestedIndex).abs() > budget);
  }
}
```

- [ ] **Step 4: Run chunk retention tests**

Run: `flutter test test/saga_chunk_retention_test.dart`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/controllers/saga_infinite_map_controller.dart test/saga_chunk_retention_test.dart
git commit -m "fix(perf): resolve working-set eviction latch during continuous scrolling"
```

---

### Task 3: ADR-0011 Catalog Synchronization in `docs/adrs/README.md`

**Files:**
- Modify: `docs/adrs/README.md:23-24`
- Test: `test/release_hygiene_test.dart`

**Interfaces:**
- Consumes: `docs/adrs/0011-reconciling-unlock-pointer-with-records.md`
- Produces: Complete index table in `docs/adrs/README.md`

- [ ] **Step 1: Add ADR-0011 row to table in `docs/adrs/README.md`**

```markdown
| [0011](0011-reconciling-unlock-pointer-with-records.md) | Reconciling unlock pointer with records, and 1.x migration | Accepted | 2.0.0 | SAST V-1, V-2 |
```

- [ ] **Step 2: Run release hygiene test**

Run: `flutter test test/release_hygiene_test.dart`
Expected: ALL PASS (49+ tests passed, no conflict markers, all ADRs tracked and cited).

- [ ] **Step 3: Commit**

```bash
git add docs/adrs/README.md
git commit -m "docs(adr): add ADR-0011 to catalog index"
```
