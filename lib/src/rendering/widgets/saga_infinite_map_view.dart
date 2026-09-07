import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/domain/models/level_data.dart';
import '../../core/domain/models/level_progress.dart';
import '../../core/domain/models/resolved_saga_layout.dart';
import '../../core/domain/models/saga_geometry.dart';
import '../../core/domain/responsive/saga_map_responsive_config.dart';
import '../../core/domain/responsive/saga_responsive_resolver.dart';
import '../adapters/widget_renderer_adapter.dart';
import '../painters/saga_path_geometry.dart';
import '../background/saga_map_background.dart';
import '../character/saga_character.dart';
import '../decoration/saga_map_decoration.dart';
import '../character/saga_character_controller.dart';
import '../character/saga_map_gate.dart';
import '../contracts/saga_map_render_context.dart';
import '../contracts/saga_map_renderer.dart';
import '../contracts/saga_chunk_context.dart';
import '../controllers/saga_infinite_map_controller.dart';
import '../controllers/saga_map_camera_controller.dart';
import '../interaction/saga_node_interaction_handler.dart';
import '../interaction/saga_map_zoom.dart';
import 'saga_map_view_internals.dart';
import '../interaction/saga_node_interaction_policy.dart';
import '../theme/saga_biome_theme_resolver.dart';
import 'map_chunk_widget.dart';

/// Node builder signature used by [SagaInfiniteMapView].
typedef SagaInfiniteNodeBuilder = Widget Function(
  BuildContext context,
  LevelData level,
  ResolvedSagaLayout layout,
);

@Deprecated(
    'Use SagaEpisodeHeaderBuilder with SagaChunkContext. Removed in 3.0.0.')
typedef SagaLegacyEpisodeHeaderBuilder = Widget? Function(
  BuildContext context,
  int chunkIndex,
);

/// Builds an episode banner or divider before a chunk in the scroll direction.
/// Return `null` to leave the chunk bare.
typedef SagaEpisodeHeaderBuilder = Widget? Function(
  BuildContext context,
  SagaChunkContext chunk,
);

/// Scroll physics that scale drag distance by a responsive sensitivity factor.
///
/// A factor of `1.0` is ordinary platform behaviour; the wrapper is skipped
/// entirely in that case so the platform's own physics stay untouched.
class SagaMapScrollPhysics extends ScrollPhysics {
  final double sensitivity;

  const SagaMapScrollPhysics({required this.sensitivity, super.parent});

  @override
  SagaMapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SagaMapScrollPhysics(
      sensitivity: sensitivity,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * sensitivity);
  }
}

/// Infinite-scrolling map powered by [SagaInfiniteMapController].
///
/// Scroll direction is derived from [SagaMapResponsiveConfig.pathAxis], not
/// configured separately — the map scrolls in the direction its path travels,
/// and the two cannot fall out of sync.
class SagaInfiniteMapView extends StatefulWidget {
  final SagaInfiniteMapController controller;

  /// Chunk size in pixels along the path axis (the scroll direction).
  final double chunkExtent;

  /// Normalized span each chunk covers along the path axis.
  ///
  /// Must equal `stepHeight * sectionsPerChunk` for the generating config; see
  /// [SagaMapConfig.spanForLevelCount].
  final double chunkSpanNormalized;

  final SagaBiomeThemeResolver biomeThemeResolver;
  final SagaResponsiveResolver responsiveResolver;
  final SagaInfiniteNodeBuilder nodeBuilder;
  final SagaNodeProgressResolver? progressResolver;

  /// Paints every chunk's path, terrain and biome tint.
  ///
  /// Passed straight to [MapChunkWidget.pathRenderer]; `null` keeps the
  /// built-in look. See that field for what a custom renderer receives.
  final SagaMapRenderer<CustomPainter>? pathRenderer;
  final SagaNodeInteractionHandler interactionHandler;
  final SagaNodeInteractionPolicy interactionPolicy;
  final SagaMapBackgroundConfig backgroundConfig;
  final ValueChanged<LevelData>? onLevelTap;

  /// Convenience shortcut, mirroring [onLevelTap]. Ignored when interactionHandler.onNodeLongPress is set.
  final ValueChanged<LevelData>? onLevelLongPress;

  /// Remaining scroll extent, in pixels, at which the next batch is requested.
  final double loadMoreTriggerPx;

  /// Lateral band the levels were generated within; forwarded to each chunk.
  final SagaLateralBounds lateralBounds;

  /// Inset at each end of every chunk's path axis, as a fraction of
  /// [chunkExtent]. Leave at `0` to keep node spacing uniform across seams.
  final double alongEdgeInsetFraction;

  /// Logical node size before responsive scaling.
  final double baseNodeSize;

  /// Floor on a node's gesture area, independent of its visual size.
  final double minTouchTarget;

  /// Screen-reader label for each node. Override to localise.
  final SagaNodeSemanticsLabelBuilder semanticsLabelBuilder;

  /// Path roundness: `0` draws straight lines between nodes, `1` a fully
  /// rounded spline. Values outside `0..1` are clamped.
  final double pathCurvature;

  /// Enables pinch-to-zoom, within the given bounds. `null` fixes the scale.
  ///
  /// One finger still scrolls: the pinch recognizer stays out of the gesture
  /// arena until a second finger lands.
  final SagaMapZoomConfig? zoomConfig;

  /// Called whenever the user changes the zoom level.
  final ValueChanged<double>? onZoomChanged;

  /// Character standing on the path, if any.
  final SagaCharacter? character;

  /// Keeps the character in view while it travels.
  final bool followCharacter;

  /// Where a followed or targeted position sits in the viewport: `0` the
  /// leading edge, `0.5` the middle, `1` the trailing edge.
  final double followAlignment;

  /// Level to open on, so a returning player resumes where they left off.
  ///
  /// Applied once, after the first layout, loading whatever chunks it needs.
  /// Defaults to the character's position when one is supplied.
  final double? initialPathPosition;

  /// Handle for scrolling the map from outside the widget tree.
  final SagaMapCameraController? cameraController;

  /// Anything that notifies when [progressResolver]'s answers may have moved.
  ///
  /// **When progress is re-resolved.** The view sweeps a chunk's levels
  /// through [progressResolver] when it has no context for that chunk, when
  /// the controller hands it a different level list for one, when the host
  /// rebuilds the view with a new widget instance — and when this listenable
  /// fires. It deliberately does *not* sweep on the view's own rebuilds: a
  /// pinch, a scroll or a character step cannot change what a resolver
  /// returns, and sweeping there cost `levelsPerChunk x visibleChunks`
  /// lookups per frame.
  ///
  /// The widget-instance trigger is the one with a hole in it, and this field
  /// is the patch. A host that stores the view in a field, or puts it under a
  /// `const` subtree, hands Flutter the *same* widget instance on every
  /// rebuild; the framework then skips the update entirely and
  /// `didUpdateWidget` never runs. That host — the one being careful about
  /// rebuilds — would otherwise never see progress refresh at all.
  ///
  /// Pass whatever already changes when progress does: a `ChangeNotifier`
  /// game state, a `ValueNotifier<SagaProgress>`, a `Listenable.merge` of
  /// several.
  ///
  /// ```dart
  /// SagaInfiniteMapView(
  ///   progressResolver: (level) => gameState.progressFor(level.id),
  ///   progressListenable: gameState,   // a ChangeNotifier
  ///   // ...
  /// )
  /// ```
  ///
  /// The view only listens; it never disposes what it is given.
  final Listenable? progressListenable;

  /// How far the player has reached, as a fractional level index; the path is
  /// painted in two styles either side of it. `null` paints it all one way.
  final double? pathProgressPosition;

  /// Scenery for each chunk, drawn below the path and nodes.
  ///
  /// Receives only the chunk index. Prefer [chunkDecorationBuilder], which is
  /// handed a [SagaChunkContext] carrying the chunk's levels, progress and
  /// dominant biome.
  @Deprecated(
      'Use chunkDecorationBuilder with SagaChunkContext. Removed in 3.0.0.')
  final SagaMapLegacyDecorationBuilder? decorationBuilder;

  /// Scenery for each chunk, drawn below the path and nodes.
  ///
  /// Handed a [SagaChunkContext], so scenery can vary with the chunk's levels,
  /// progress and biome. Supersedes [decorationBuilder].
  final SagaMapDecorationBuilder? chunkDecorationBuilder;

  /// Banner shown before a chunk in the scroll direction — an episode title,
  /// a "World 2" divider. Return `null` for a chunk to leave it bare.
  ///
  /// Receives only the chunk index. Prefer [chunkEpisodeHeaderBuilder].
  @Deprecated(
      'Use chunkEpisodeHeaderBuilder with SagaChunkContext. Removed in 3.0.0.')
  final SagaLegacyEpisodeHeaderBuilder? episodeHeaderBuilder;

  /// Along-axis size of one episode header, in logical pixels.
  ///
  /// Declared rather than measured, the same way [chunkExtent] is: a header is
  /// a host widget and the view cannot know its size before laying it out, but
  /// every scroll target has to be computed before then. Each list item is
  /// `header + chunk`, so a header the view does not know about shifts chunk
  /// `c` by `c` headers — `scrollToPathPosition`, the opening scroll and the
  /// camera all land short by a growing margin.
  ///
  /// Leave it at `0` when you build no headers. Set it to the header's height
  /// on a vertical map, its width on a horizontal one.
  final double episodeHeaderExtent;

  /// Banner shown before a chunk, handed a [SagaChunkContext] so it can report
  /// on the chunk it announces. Supersedes [episodeHeaderBuilder].
  final SagaEpisodeHeaderBuilder? chunkEpisodeHeaderBuilder;

  /// A layer drawn behind the map that scrolls slower than it, for depth.
  ///
  /// Shifted by the scroll offset times [parallaxFactor]; `0` pins it, `1`
  /// moves it with the map. Sits behind everything and never takes a pointer.
  final Widget? parallaxBackground;

  /// Fraction of the scroll offset the [parallaxBackground] moves by.
  final double parallaxFactor;

  /// Fires when a chunk becomes the dominant one on screen. Not called again while it stays dominant.
  /// The first entrance is reported to the host; the package only emits the event.
  final void Function(SagaChunkContext chunk)? onChunkEnter;

  /// Fires when the character's path position crosses a level.
  ///
  /// Fast scrolls may skip intermediate chunks or levels; this only emits the
  /// latest reached level.
  ///
  /// **Best-effort, not a ledger.** The event carries the [LevelData] and needs
  /// the level's chunk in memory to find it, so it is dropped for a level whose
  /// chunk has been evicted under `maxRetainedChunks` or has not finished
  /// loading. It is not re-fired when that chunk comes back: the reached-level
  /// mark has already moved past it. Accepted deliberately — the alternative is
  /// holding a queue of pending events and replaying them out of order, which
  /// is worse than a gap for what this is for (a banner, a sound, a hint).
  /// Anything that must not be missed belongs in your own progression code,
  /// where the level id is known without the map's help.
  final ValueChanged<LevelData>? onLevelReached;

  /// Barriers on the path. The view applies [clampTravelThroughGates] itself,
  /// so a closed gate stops the character without the host wiring anything.
  ///
  /// Whether a gate is open stays the host's call — tickets, friends and
  /// purchases are game economy, not map geometry. The package only enforces
  /// the consequence.
  ///
  /// [SagaMapGate.pathPosition] is on the same zero-based scale as
  /// [LevelData.id]: a gate at `14.0` sits on the 15th level a player sees, and
  /// one at `13.5` sits between the 14th and the 15th.
  ///
  /// Empty, the default, is 1.x behaviour: nothing is clamped.
  ///
  /// A gate only stops the walk. To also stop taps and unlocking, pass the same
  /// condition to `SagaNodeInteractionPolicy.isReachable` and
  /// `CompleteLevelUseCase.canUnlock`.
  ///
  /// If the character controller already carries a host-installed
  /// [SagaCharacterController.barrier], that one wins and these gates are not
  /// applied — an explicit barrier is assumed to be deliberate.
  final List<SagaMapGate> gates;

  const SagaInfiniteMapView({
    super.key,
    required this.controller,
    required this.chunkExtent,
    required this.chunkSpanNormalized,
    required this.biomeThemeResolver,
    this.responsiveResolver = const SagaResponsiveResolver(),
    required this.nodeBuilder,
    this.progressResolver,
    this.pathRenderer,
    this.interactionHandler = const SagaNodeInteractionHandler(),
    this.interactionPolicy = const SagaNodeInteractionPolicy(),
    this.backgroundConfig = const SagaMapBackgroundConfig.none(),
    this.onLevelTap,
    this.onLevelLongPress,
    this.loadMoreTriggerPx = 1200,
    this.lateralBounds = SagaLateralBounds.unit,
    this.alongEdgeInsetFraction = 0.0,
    this.baseNodeSize = kSagaDefaultNodeSize,
    this.minTouchTarget = kSagaMinTouchTarget,
    this.semanticsLabelBuilder = defaultSagaNodeSemanticsLabel,
    this.pathCurvature = 0.0,
    this.zoomConfig,
    this.onZoomChanged,
    this.character,
    this.followCharacter = true,
    this.followAlignment = 0.5,
    this.initialPathPosition,
    this.cameraController,
    this.progressListenable,
    this.pathProgressPosition,
    this.decorationBuilder,
    this.chunkDecorationBuilder,
    this.episodeHeaderBuilder,
    this.episodeHeaderExtent = 0,
    this.chunkEpisodeHeaderBuilder,
    this.parallaxBackground,
    this.parallaxFactor = 0.4,
    this.onChunkEnter,
    this.onLevelReached,
    this.gates = const <SagaMapGate>[],
  })  : assert(
          decorationBuilder == null || chunkDecorationBuilder == null,
          'Cannot provide both decorationBuilder and chunkDecorationBuilder.',
        ),
        assert(
          episodeHeaderBuilder == null || chunkEpisodeHeaderBuilder == null,
          'Cannot provide both episodeHeaderBuilder and chunkEpisodeHeaderBuilder.',
        );

  /// Scroll direction implied by the configured path axis.
  Axis get scrollAxis {
    switch (responsiveResolver.config.pathAxis) {
      case SagaMapPathAxis.vertical:
        return Axis.vertical;
      case SagaMapPathAxis.horizontal:
        return Axis.horizontal;
    }
  }

  @override
  State<SagaInfiniteMapView> createState() => _SagaInfiniteMapViewState();
}

class _SagaInfiniteMapViewState extends State<SagaInfiniteMapView> {
  final Map<int, SagaChunkContext> _chunkContexts = {};

  /// Bumped whenever progress *may* have changed: a host rebuild, or new
  /// chunks arriving. Not bumped by the view's own `setState` calls — a pinch,
  /// a scroll, a character step — because none of those can change what a
  /// progress resolver returns.
  ///
  /// The sweep that resolves every visible level's progress used to sit
  /// unconditionally in `itemBuilder`, so a host whose resolver does real work
  /// paid `levelsPerChunk x visibleChunks` lookups on every frame of a zoom
  /// gesture purely to conclude that nothing had changed.
  int _progressEpoch = 0;

  /// Epoch each cached chunk context was swept at.
  final Map<int, int> _contextEpochs = {};

  /// The exact level list each cached context was swept from. Compared by
  /// identity: the controller hands out the same list until a chunk is
  /// reloaded, and a reload is the one thing that can bring levels whose
  /// progress has never been read.
  final Map<int, List<LevelData>> _contextLevels = {};
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<void>? _kickStart;

  /// Stable identity for the character across chunk hand-offs, so a running
  /// animation is not restarted when it crosses a seam.
  final GlobalKey _characterKey = GlobalKey();

  /// Applies [SagaInfiniteMapView.gates] to a requested move.
  ///
  /// Kept as an object rather than a closure so the gate list can be swapped
  /// without changing the function's identity, which is what lets
  /// [_syncGateBarrier] tell the view's barrier from a host's.
  final _SagaGateBarrier _gateBarrier = _SagaGateBarrier();

  /// A single stable tear-off of [_gateBarrier]; a fresh `.clamp` each time
  /// would defeat the identity checks.
  late final double Function(double, double) _gateBarrierFn =
      _gateBarrier.clamp;

  /// Mirrors the character controller's moving flag. Held separately so the
  /// view rebuilds when travel starts and stops, not on every frame of it.
  bool _characterMoving = false;
  bool _openingScrollDone = false;
  bool _openingScrollRunning = false;
  double _parallaxOffset = 0;

  late final SagaChunkEventTracker _events = SagaChunkEventTracker(
    contextFor: (index) {
      final cached = _chunkContexts[index];
      if (cached != null && cached.levels.isNotEmpty) return cached;
      final levels = widget.controller.chunkLevels(index);
      return levels.isEmpty ? null : _buildChunkContext(index, levels);
    },
    levelsFor: (index) => widget.controller.chunkLevels(index),
  );

  late final SagaZoomGestureController _zoomGesture =
      SagaZoomGestureController(initialZoom: widget.zoomConfig?.initial ?? 1.0);

  double get _zoom => _zoomGesture.zoom;
  double get _lateralPan => _zoomGesture.lateralPan;

  bool get _isVertical => widget.scrollAxis == Axis.vertical;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    widget.controller.addListener(_onControllerChanged);
    _attachCharacter(null, widget.character?.controller);
    _syncGateBarrier(null, widget.character?.controller);
    widget.cameraController?.attach(
      onScroll: _scrollToPathPosition,
      characterPosition: _currentCharacterPosition,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpeningScroll());
    _kickStart =
        Stream<void>.fromFuture(widget.controller.initialize()).listen((_) {});
    widget.progressListenable?.addListener(_onProgressListenable);
  }

  /// The host says progress moved. Bump the epoch so the next build sweeps,
  /// and rebuild — this is the only trigger available to a host whose widget
  /// instance never changes, so it has to do both.
  void _onProgressListenable() {
    if (!mounted) return;
    setState(() => _progressEpoch++);
  }

  @override
  void didUpdateWidget(covariant SagaInfiniteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new widget is the host telling us something changed, and the host is
    // the only thing that can change what `progressResolver` answers.
    _progressEpoch++;
    if (widget.zoomConfig != oldWidget.zoomConfig) {
      _zoomGesture.applyConfig(widget.zoomConfig);
    }
    _attachCharacter(
      oldWidget.character?.controller,
      widget.character?.controller,
    );
    _syncGateBarrier(
      oldWidget.character?.controller,
      widget.character?.controller,
    );
    if (oldWidget.cameraController != widget.cameraController) {
      // A swapped camera controller was never attached, so every
      // `scrollToPathPosition` on it silently did nothing — the failure mode of
      // a handle that reports success by returning.
      oldWidget.cameraController?.detach(_scrollToPathPosition);
      widget.cameraController?.attach(
        onScroll: _scrollToPathPosition,
        characterPosition: _currentCharacterPosition,
      );
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      // A new controller is a new world: a different seed, different levels at
      // the same indices. The context cache is keyed by chunk index alone, so
      // keeping it would render the previous world's levels under the new
      // controller until every chunk happened to be rebuilt.
      _chunkContexts.clear();
      _contextEpochs.clear();
      _contextLevels.clear();
      _kickStart?.cancel();
      _kickStart = Stream<void>.fromFuture(widget.controller.initialize())
          .listen((_) {});
    }
    if (oldWidget.progressListenable != widget.progressListenable) {
      oldWidget.progressListenable?.removeListener(_onProgressListenable);
      widget.progressListenable?.addListener(_onProgressListenable);
    }
    if (oldWidget.pathProgressPosition != widget.pathProgressPosition) {
      _checkLevelReached();
    }
  }

  void _attachCharacter(
    SagaCharacterController? previous,
    SagaCharacterController? next,
  ) {
    if (identical(previous, next)) return;
    previous?.removeListener(_onCharacterChanged);
    next?.addListener(_onCharacterChanged);
    _characterMoving = next?.isMoving ?? false;
    _checkLevelReached();
  }

  /// Keeps [SagaInfiniteMapView.gates] wired to the character controller.
  ///
  /// Called on every rebuild rather than only on controller swaps, because the
  /// gate list changes far more often than the controller does — opening a
  /// gate is a normal game event.
  ///
  /// A barrier the host installed itself is left alone in both directions: the
  /// view only ever installs and removes its own.
  void _syncGateBarrier(
    SagaCharacterController? previous,
    SagaCharacterController? next,
  ) {
    _gateBarrier.gates = widget.gates;

    if (previous != null &&
        !identical(previous, next) &&
        identical(previous.barrier, _gateBarrierFn)) {
      previous.barrier = null;
    }

    if (next == null) return;
    if (widget.gates.isEmpty) {
      // Emptying the list has to lift the clamp, not freeze the last one.
      if (identical(next.barrier, _gateBarrierFn)) next.barrier = null;
      return;
    }
    if (next.barrier == null || identical(next.barrier, _gateBarrierFn)) {
      next.barrier = _gateBarrierFn;
    }
  }

  void _onCharacterChanged() {
    _checkLevelReached();
    final moving = widget.character?.controller?.isMoving ?? false;
    if (moving && widget.followCharacter) {
      _followCharacter();
    }
    // Only the start and end of a journey change how the view behaves; the
    // frames between are the character layer's business.
    if (moving != _characterMoving && mounted) {
      setState(() => _characterMoving = moving);
    }
  }

  /// Along-axis pixel where [pathPosition] sits, across the whole map.
  ///
  /// Chunk `c` occupies `[c * extent, (c+1) * extent]` and holds `n` levels, so
  /// level `L` lands at `extent * L / n`. Exact on a node; between nodes it is
  /// a linear read of a curve that may bow slightly, which no camera can show.
  double? _alongPixelFor(double pathPosition) {
    if (!_scrollController.hasClients) return null;
    final sections = widget.controller.sectionsPerChunk;
    if (sections <= 0) return null;
    final layout = widget.responsiveResolver.resolveForWidth(
      MediaQuery.sizeOf(context).width,
    );
    // Rounded *after* the zoom, matching MapChunkWidget, which folds the user
    // zoom into `nodeSpacing` before rounding the extent. Rounding first and
    // scaling after put the camera's idea of a chunk boundary a fraction of a
    // pixel from the layout's, and the two drifted a little further apart with
    // every chunk.
    final extent =
        (widget.chunkExtent * layout.nodeSpacing * _zoom).roundToDouble();
    // Each list item is `header + chunk`, so chunk `c` starts `c` headers
    // further along than its chunk extent alone implies. Without this every
    // camera target drifts by one header per chunk — a mile deep into the map,
    // "scroll to level 250" lands somewhere else entirely.
    final headers = widget.episodeHeaderExtent * (pathPosition / sections);
    return extent * pathPosition / sections + headers;
  }

  double _currentCharacterPosition() =>
      widget.character?.effectivePathPosition ?? 0;

  /// Builds the context for one chunk, resolving each level's progress so a
  /// listener sees the same `progress` map the builders do.
  SagaChunkContext _buildChunkContext(int index, List<LevelData> levels) {
    final progress = <int, LevelProgress>{};
    if (widget.progressResolver != null) {
      for (final level in levels) {
        final resolved = widget.progressResolver!(level);
        if (resolved != null) progress[level.id] = resolved;
      }
    }
    return SagaChunkContext(
      chunkIndex: index,
      levels: levels,
      progress: progress,
    );
  }

  void _checkDominantChunk() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final layout = widget.responsiveResolver.resolveForWidth(
      MediaQuery.sizeOf(context).width,
    );

    _events.checkDominantChunk(
      centerOffset: position.pixels + (position.viewportDimension / 2.0),
      chunkExtent:
          (widget.chunkExtent * layout.nodeSpacing * _zoom).roundToDouble(),
      onChunkEnter: widget.onChunkEnter,
    );
  }

  void _checkLevelReached() {
    if (!mounted) return;
    _events.checkLevelReached(
      pathPosition: widget.character?.effectivePathPosition ??
          widget.pathProgressPosition,
      sectionsPerChunk: widget.controller.sectionsPerChunk,
      onLevelReached: widget.onLevelReached,
    );
  }

  /// Loads chunks until [chunkIndex] exists, or the map says it has ended.
  Future<void> _ensureChunkLoaded(int chunkIndex) async {
    var guard = 0;
    while (widget.controller.loadedChunkCount <= chunkIndex &&
        !widget.controller.hasReachedEnd &&
        guard++ < 200) {
      final before = widget.controller.loadedChunkCount;
      await widget.controller.loadMore();
      // A loader that stops producing would otherwise spin here forever.
      if (widget.controller.loadedChunkCount == before) break;
    }
  }

  Future<void> _scrollToPathPosition(
    double pathPosition, {
    required double alignment,
    required Duration duration,
    required Curve curve,
  }) async {
    final sections = widget.controller.sectionsPerChunk;
    if (sections > 0) {
      final before = widget.controller.loadedChunkCount;
      await _ensureChunkLoaded(pathPosition.floor() ~/ sections);
      if (!mounted) return;
      if (widget.controller.loadedChunkCount != before) {
        // Newly loaded chunks are not in the scroll extent until they have been
        // laid out; measuring now would clamp against a stale maximum.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
    }
    if (!_scrollController.hasClients) return;

    final target = _offsetFor(pathPosition, alignment);
    if (target == null) return;
    if (duration == Duration.zero) {
      _scrollController.jumpTo(target);
      return;
    }
    await _scrollController.animateTo(
      target,
      duration: duration,
      curve: curve,
    );
  }

  /// Scroll offset that puts [pathPosition] at [alignment] in the viewport.
  double? _offsetFor(double pathPosition, double alignment) {
    final along = _alongPixelFor(pathPosition);
    if (along == null) return null;
    final position = _scrollController.position;
    final raw = along - position.viewportDimension * alignment;
    return raw.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  Future<void> _applyOpeningScroll() async {
    if (_openingScrollDone || _openingScrollRunning || !mounted) return;

    final target =
        widget.initialPathPosition ?? widget.character?.effectivePathPosition;
    if (target == null || target == 0) {
      _openingScrollDone = true;
      return;
    }
    // The first frame usually has no chunks yet, so there is no scrollable to
    // move. Leave the flag down and let the next load try again, rather than
    // marking the job done after silently doing nothing.
    if (!_scrollController.hasClients) return;

    _openingScrollRunning = true;
    try {
      // Jump rather than animate: opening the map should already be at the
      // right place, not travel there while the player watches.
      await _scrollToPathPosition(
        target,
        alignment: widget.followAlignment,
        duration: Duration.zero,
        curve: Curves.linear,
      );
      _openingScrollDone = true;
      if (mounted) _checkDominantChunk();
    } finally {
      _openingScrollRunning = false;
    }
  }

  @override
  void dispose() {
    widget.cameraController?.detach(_scrollToPathPosition);
    final controller = widget.character?.controller;
    controller?.removeListener(_onCharacterChanged);
    // The controller usually outlives the view; leaving a barrier pointing at
    // a disposed view's gate list would clamp a map that no longer has gates.
    if (controller != null && identical(controller.barrier, _gateBarrierFn)) {
      controller.barrier = null;
    }
    _kickStart?.cancel();
    widget.progressListenable?.removeListener(_onProgressListenable);
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _chunkContexts.clear();
    _contextEpochs.clear();
    _contextLevels.clear();
    super.dispose();
  }

  void _onControllerChanged() {
    // Deliberately does *not* bump the epoch. New chunks bring levels whose
    // progress has never been read, but they are new chunks: the builder
    // sweeps any chunk it has no context for, and any whose level list the
    // controller has replaced. Bumping here would re-sweep every chunk already
    // on screen every time one more loaded.
    _pruneEvictedContexts();
    if (mounted) {
      setState(() {});
    }
    if (!_openingScrollDone) {
      // Chunks have just arrived; the opening scroll may now be possible.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyOpeningScroll());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkDominantChunk();
      });
    }
  }

  /// Drops the view's own per-chunk cache for chunks the controller evicted.
  ///
  /// The controller bounds `_chunks` by `maxRetainedChunks`, but this view kept
  /// a second, unbounded cache (`_chunkContexts`) that nothing ever removed.
  /// Pruning it in step with the controller makes `maxRetainedChunks` bound
  /// total memory, not just the controller's half.
  ///
  /// **A chunk being reloaded is kept.** `itemBuilder` falls back to a cached
  /// context's levels when the controller has none — that fallback is what
  /// draws an evicted-but-still-visible chunk from stale-but-correct data for
  /// the frame or two its reload takes. Pruning on `retainedChunkIndices`
  /// alone deleted the very context that fallback reads, so the chunk was
  /// drawn *empty* instead: a blank band sliding past under the player's
  /// thumb. The bound is not weakened by this — `reloadingChunkIndices` holds
  /// only chunks that were asked for, so it is bounded by what is on screen,
  /// and each entry leaves it as soon as its reload lands.
  void _pruneEvictedContexts() {
    if (_chunkContexts.isEmpty) return;
    final retained = widget.controller.retainedChunkIndices;
    final reloading = widget.controller.reloadingChunkIndices;
    bool drop(int index) =>
        !retained.contains(index) && !reloading.contains(index);
    _chunkContexts.removeWhere((index, _) => drop(index));
    _contextEpochs.removeWhere((index, _) => drop(index));
    _contextLevels.removeWhere((index, _) => drop(index));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _checkDominantChunk();
    if (widget.parallaxBackground != null) {
      final next = _scrollController.offset * widget.parallaxFactor;
      if (next != _parallaxOffset && mounted) {
        setState(() => _parallaxOffset = next);
      }
    }
    final extentAfter = _scrollController.position.extentAfter;
    if (extentAfter <= widget.loadMoreTriggerPx) {
      unawaited(widget.controller.loadMore());
    }
  }

  /// Keeps the travelling character at [SagaInfiniteMapView.followAlignment].
  ///
  /// Jumps rather than animates: scrolling is locked during a journey, so the
  /// offset is driven straight from the character's own eased motion. Animating
  /// on top would add a second easing and lag behind.
  void _followCharacter() {
    if (!_scrollController.hasClients) return;
    final target = _offsetFor(
      _currentCharacterPosition(),
      widget.followAlignment,
    );
    if (target == null) return;
    if ((target - _scrollController.offset).abs() < 0.5) return;
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.controller.loadedChunkCount;
    if (count == 0 && widget.controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (count == 0 && widget.controller.lastError != null) {
      return Center(child: Text(_loadErrorText('Failed to load chunks')));
    }

    final layout = widget.responsiveResolver.resolveForWidth(
      MediaQuery.sizeOf(context).width,
    );

    final list = ListView.builder(
      controller: _scrollController,
      scrollDirection: widget.scrollAxis,
      // Scrolling is locked while the character travels, so the map cannot be
      // dragged out from under a journey the camera is following.
      physics: _characterMoving
          ? const NeverScrollableScrollPhysics()
          : (layout.scrollSensitivity == 1.0
              ? null
              : SagaMapScrollPhysics(sensitivity: layout.scrollSensitivity)),
      itemCount: count + 1,
      itemBuilder: (context, index) {
        if (index == count) {
          return _buildTrailer();
        }
        var levels = widget.controller.chunkLevels(index);
        var cached = _chunkContexts[index];
        if (levels.isEmpty && cached != null) {
          levels = cached.levels;
        }

        // Skip the sweep entirely when nothing since the last one could have
        // changed the answer. This is the whole optimisation: a pinch rebuilds
        // every visible chunk many times a second, and none of those rebuilds
        // can move a level's progress.
        final swept = _contextEpochs[index] == _progressEpoch &&
            identical(_contextLevels[index], levels);
        if (cached == null || !swept) {
          Map<int, LevelProgress> progress = {};
          if (widget.progressResolver != null && levels.isNotEmpty) {
            for (final l in levels) {
              final p = widget.progressResolver!(l);
              if (p != null) progress[l.id] = p;
            }
          }
          bool progressChanged = false;
          if (cached != null) {
            if (cached.progress.length != progress.length) {
              progressChanged = true;
            } else {
              for (final k in progress.keys) {
                if (cached.progress[k] != progress[k]) {
                  progressChanged = true;
                  break;
                }
              }
            }
          }
          // T-18 made the refresh conditional on `progressChanged` alone, so a
          // chunk whose levels were replaced while its progress stayed
          // identical kept a context carrying the *previous* list — and the
          // host's decoration builder read the previous world's `LevelData`
          // while the widget beside it drew the new one. Identity, not
          // equality: a fresh-list-per-frame host is exactly what T-18 was
          // protecting, and this is the same comparison the `swept` check
          // above already makes. It reads `_contextLevels`, the raw list the
          // last sweep ran on, not `cached.levels` — the context copies its
          // list into an unmodifiable view, so comparing against that would be
          // true on every pass and rebuild the context every time.
          final levelsReplaced =
              cached != null && !identical(_contextLevels[index], levels);
          if (cached == null || progressChanged || levelsReplaced) {
            cached = SagaChunkContext(
              chunkIndex: index,
              levels: levels,
              progress: progress,
            );
          }
          if (levels.isNotEmpty) {
            _chunkContexts[index] = cached;
            _contextEpochs[index] = _progressEpoch;
            _contextLevels[index] = levels;
          }
        }

        final chunk = MapChunkWidget(
          chunkContext: cached,
          levels: levels,
          chunkIndex: index,
          chunkExtent: widget.chunkExtent,
          chunkSpanNormalized: widget.chunkSpanNormalized,
          biomeThemeResolver: widget.biomeThemeResolver,
          responsiveResolver: widget.responsiveResolver,
          nodeBuilder: widget.nodeBuilder,
          progressResolver: widget.progressResolver,
          pathRenderer: widget.pathRenderer,
          onLevelTap: widget.onLevelTap,
          onLevelLongPress: widget.onLevelLongPress,
          interactionHandler: widget.interactionHandler,
          interactionPolicy: widget.interactionPolicy,
          backgroundConfig: widget.backgroundConfig,
          lateralBounds: widget.lateralBounds,
          alongEdgeInsetFraction: widget.alongEdgeInsetFraction,
          leadingNeighbors: _levelsBefore(index),
          trailingNeighbors: _levelsAfter(index),
          pathCurvature: widget.pathCurvature,
          pathProgressPosition: widget.pathProgressPosition,
          chunkDecorationBuilder: widget.chunkDecorationBuilder,
          // ignore: deprecated_member_use_from_same_package
          decorationBuilder: widget.decorationBuilder,
          baseNodeSize: widget.baseNodeSize,
          minTouchTarget: widget.minTouchTarget,
          semanticsLabelBuilder: widget.semanticsLabelBuilder,
          userZoom: _zoom,
          lateralPanOffset: _lateralPan,
          character: widget.character,
          characterKey: _characterKey,
        );

        Widget? header;
        if (widget.chunkEpisodeHeaderBuilder != null) {
          header = widget.chunkEpisodeHeaderBuilder!(context, cached);
          // ignore: deprecated_member_use_from_same_package
        } else if (widget.episodeHeaderBuilder != null) {
          // ignore: deprecated_member_use_from_same_package
          header = widget.episodeHeaderBuilder!(context, index);
        }
        if (header == null) return chunk;
        // The header precedes the chunk in the scroll direction, so it reads
        // as a divider entering a new episode.
        return widget.scrollAxis == Axis.vertical
            ? Column(mainAxisSize: MainAxisSize.min, children: [header, chunk])
            : Row(mainAxisSize: MainAxisSize.min, children: [header, chunk]);
      },
    );

    // Pinch is disabled mid-journey for the same reason as scrolling: it would
    // fight the camera.
    final Widget gestureWrapped;
    if (widget.zoomConfig == null || _characterMoving) {
      gestureWrapped = list;
    } else {
      gestureWrapped = RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          SagaPinchGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<SagaPinchGestureRecognizer>(
            () => SagaPinchGestureRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onStart = _onPinchStart
              ..onUpdate = _onPinchUpdate,
          ),
        },
        child: list,
      );
    }

    final parallax = widget.parallaxBackground;
    if (parallax == null) return gestureWrapped;

    final shift = widget.scrollAxis == Axis.vertical
        ? Offset(0, -_parallaxOffset)
        : Offset(-_parallaxOffset, 0);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Transform.translate(
              key: const ValueKey('saga-parallax'),
              offset: shift,
              child: parallax,
            ),
          ),
        ),
        gestureWrapped,
      ],
    );
  }

  void _onPinchStart(ScaleStartDetails details) {
    _zoomGesture.start(
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
      focalPoint: details.localFocalPoint,
    );
  }

  void _onPinchUpdate(ScaleUpdateDetails details) {
    final update = _zoomGesture.update(
      config: widget.zoomConfig,
      details: details,
      isVertical: _isVertical,
    );
    if (update == null) return;

    // The controller already holds the new zoom and pan; this only tells the
    // element tree to read them again.
    setState(() {});

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      _scrollController.jumpTo(
        update.targetScrollOffset.clamp(
          position.minScrollExtent,
          // maxScrollExtent lags a frame behind the resize; clamping to the
          // stale value would fight the zoom, so allow the larger of the two.
          math.max(position.maxScrollExtent, update.targetScrollOffset),
        ),
      );
    }

    widget.onZoomChanged?.call(update.zoom);
  }

  /// The [kSagaPathNeighborCount] levels preceding [chunkIndex], in path order.
  ///
  /// An unloaded neighbour simply leaves the seam unbridged until it arrives;
  /// the controller notifies on load, which rebuilds this chunk with the
  /// neighbour in place.
  List<LevelData> _levelsBefore(int chunkIndex) {
    if (chunkIndex <= 0) return const <LevelData>[];
    final previous = widget.controller.chunkLevels(chunkIndex - 1);
    if (previous.isEmpty) return const <LevelData>[];
    final take = previous.length < kSagaPathNeighborCount
        ? previous.length
        : kSagaPathNeighborCount;
    return previous.sublist(previous.length - take);
  }

  /// The [kSagaPathNeighborCount] levels following [chunkIndex], in path order.
  List<LevelData> _levelsAfter(int chunkIndex) {
    final next = widget.controller.chunkLevels(chunkIndex + 1);
    if (next.isEmpty) return const <LevelData>[];
    final take = next.length < kSagaPathNeighborCount
        ? next.length
        : kSagaPathNeighborCount;
    return next.sublist(0, take);
  }

  /// A loader failure rendered for a player rather than for a log.
  ///
  /// Host exception text was previously interpolated raw and unbounded. Two
  /// problems with that: a long message pushed the map off the screen, and a
  /// `toString()` on a host's exception can carry a URL, a token or a file path
  /// that has no business being on a player's screen in release. In release the
  /// detail is dropped entirely; in debug it is kept, clipped, because that is
  /// where it is useful.
  String _loadErrorText(String prefix) {
    if (kReleaseMode) return prefix;
    final detail = widget.controller.lastError.toString();
    const limit = 200;
    return detail.length <= limit
        ? '$prefix: $detail'
        : '$prefix: ${detail.substring(0, limit)}...';
  }

  Widget _buildTrailer() {
    final Widget child;
    if (widget.controller.lastError != null) {
      child = Text(_loadErrorText('Chunk load error'));
    } else if (widget.controller.hasReachedEnd) {
      child = const Text('Reached configured chunk limit.');
    } else if (widget.controller.isLoading) {
      child = const CircularProgressIndicator();
    } else {
      child = const SizedBox.shrink();
    }

    final trailer = Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: child),
    );

    // A horizontal list gives children unbounded width; give the trailer a
    // finite one so it does not overflow.
    return widget.scrollAxis == Axis.horizontal
        ? SizedBox(width: 160, child: trailer)
        : trailer;
  }
}

/// The view's own gate barrier.
///
/// Pulled out of the widget so gate handling is one small, named thing rather
/// than another branch inside a 650-line `build`, and so its identity is stable
/// while [gates] changes underneath it.
class _SagaGateBarrier {
  List<SagaMapGate> gates = const <SagaMapGate>[];

  /// How far a move from [from] towards [to] may actually get.
  double clamp(double from, double to) =>
      clampTravelThroughGates(gates, from, to);
}
