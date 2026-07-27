import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/domain/models/level_data.dart';
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
import '../contracts/saga_map_render_context.dart';
import '../controllers/saga_infinite_map_controller.dart';
import '../controllers/saga_map_camera_controller.dart';
import '../interaction/saga_node_interaction_handler.dart';
import '../interaction/saga_map_zoom.dart';
import '../interaction/saga_node_interaction_policy.dart';
import '../theme/saga_biome_theme_resolver.dart';
import 'map_chunk_widget.dart';

/// Node builder signature used by [SagaInfiniteMapView].
typedef SagaInfiniteNodeBuilder = Widget Function(
  BuildContext context,
  LevelData level,
  ResolvedSagaLayout layout,
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
  final SagaNodeInteractionHandler interactionHandler;
  final SagaNodeInteractionPolicy interactionPolicy;
  final SagaMapBackgroundConfig backgroundConfig;
  final ValueChanged<LevelData>? onLevelTap;

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

  /// How far the player has reached, as a fractional level index; the path is
  /// painted in two styles either side of it. `null` paints it all one way.
  final double? pathProgressPosition;

  /// Scenery for each chunk, drawn below the path and nodes.
  final SagaMapDecorationBuilder? decorationBuilder;

  /// Banner shown before a chunk in the scroll direction — an episode title,
  /// a "World 2" divider. Return `null` for a chunk to leave it bare.
  final Widget? Function(BuildContext context, int chunkIndex)?
      episodeHeaderBuilder;

  /// A layer drawn behind the map that scrolls slower than it, for depth.
  ///
  /// Shifted by the scroll offset times [parallaxFactor]; `0` pins it, `1`
  /// moves it with the map. Sits behind everything and never takes a pointer.
  final Widget? parallaxBackground;

  /// Fraction of the scroll offset the [parallaxBackground] moves by.
  final double parallaxFactor;

  const SagaInfiniteMapView({
    super.key,
    required this.controller,
    required this.chunkExtent,
    required this.chunkSpanNormalized,
    required this.biomeThemeResolver,
    this.responsiveResolver = const SagaResponsiveResolver(),
    required this.nodeBuilder,
    this.progressResolver,
    this.interactionHandler = const SagaNodeInteractionHandler(),
    this.interactionPolicy = const SagaNodeInteractionPolicy(),
    this.backgroundConfig = const SagaMapBackgroundConfig.none(),
    this.onLevelTap,
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
    this.pathProgressPosition,
    this.decorationBuilder,
    this.episodeHeaderBuilder,
    this.parallaxBackground,
    this.parallaxFactor = 0.4,
  });

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
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<void>? _kickStart;

  /// Stable identity for the character across chunk hand-offs, so a running
  /// animation is not restarted when it crosses a seam.
  final GlobalKey _characterKey = GlobalKey();

  /// Mirrors the character controller's moving flag. Held separately so the
  /// view rebuilds when travel starts and stops, not on every frame of it.
  bool _characterMoving = false;
  bool _openingScrollDone = false;
  bool _openingScrollRunning = false;
  double _parallaxOffset = 0;

  late double _zoom = widget.zoomConfig?.initial ?? 1.0;
  double _lateralPan = 0;

  // Captured when a pinch begins, so every update is measured against the
  // gesture's origin rather than accumulating rounding from frame to frame.
  double _zoomAtGestureStart = 1;
  double _panAtGestureStart = 0;
  double _scrollAtGestureStart = 0;
  Offset _focalAtGestureStart = Offset.zero;

  bool get _isVertical => widget.scrollAxis == Axis.vertical;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    widget.controller.addListener(_onControllerChanged);
    _attachCharacter(null, widget.character?.controller);
    widget.cameraController?.attach(
      onScroll: _scrollToPathPosition,
      characterPosition: _currentCharacterPosition,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpeningScroll());
    _kickStart =
        Stream<void>.fromFuture(widget.controller.initialize()).listen((_) {});
  }

  @override
  void didUpdateWidget(covariant SagaInfiniteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final config = widget.zoomConfig;
    if (config != oldWidget.zoomConfig) {
      final next = config == null ? 1.0 : config.clamp(_zoom);
      if (next != _zoom) {
        _zoom = next;
        _lateralPan = 0;
      }
    }
    _attachCharacter(
      oldWidget.character?.controller,
      widget.character?.controller,
    );
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _kickStart?.cancel();
      _kickStart = Stream<void>.fromFuture(widget.controller.initialize())
          .listen((_) {});
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
  }

  void _onCharacterChanged() {
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
    final extent =
        (widget.chunkExtent * layout.nodeSpacing).roundToDouble() * _zoom;
    return extent * pathPosition / sections;
  }

  double _currentCharacterPosition() =>
      widget.character?.effectivePathPosition ?? 0;

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
    } finally {
      _openingScrollRunning = false;
    }
  }

  @override
  void dispose() {
    widget.cameraController?.detach(_scrollToPathPosition);
    widget.character?.controller?.removeListener(_onCharacterChanged);
    _kickStart?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
    if (!_openingScrollDone) {
      // Chunks have just arrived; the opening scroll may now be possible.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyOpeningScroll());
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
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
      return Center(
        child: Text('Failed to load chunks: ${widget.controller.lastError}'),
      );
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
        // The chunk sizes its own path axis and fills the lateral axis from the
        // constraints the list hands it. No MediaQuery override, so responsive
        // resolution still sees the real device.
        final chunk = MapChunkWidget(
          levels: widget.controller.chunkLevels(index),
          chunkIndex: index,
          chunkExtent: widget.chunkExtent,
          chunkSpanNormalized: widget.chunkSpanNormalized,
          biomeThemeResolver: widget.biomeThemeResolver,
          responsiveResolver: widget.responsiveResolver,
          nodeBuilder: widget.nodeBuilder,
          progressResolver: widget.progressResolver,
          onLevelTap: widget.onLevelTap,
          interactionHandler: widget.interactionHandler,
          interactionPolicy: widget.interactionPolicy,
          backgroundConfig: widget.backgroundConfig,
          lateralBounds: widget.lateralBounds,
          alongEdgeInsetFraction: widget.alongEdgeInsetFraction,
          leadingNeighbors: _levelsBefore(index),
          trailingNeighbors: _levelsAfter(index),
          pathCurvature: widget.pathCurvature,
          pathProgressPosition: widget.pathProgressPosition,
          decorationBuilder: widget.decorationBuilder,
          baseNodeSize: widget.baseNodeSize,
          minTouchTarget: widget.minTouchTarget,
          semanticsLabelBuilder: widget.semanticsLabelBuilder,
          userZoom: _zoom,
          lateralPanOffset: _lateralPan,
          character: widget.character,
          characterKey: _characterKey,
        );

        final header = widget.episodeHeaderBuilder?.call(context, index);
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
    _zoomAtGestureStart = _zoom;
    _panAtGestureStart = _lateralPan;
    _scrollAtGestureStart =
        _scrollController.hasClients ? _scrollController.offset : 0;
    _focalAtGestureStart = details.localFocalPoint;
  }

  void _onPinchUpdate(ScaleUpdateDetails details) {
    final config = widget.zoomConfig;
    if (config == null || details.pointerCount < 2) return;

    final next = config.clamp(_zoomAtGestureStart * details.scale);
    final ratio = next / _zoomAtGestureStart;

    final focalAlong =
        _isVertical ? _focalAtGestureStart.dy : _focalAtGestureStart.dx;
    final focalLateral =
        _isVertical ? _focalAtGestureStart.dx : _focalAtGestureStart.dy;
    final currentLateral =
        _isVertical ? details.localFocalPoint.dx : details.localFocalPoint.dy;

    // Whatever sat under the fingers stays under them: the content grows about
    // the focal point, so the scroll offset has to grow with it.
    final targetOffset = (_scrollAtGestureStart + focalAlong) * ratio -
        focalAlong;

    final pan = _panAtGestureStart * ratio + (currentLateral - focalLateral);

    setState(() {
      _zoom = next;
      _lateralPan = pan;
    });

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      _scrollController.jumpTo(
        targetOffset.clamp(
          position.minScrollExtent,
          // maxScrollExtent lags a frame behind the resize; clamping to the
          // stale value would fight the zoom, so allow the larger of the two.
          math.max(position.maxScrollExtent, targetOffset),
        ),
      );
    }

    widget.onZoomChanged?.call(next);
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
    final take =
        previous.length < kSagaPathNeighborCount ? previous.length : kSagaPathNeighborCount;
    return previous.sublist(previous.length - take);
  }

  /// The [kSagaPathNeighborCount] levels following [chunkIndex], in path order.
  List<LevelData> _levelsAfter(int chunkIndex) {
    final next = widget.controller.chunkLevels(chunkIndex + 1);
    if (next.isEmpty) return const <LevelData>[];
    final take =
        next.length < kSagaPathNeighborCount ? next.length : kSagaPathNeighborCount;
    return next.sublist(0, take);
  }

  Widget _buildTrailer() {
    final Widget child;
    if (widget.controller.lastError != null) {
      child = Text('Chunk load error: ${widget.controller.lastError}');
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
