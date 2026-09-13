# Spec: Performance & Architecture Governance Improvements (v2.1.1)

- **Date:** 2026-09-13
- **Status:** Draft / Pending Review
- **Scope:** Priority 1 & 2 Quick Wins from Architecture Audit

---

## 1. Context & Motivation

Following the comprehensive architectural review of SagaMap v2.1.0 across 5 specialized evaluator subagents, three high-impact, non-breaking improvements were selected for immediate implementation:
1. **Repaint Boundary Isolation:** Preventing frame-by-frame raster invalidation of heavy Bézier spline paths during character animations.
2. **Eviction Latch Fix:** Resolving the memory latch in `SagaInfiniteMapController._evictIfNeeded` during continuous infinite scrolling.
3. **ADR-0011 Catalog Synchronization:** Restoring the missing entry for ADR-0011 in `docs/adrs/README.md`.

---

## 2. Technical Design

### 2.1 Repaint Boundary Isolation (`MapChunkWidget`)
- **Location:** `lib/src/rendering/widgets/map_chunk_widget.dart`
- **Change:**
  - Wrap `Positioned.fill(child: CustomPaint(painter: chunkPainter))` in a `RepaintBoundary`.
  - Wrap `Positioned.fill(child: _SagaCharacterLayer(...))` in a `RepaintBoundary`.
- **Verification:**
  - Ensure all golden tests pass (`flutter test test/golden/`).
  - Verify that character motion does not invalidate the chunk's static background/path rendering layer.

### 2.2 Eviction Latch Fix (`SagaInfiniteMapController`)
- **Location:** `lib/src/rendering/controllers/saga_infinite_map_controller.dart`
- **Change:**
  - In `_evictIfNeeded()`, ensure that chunks requested far from `_lastRequestedIndex` are not permanently protected if `_chunks.length > budget`.
  - Prune `_requestedSinceEviction` to only protect indices in the active working neighborhood (e.g. `(index - _lastRequestedIndex).abs() <= 2`), allowing chunks far behind the scroll position to be evicted cleanly.
- **Verification:**
  - Ensure all chunk retention unit tests pass (`test/saga_chunk_retention_test.dart`).

### 2.3 ADR-0011 Index Synchronization
- **Location:** `docs/adrs/README.md`
- **Change:**
  - Add row for ADR-0011 in the index table:
    `| [0011](0011-reconciling-unlock-pointer-with-records.md) | Reconciling unlock pointer with records, and 1.x migration | Accepted | 2.0.0 | SAST V-1, V-2 |`
- **Verification:**
  - Ensure `test/release_hygiene_test.dart` passes (all ADR citations resolve, no conflict markers, no mojibake).

---

## 3. Risk Assessment
- **Breaking Changes:** None (100% backwards-compatible).
- **SemVer Impact:** Patch release (`2.1.1` or internal polish).
