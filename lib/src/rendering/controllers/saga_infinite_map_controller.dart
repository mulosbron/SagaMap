import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/domain/models/level_data.dart';
import '../../core/domain/saga_map_chunk_constants.dart';

/// Async chunk loader callback used by [SagaInfiniteMapController].
typedef SagaChunkLevelLoader = FutureOr<List<LevelData>> Function(
  int chunkIndex,
  int sectionsPerChunk,
);

/// Stateful controller that manages lazy loading map chunks.
///
/// Set [maxRetainedChunks] to bound memory on a genuinely endless map: chunks
/// far from the ones being read are dropped, and reloaded on demand if the user
/// scrolls back. Loaders are expected to be deterministic, so a reloaded chunk
/// is identical to the one that was dropped.
class SagaInfiniteMapController extends ChangeNotifier {
  final SagaChunkLevelLoader chunkLoader;
  final int sectionsPerChunk;
  final int initialChunkCount;
  final int loadBatchSize;
  final int? maxChunkCount;

  /// Target number of chunks kept in memory, or `null` to keep every chunk ever
  /// loaded.
  ///
  /// A target rather than a hard cap: chunks requested since the last eviction
  /// are never dropped, so a budget smaller than what the viewport is currently
  /// showing is simply exceeded rather than causing an
  /// evict-reload-evict thrash. Chunks beyond that working set are dropped
  /// furthest-away-first.
  final int? maxRetainedChunks;

  final Map<int, List<LevelData>> _chunks = <int, List<LevelData>>{};
  final Set<int> _reloading = <int>{};

  /// Working set: indices the UI has asked for since the last eviction pass.
  final Set<int> _requestedSinceEviction = <int>{};
  bool _isLoading = false;
  Object? _lastError;
  int _nextChunkIndex = 0;
  int _lastRequestedIndex = 0;
  bool _disposed = false;

  SagaInfiniteMapController({
    required this.chunkLoader,
    this.sectionsPerChunk = kSagaMapChunkSize,
    this.initialChunkCount = 3,
    this.loadBatchSize = 2,
    this.maxChunkCount,
    this.maxRetainedChunks,
  })  : assert(sectionsPerChunk > 0, 'sectionsPerChunk must be greater than 0'),
        assert(
          maxRetainedChunks == null || maxRetainedChunks > 0,
          'maxRetainedChunks must be greater than 0',
        );

  /// True while a chunk batch is being loaded.
  bool get isLoading => _isLoading;

  /// Last loader error, if any.
  Object? get lastError => _lastError;

  /// Highest chunk index reached, whether or not it is still in memory.
  int get loadedChunkCount => _nextChunkIndex;

  /// Chunks currently held in memory. Equal to [loadedChunkCount] unless
  /// [maxRetainedChunks] has forced evictions.
  int get retainedChunkCount => _chunks.length;

  /// Whether configured [maxChunkCount] has been reached.
  bool get hasReachedEnd {
    if (maxChunkCount == null) return false;
    return _nextChunkIndex >= maxChunkCount!;
  }

  /// Returns levels loaded for the requested chunk.
  ///
  /// Safe to call during build. If the chunk was evicted, this returns empty
  /// and schedules a reload for after the current frame — never notifying
  /// listeners mid-build.
  List<LevelData> chunkLevels(int chunkIndex) {
    _lastRequestedIndex = chunkIndex;
    _requestedSinceEviction.add(chunkIndex);
    final levels = _chunks[chunkIndex];
    if (levels != null) return levels;
    if (chunkIndex >= 0 && chunkIndex < _nextChunkIndex) {
      _scheduleReload(chunkIndex);
    }
    return const <LevelData>[];
  }

  /// Loads initial chunk set once.
  Future<void> initialize() async {
    if (_nextChunkIndex > 0 || _isLoading) return;
    await loadMore(count: initialChunkCount);
  }

  /// Loads more chunks according to controller strategy.
  Future<void> loadMore({int? count}) async {
    if (_isLoading || hasReachedEnd) return;
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    final requestedCount = count ?? loadBatchSize;
    final targetCount = _clampLoadCount(requestedCount);
    if (targetCount <= 0) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      for (var i = 0; i < targetCount; i++) {
        final index = _nextChunkIndex;
        final levels = await chunkLoader(index, sectionsPerChunk);
        _chunks[index] = levels;
        _nextChunkIndex++;
      }
      _evictIfNeeded();
    } catch (error) {
      _lastError = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Drops chunks outside the working set, furthest from the read position
  /// first, until the retention budget is met.
  ///
  /// Chunks in [_requestedSinceEviction] are never dropped. Without that
  /// protection a budget smaller than the viewport's working set would evict a
  /// chunk that is immediately requested again, reloaded, and evicted once
  /// more — an endless rebuild loop rather than a memory saving.
  void _evictIfNeeded() {
    final budget = maxRetainedChunks;
    if (budget == null) return;

    if (_chunks.length > budget) {
      final candidates = _chunks.keys
          .where((index) => !_requestedSinceEviction.contains(index))
          .toList()
        ..sort((a, b) {
          final byDistance = (a - _lastRequestedIndex)
              .abs()
              .compareTo((b - _lastRequestedIndex).abs());
          // Ties go to the lower index: scrolling forward is the common case,
          // so prefer keeping what lies ahead.
          return byDistance != 0 ? byDistance : b.compareTo(a);
        });

      for (final index in candidates.reversed) {
        if (_chunks.length <= budget) break;
        _chunks.remove(index);
      }
    }

    _requestedSinceEviction.clear();
  }

  void _scheduleReload(int chunkIndex) {
    if (_disposed || !_reloading.add(chunkIndex)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (_disposed) return;
      try {
        final levels = await chunkLoader(chunkIndex, sectionsPerChunk);
        if (_disposed) return;
        // Deliberately no eviction here: a reload is proof the chunk is in the
        // working set, and evicting on this path is what would close the loop.
        _chunks[chunkIndex] = levels;
      } catch (error) {
        if (_disposed) return;
        _lastError = error;
      } finally {
        _reloading.remove(chunkIndex);
      }
      if (!_disposed) notifyListeners();
    });
  }

  int _clampLoadCount(int requestedCount) {
    final configuredMax = maxChunkCount;
    if (configuredMax == null) {
      return requestedCount;
    }
    final remaining = configuredMax - _nextChunkIndex;
    if (remaining <= 0) {
      return 0;
    }
    return requestedCount <= remaining ? requestedCount : remaining;
  }

  /// Clears loaded chunks and returns to initial state.
  void reset() {
    _chunks.clear();
    _reloading.clear();
    _requestedSinceEviction.clear();
    _nextChunkIndex = 0;
    _lastRequestedIndex = 0;
    _lastError = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
