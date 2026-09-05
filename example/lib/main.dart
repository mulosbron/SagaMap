// SagaMap — full feature demo.
//
// Everything the package can do lives in this one file, wired to a control
// panel so each feature can be switched on and off while the map runs. Tap a
// level node to walk the character there; completing a level unlocks the next
// one and lights up the path behind you.
//
// Run with:
//   cd example && flutter run

import 'package:flutter/material.dart';
import 'package:saga_map/saga_map.dart';

void main() => runApp(const SagaMapDemoApp());

/// Pixels of path each level occupies along the scroll axis.
///
/// Orientation-independent on purpose: the same value drives chunk width in a
/// horizontal map and chunk height in a vertical one, so node density looks the
/// same either way.
const double _pixelsPerLevel = 96;

/// Levels generated per chunk. This also fixes `chunkSpanNormalized`, which
/// must equal `stepHeight * levelsPerChunk` — see
/// [SagaMapConfig.spanForLevelCount].
const int _levelsPerChunk = 10;

/// The geometry the whole demo generates against.
const SagaMapConfig _mapConfig = SagaMapConfig.defaultConfig;

/// Where the demo's one gate sits. Closed, it holds the character on the near
/// side until the host decides to open it.
const int _gateLevel = 12;

/// The walk cycle bundled with this example: six 48x64 frames side by side,
/// which is the default [SagaSpriteLayout.horizontal].
const SagaSpriteSheet _heroSheet = SagaSpriteSheet(
  frameWidth: 48,
  frameHeight: 64,
  frameCount: 6,
);

/// Which artwork supplies the map background.
enum DemoBackground { none, colour, svg, image, multiSvg }

/// How the character is drawn — the point being that the library does not care.
enum DemoCharacterArt { spriteSheet, flutterWidget }

class SagaMapDemoApp extends StatelessWidget {
  const SagaMapDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SagaMap Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F7D3A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SagaMapDemo(),
    );
  }
}

class SagaMapDemo extends StatefulWidget {
  const SagaMapDemo({super.key});

  @override
  State<SagaMapDemo> createState() => _SagaMapDemoState();
}

class _SagaMapDemoState extends State<SagaMapDemo>
    with TickerProviderStateMixin {
  // --- Library controllers -------------------------------------------------

  /// Feeds chunks of generated levels to the map as it scrolls.
  late SagaInfiniteMapController _map;

  /// Owns the character's position and drives its movement.
  late SagaCharacterController _character;

  /// Lets the demo scroll the map from a button, outside the widget tree.
  final SagaMapCameraController _camera = SagaMapCameraController();

  // --- Game state ----------------------------------------------------------

  /// Progression state: which levels are locked, unlocked or done.
  SagaProgress _progress = SagaProgress.initial();

  /// Boss drops collected so far.
  final List<InventoryItem> _inventory = <InventoryItem>[];

  /// Seed every level position is derived from. Change it for a new map.
  int _seed = 42;

  /// Highest level reached, which is where the path stops looking "walked".
  double _reached = 0;

  String _status = 'Tap a level to walk there';

  /// Which episode (chunk) the viewport is centred on. Driven by [onChunkEnter],
  /// a 1.1.0 listener that fires as the map scrolls into a new chunk.
  int _currentEpisode = 1;

  /// The last level the character physically walked over, reported by
  /// [onLevelReached] (1.1.0) rather than inferred from completion.
  int _lastReachedLevel = 0;

  // --- Feature toggles -----------------------------------------------------

  SagaMapPathAxis _axis = SagaMapPathAxis.vertical;
  DemoBackground _background = DemoBackground.svg;
  DemoCharacterArt _art = DemoCharacterArt.spriteSheet;
  SagaCharacterGait _gait = SagaCharacterGait.walk;

  double _curvature = 0.85;
  double _zoom = 1;

  bool _showWalkedPath = true;
  bool _showScenery = true;
  bool _showEpisodeHeaders = true;
  bool _showParallax = true;
  bool _gateClosed = true;
  bool _pinchZoom = true;
  bool _followCharacter = true;
  bool _denseMobilePolicy = true;
  bool _boundedMemory = false;

  @override
  void initState() {
    super.initState();
    _map = _buildMapController();
    _character = _buildCharacterController();
  }

  @override
  void dispose() {
    _character.dispose();
    _camera.dispose();
    _map.dispose();
    super.dispose();
  }

  // --- Wiring --------------------------------------------------------------

  /// Builds the chunk controller for the current seed.
  ///
  /// The loader is deterministic — level N always lands in the same place for a
  /// given seed — which is what lets chunks be dropped and regenerated freely.
  /// `maxRetainedChunks` bounds memory on a long map by evicting chunks far
  /// from the one being read.
  SagaInfiniteMapController _buildMapController() {
    const generator = SagaMapLevelGenerator();
    return SagaInfiniteMapController(
      sectionsPerChunk: _levelsPerChunk,
      initialChunkCount: 3,
      loadBatchSize: 2,
      maxRetainedChunks: _boundedMemory ? 6 : null,
      chunkLoader: (chunkIndex, sectionsPerChunk) => generator.generateLevels(
        globalSeed: _seed,
        config: _mapConfig,
        startLevelId: chunkIndex * sectionsPerChunk,
        count: sectionsPerChunk,
      ),
    );
  }

  /// Builds the character controller and hooks up the gate.
  ///
  /// `barrier` is how a gate stops travel: the controller asks it how far a
  /// requested move may actually go, and a closed gate shortens the answer to
  /// its near side. Whether the gate is open stays the host's decision.
  SagaCharacterController _buildCharacterController() {
    final controller = SagaCharacterController(
      vsync: this,
      gait: _gait,
      stepDuration: const Duration(milliseconds: 380),
      stepPause: const Duration(milliseconds: 80),
    );
    controller.barrier = (from, to) => clampTravelThroughGates(
          [
            SagaMapGate(
              pathPosition: _gateLevel.toDouble(),
              isOpen: !_gateClosed,
            ),
          ],
          from,
          to,
        );
    return controller;
  }

  /// Rebuilds the map for a new seed, resetting progress with it.
  void _reseed(int seed) {
    setState(() {
      _seed = seed;
      _progress = SagaProgress.initial();
      _inventory.clear();
      _reached = 0;
      _status = 'New map from seed $seed';
      _map.dispose();
      _map = _buildMapController();
    });
    _character.jumpTo(0);
  }

  /// Swaps the gait, which needs a fresh controller since gait is fixed at
  /// construction. The character keeps its place across the swap.
  void _setGait(SagaCharacterGait gait) {
    final at = _character.pathPosition;
    setState(() {
      _gait = gait;
      _character.dispose();
      _character = _buildCharacterController();
    });
    _character.jumpTo(at);
  }

  /// Rebuilds the map controller in place, for toggles that change how chunks
  /// are loaded rather than how they are drawn.
  void _rebuildMap() {
    setState(() {
      _map.dispose();
      _map = _buildMapController();
    });
  }

  // --- Gameplay ------------------------------------------------------------

  /// Walks the character to [level], then completes it.
  ///
  /// If a closed gate sits in between the controller stops there and the level
  /// is not completed — the walk simply ends short.
  Future<void> _goToLevel(LevelData level) async {
    final target = level.id.toDouble();
    setState(() => _status = 'Walking to level ${level.id}…');

    await _character.moveTo(target);
    if (!mounted) return;

    if (_character.pathPosition < target) {
      setState(() => _status = 'A closed gate blocks the way at $_gateLevel');
      return;
    }
    _completeLevel(level.id);
  }

  /// Applies the completion use-case and folds the result back into state.
  ///
  /// The use-case keeps the better of the old and new star counts, unlocks the
  /// next level, and mints a boss reward only on a first clear.
  void _completeLevel(int levelId) {
    const useCase = CompleteLevelUseCase();
    final result = useCase.execute(
      currentProgress: _progress,
      levelId: levelId,
      globalSeed: _seed,
      stars: 1 + (levelId % kMaxLevelStars),
    );

    setState(() {
      _progress = result.nextProgress;
      // The walked path is painted up to here.
      _reached = _reached > levelId ? _reached : levelId.toDouble();
      final reward = result.reward;
      if (reward != null) {
        _inventory.add(reward);
        _status = 'Boss cleared — found ${reward.itemName}!';
      } else {
        _status = 'Level $levelId complete';
      }
    });
  }

  /// Progress lookup the map uses to style each node.
  LevelProgress? _progressFor(LevelData level) => _progress.levels[level.id];

  /// Long-press handler (1.1.0). Shows the boss drop-rate breakdown computed
  /// with the `LootTableOdds` extension, and a bookmark toggle that stores a
  /// host-owned flag in `LevelProgress.extra` — data the library persists
  /// through JSON without knowing what it means.
  void _showLevelInfo(LevelData level) {
    final displayId = level.id + 1;
    final bookmarked =
        (_progressFor(level)?.extra['bookmarked'] as bool?) ?? false;

    // Odds only make sense where a reward actually rolls: boss levels.
    final odds = isBossLevel(level.id) ? kMvpLootTable : const <LootTableEntry>[];

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Level $displayId'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (odds.isEmpty)
              const Text('A normal level — no boss loot rolls here.')
            else ...[
              const Text('Boss drop rates',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final entry in odds)
                Text('• ${entry.itemName}: '
                    '${(odds.probabilityOf(entry) * 100).toStringAsFixed(1)}%'),
              const Divider(),
              for (final MapEntry(:key, :value) in odds.rarityOdds().entries)
                Text('${key.name}: ${(value * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            icon: Icon(
                bookmarked ? Icons.bookmark : Icons.bookmark_border),
            label: Text(bookmarked ? 'Bookmarked' : 'Bookmark'),
            onPressed: () {
              _toggleBookmark(level.id, !bookmarked);
              Navigator.of(dialogContext).pop();
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Writes a host-owned `bookmarked` flag into that level's progress `extra`,
  /// creating a progress entry if the level has none yet.
  void _toggleBookmark(int levelId, bool value) {
    setState(() {
      final levels = Map<int, LevelProgress>.from(_progress.levels);
      final existing = levels[levelId] ??
          LevelProgress(levelId: levelId, state: LevelCompletionState.locked);
      final extra = Map<String, dynamic>.from(existing.extra)
        ..['bookmarked'] = value;
      levels[levelId] = existing.copyWith(extra: extra);
      _progress = _progress.copyWith(levels: levels);
      _status = value
          ? 'Bookmarked level ${levelId + 1}'
          : 'Removed bookmark on level ${levelId + 1}';
    });
  }

  // --- Builders the map calls ----------------------------------------------

  /// Resolves the responsive policy: orientation plus an optional touch-first
  /// density that enlarges nodes and their touch targets on phones.
  SagaResponsiveResolver get _responsiveResolver {
    var config = SagaMapResponsiveConfig.defaults.copyWith(pathAxis: _axis);
    if (_denseMobilePolicy) {
      config = config.copyWith(
        nodeSizePolicy: const SagaMapValuePolicy(
          mobile: 1.35,
          tablet: 1.1,
          desktop: 1.0,
          ultra4k: 0.95,
        ),
        interactionRadiusPolicy: const SagaMapValuePolicy(
          mobile: 1.3,
          tablet: 1.1,
          desktop: 1.0,
          ultra4k: 1.0,
        ),
      );
    }
    return SagaResponsiveResolver(config: config);
  }

  /// Picks the background artwork for the current toggle.
  ///
  /// Multi-asset modes cycle their list across chunks; `overflowBehavior`
  /// decides what happens once the chunks outrun the artwork.
  SagaMapBackgroundConfig get _backgroundConfig {
    final horizontal = _axis == SagaMapPathAxis.horizontal;
    switch (_background) {
      case DemoBackground.none:
        return const SagaMapBackgroundConfig.none();
      case DemoBackground.colour:
        return const SagaMapBackgroundConfig.color(color: Color(0xFF24451F));
      case DemoBackground.svg:
        return SagaMapBackgroundConfig.svgAsset(
          assetPath: horizontal
              ? 'assets/svg/map_horizontal.svg'
              : 'assets/svg/map_vertical.svg',
          fit: BoxFit.cover,
        );
      case DemoBackground.image:
        return SagaMapBackgroundConfig.imageAsset(
          assetPath: horizontal
              ? 'assets/drawable/map_horizontal.png'
              : 'assets/drawable/map_vertical.png',
          fit: BoxFit.cover,
        );
      case DemoBackground.multiSvg:
        return const SagaMapBackgroundConfig.svgAssets(
          assetPaths: [
            'assets/svg/map_vertical.svg',
            'assets/svg/map_horizontal.svg',
          ],
          fit: BoxFit.cover,
          overflowBehavior: SagaMapBackgroundOverflowBehavior.loop,
        );
    }
  }

  /// Draws one level node.
  ///
  /// The builder is handed the resolved layout so it can scale with the map.
  /// Progress decides the colour; boss levels get a different shape and the
  /// current level a white ring.
  Widget _buildNode(
    BuildContext context,
    LevelData level,
    ResolvedSagaLayout layout,
  ) {
    final progress = _progressFor(level);
    final state = progress?.state ?? LevelCompletionState.locked;
    final isCurrent = level.id == _progress.currentMaxUnlockedLevelId;
    final isBoss = isBossLevel(level.id);

    final Color fill;
    final Color border;
    switch (state) {
      case LevelCompletionState.completed:
        fill = const Color(0xFFFFC107);
        border = const Color(0xFF8A6100);
      case LevelCompletionState.unlocked:
        fill = const Color(0xFF7BC96F);
        border = const Color(0xFF33632C);
      case LevelCompletionState.locked:
        fill = const Color(0xFF6B6B6B);
        border = const Color(0xFF3A3A3A);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        shape: isBoss ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isBoss ? BorderRadius.circular(10) : null,
        border: Border.all(
          color: isCurrent ? Colors.white : border,
          width: isCurrent ? 3 : 2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${level.id + 1}',
              style: TextStyle(
                color: state == LevelCompletionState.locked
                    ? Colors.white70
                    : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            if ((progress?.stars ?? 0) > 0)
              Text(
                '★' * progress!.stars,
                style: const TextStyle(color: Colors.black87, fontSize: 8),
              ),
            // A host-owned bookmark flag stored in LevelProgress.extra (1.1.0).
            if ((progress?.extra['bookmarked'] as bool?) ?? false)
              const Icon(Icons.bookmark, color: Color(0xFF1B3A17), size: 10),
          ],
        ),
      ),
    );
  }

  /// Draws the character.
  ///
  /// The library never draws it — it only reports where the character is, which
  /// way it faces and whether it is moving. That is what lets a sprite sheet
  /// and a plain Flutter widget swap freely here, and why Lottie or Rive would
  /// drop into the same place.
  Widget _buildCharacter(BuildContext context, SagaCharacterState state) {
    final walking = state.motion == SagaCharacterMotion.walking;

    if (_art == DemoCharacterArt.spriteSheet) {
      return SagaSpriteAnimation(
        image: const AssetImage('assets/drawable/hero_walk.png'),
        sheet: _heroSheet,
        // Walking plays the whole strip; standing still holds one frame.
        clip: walking
            ? const SagaSpriteClip(count: 6, fps: 10)
            : const SagaSpriteClip(count: 1),
        // The path already accounts for right-to-left, so this is purely
        // "which way is the art facing".
        flipHorizontally: state.facesLeft,
        playing: walking,
      );
    }

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scaleByDouble(state.facesLeft ? -1.0 : 1.0, 1.0, 1.0, 1.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: walking ? Colors.deepOrange : Colors.orangeAccent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.directions_walk, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  /// Scatters scenery over a chunk.
  ///
  /// Decorations are positioned by the library but drawn by the host, and they
  /// sit below the path and nodes — so a tree can overlap a level without ever
  /// stealing the tap that opens it.
  ///
  /// 1.1.0: the builder is handed a [SagaChunkContext] instead of a bare index,
  /// so it can read the chunk's levels and dominant biome. Here the tree colour
  /// follows `chunk.dominantBiomeId`, and `SagaMapDecoration.atLevel` pins a
  /// flag right beside every boss node without any coordinate maths.
  List<SagaMapDecoration> _buildScenery(
    BuildContext context,
    SagaChunkContext chunk,
  ) {
    if (!_showScenery) return const <SagaMapDecoration>[];
    final base = chunk.chunkIndex * _levelsPerChunk;
    final treeColor = _biomeTint(chunk.dominantBiomeId);

    return <SagaMapDecoration>[
      // Trees hugging the path, alternating sides, tinted by the chunk's biome.
      for (var i = 1; i < _levelsPerChunk; i += 3)
        SagaMapDecoration.besidePath(
          pathPosition: (base + i).toDouble(),
          lateralOffset: i.isEven ? 96 : -96,
          size: const Size(40, 46),
          builder: (context) => Icon(Icons.park, color: treeColor, size: 40),
        ),
      // A cloud floating free of the path, placed by chunk fraction.
      SagaMapDecoration.atFraction(
        chunkFraction: Offset(chunk.chunkIndex.isEven ? 0.2 : 0.8, 0.35),
        size: const Size(56, 34),
        builder: (context) =>
            const Icon(Icons.cloud, color: Color(0x55FFFFFF), size: 52),
      ),
      // 1.1.0: a boss flag anchored to the level itself, not to raw pixels.
      for (final level in chunk.levels)
        if (isBossLevel(level.id))
          SagaMapDecoration.atLevel(
            levelId: level.id,
            height: 34,
            offset: const Offset(30, -30),
            builder: (context) =>
                const Icon(Icons.flag, color: Color(0xFFFFC107), size: 30),
          ),
    ];
  }

  /// A rough tint per biome, used to colour scenery from the chunk context.
  Color _biomeTint(String biomeId) {
    switch (biomeId) {
      case kBiomeIdDesert:
        return const Color(0xFFB58A3A);
      case kBiomeIdGlacier:
        return const Color(0xFF6FA8C9);
      case kBiomeIdForest:
      default:
        return const Color(0xFF2F6B2A);
    }
  }

  /// A banner announcing each new episode, shown before its chunk in the
  /// scroll direction.
  ///
  /// 1.1.0: the builder receives a [SagaChunkContext], so the banner can report
  /// how many stars the player has earned across this chunk's levels using the
  /// `SagaProgressStars.starsInRange` helper — no manual loop over levels.
  Widget? _buildEpisodeHeader(BuildContext context, SagaChunkContext chunk) {
    if (!_showEpisodeHeaders) return null;

    final earned = _progress.starsInRange(
      chunk.chunkIndex * _levelsPerChunk,
      _levelsPerChunk,
    );

    final banner = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xCC1B3A17),
        border: Border.all(color: const Color(0xFF7BC96F), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'EPISODE ${chunk.chunkIndex + 1}   ★ $earned',
        style: const TextStyle(
          color: Color(0xFFFFC107),
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );

    return Padding(
      padding: _axis == SagaMapPathAxis.vertical
          ? const EdgeInsets.symmetric(vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 12),
      child: Center(child: banner),
    );
  }

  /// The layer behind the map that scrolls slower than it, for depth.
  Widget? get _parallaxLayer {
    if (!_showParallax) return null;
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12331B), Color(0xFF2C5E3A), Color(0xFF12331B)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMap()),
            _buildStatusBar(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openControls,
        icon: const Icon(Icons.tune),
        label: const Text('Features'),
      ),
    );
  }

  /// The map itself, with every feature wired to the current toggles.
  Widget _buildMap() {
    return SagaInfiniteMapView(
      controller: _map,
      // Sizing is expressed along the path axis, whichever screen axis that is.
      chunkExtent: _levelsPerChunk * _pixelsPerLevel,
      chunkSpanNormalized: _mapConfig.spanForLevelCount(_levelsPerChunk),
      // Centres the generated zig-zag band identically in every chunk.
      lateralBounds: _mapConfig.lateralBounds,
      biomeThemeResolver: const _DemoBiomeTheme(),
      responsiveResolver: _responsiveResolver,
      backgroundConfig: _backgroundConfig,

      // Path shape and progress.
      pathCurvature: _curvature,
      pathProgressPosition: _showWalkedPath ? _reached : null,

      // Scenery, banners, depth. 1.1.0 context-aware builders.
      decorationBuilder: _buildScenery,
      episodeHeaderBuilder: _buildEpisodeHeader,
      parallaxBackground: _parallaxLayer,
      parallaxFactor: 0.35,

      // 1.1.0 listeners: which chunk the viewport entered, and which level the
      // character walked over. Both are debounced by the library, so scrolling
      // back and forth across a seam does not spam these callbacks.
      onChunkEnter: (chunk) =>
          setState(() => _currentEpisode = chunk.chunkIndex + 1),
      onLevelReached: (level) =>
          setState(() => _lastReachedLevel = level.id + 1),

      // 1.1.0: long-press a node for its drop-rate breakdown. Locked nodes are
      // filtered out by the interaction policy's canLongPress.
      onLevelLongPress: _showLevelInfo,

      // The character and the camera that follows it.
      character: SagaCharacter(
        controller: _character,
        size: const Size(44, 58),
        builder: _buildCharacter,
        semanticsLabel: 'Player',
      ),
      followCharacter: _followCharacter,
      cameraController: _camera,
      // Opens where the player left off rather than at level zero.
      initialPathPosition: _reached,

      // Pinch to zoom; one finger still scrolls.
      zoomConfig:
          _pinchZoom ? const SagaMapZoomConfig(min: 0.6, max: 2.4) : null,
      onZoomChanged: (zoom) => setState(() => _zoom = zoom),

      // Interaction.
      progressResolver: _progressFor,
      interactionPolicy: const SagaNodeInteractionPolicy(
        emitTapForLockedNode: false,
        emitTapForCompletedNode: true,
      ),
      onLevelTap: _goToLevel,
      nodeBuilder: _buildNode,
    );
  }

  /// A one-line readout of what the map is currently doing.
  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'seed $_seed · episode $_currentEpisode · '
            'reached L$_lastReachedLevel · '
            '★ ${_progress.totalStars} · '
            'items ${_inventory.length} · '
            'zoom ${_zoom.toStringAsFixed(2)} · '
            '${_axis == SagaMapPathAxis.vertical ? 'vertical' : 'horizontal'}',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  /// The feature panel. Every control here maps to one library capability.
  void _openControls() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          // Applies a change to both the sheet and the map behind it.
          void update(VoidCallback fn) {
            setState(fn);
            setSheetState(() {});
          }

          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.75,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _section('Path'),
                SegmentedButton<SagaMapPathAxis>(
                  segments: const [
                    ButtonSegment(
                      value: SagaMapPathAxis.vertical,
                      label: Text('Vertical'),
                      icon: Icon(Icons.swap_vert),
                    ),
                    ButtonSegment(
                      value: SagaMapPathAxis.horizontal,
                      label: Text('Horizontal'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                  ],
                  selected: {_axis},
                  onSelectionChanged: (s) => update(() => _axis = s.first),
                ),
                _slider(
                  label: 'Curvature',
                  value: _curvature,
                  onChanged: (v) => update(() => _curvature = v),
                ),
                SwitchListTile(
                  title: const Text('Light up the walked path'),
                  subtitle: const Text('Bright behind you, dim ahead'),
                  value: _showWalkedPath,
                  onChanged: (v) => update(() => _showWalkedPath = v),
                ),
                _section('Character'),
                SegmentedButton<DemoCharacterArt>(
                  segments: const [
                    ButtonSegment(
                      value: DemoCharacterArt.spriteSheet,
                      label: Text('Sprite sheet'),
                    ),
                    ButtonSegment(
                      value: DemoCharacterArt.flutterWidget,
                      label: Text('Widget'),
                    ),
                  ],
                  selected: {_art},
                  onSelectionChanged: (s) => update(() => _art = s.first),
                ),
                SegmentedButton<SagaCharacterGait>(
                  segments: const [
                    ButtonSegment(
                      value: SagaCharacterGait.walk,
                      label: Text('Walk'),
                    ),
                    ButtonSegment(
                      value: SagaCharacterGait.hop,
                      label: Text('Hop'),
                    ),
                  ],
                  selected: {_gait},
                  onSelectionChanged: (s) {
                    _setGait(s.first);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Camera follows the character'),
                  value: _followCharacter,
                  onChanged: (v) => update(() => _followCharacter = v),
                ),
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: const Text('Scroll to the character'),
                  subtitle: const Text('SagaMapCameraController'),
                  onTap: () => _camera.scrollToCharacter(),
                ),
                _section('Scenery'),
                SwitchListTile(
                  title: const Text('Decorations'),
                  subtitle: const Text('Trees and clouds, below the nodes'),
                  value: _showScenery,
                  onChanged: (v) => update(() => _showScenery = v),
                ),
                SwitchListTile(
                  title: const Text('Episode headers'),
                  value: _showEpisodeHeaders,
                  onChanged: (v) => update(() => _showEpisodeHeaders = v),
                ),
                SwitchListTile(
                  title: const Text('Parallax background'),
                  value: _showParallax,
                  onChanged: (v) => update(() => _showParallax = v),
                ),
                _backgroundPicker(update),
                _section('Rules'),
                SwitchListTile(
                  title: Text('Gate closed at level $_gateLevel'),
                  subtitle: const Text('Holds the character on the near side'),
                  value: _gateClosed,
                  onChanged: (v) => update(() => _gateClosed = v),
                ),
                SwitchListTile(
                  title: const Text('Pinch to zoom'),
                  subtitle: const Text('One finger still scrolls'),
                  value: _pinchZoom,
                  onChanged: (v) => update(() => _pinchZoom = v),
                ),
                SwitchListTile(
                  title: const Text('Touch-first density'),
                  subtitle: const Text('Bigger nodes and targets on phones'),
                  value: _denseMobilePolicy,
                  onChanged: (v) => update(() => _denseMobilePolicy = v),
                ),
                SwitchListTile(
                  title: const Text('Bounded memory'),
                  subtitle: const Text('Evict chunks far from the viewport'),
                  value: _boundedMemory,
                  onChanged: (v) {
                    setState(() => _boundedMemory = v);
                    _rebuildMap();
                    setSheetState(() {});
                  },
                ),
                _section('Map'),
                ListTile(
                  leading: const Icon(Icons.casino),
                  title: const Text('New seed'),
                  subtitle: Text('Currently $_seed'),
                  onTap: () {
                    _reseed(_seed + 1);
                    setSheetState(() {});
                  },
                ),
                if (_inventory.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: const Text('Boss drops'),
                    subtitle:
                        Text(_inventory.map((i) => i.itemName).join(', ')),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// A labelled divider inside the control sheet.
  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF9ED89A),
          ),
        ),
      );

  /// A `0..1` slider with its value shown alongside.
  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            divisions: 20,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(value.toStringAsFixed(2))),
      ],
    );
  }

  /// Background artwork picker.
  Widget _backgroundPicker(void Function(VoidCallback) update) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final mode in DemoBackground.values)
            ChoiceChip(
              label: Text(_backgroundLabel(mode)),
              selected: _background == mode,
              onSelected: (_) => update(() => _background = mode),
            ),
        ],
      ),
    );
  }

  /// Human-readable name for a background mode.
  String _backgroundLabel(DemoBackground mode) {
    switch (mode) {
      case DemoBackground.none:
        return 'None';
      case DemoBackground.colour:
        return 'Colour';
      case DemoBackground.svg:
        return 'SVG';
      case DemoBackground.image:
        return 'Image';
      case DemoBackground.multiSvg:
        return 'Multi-SVG';
    }
  }
}

/// Biome colours for the demo.
///
/// The upcoming colours are what create the "road lights up as you go" look:
/// the stretch the player has covered uses the bright pair, everything ahead
/// the muted one.
class _DemoBiomeTheme implements SagaBiomeThemeResolver {
  const _DemoBiomeTheme();

  @override
  SagaBiomeTheme resolve(String biomeId) {
    Color background;
    Color walked;
    switch (biomeId) {
      case kBiomeIdDesert:
        background = const Color(0xFF6E5A2A);
        walked = const Color(0xFFFFD466);
      case kBiomeIdGlacier:
        background = const Color(0xFF2A4A5C);
        walked = const Color(0xFF9FE3FF);
      default:
        background = const Color(0xFF2D5A27);
        walked = const Color(0xFFFFC107);
    }

    return SagaBiomeTheme(
      backgroundColor: background,
      pathFillColor: walked,
      pathBorderColor: const Color(0xFF5A4600),
      upcomingPathFillColor: const Color(0xFF6E7A6B),
      upcomingPathBorderColor: const Color(0xFF3B443A),
      shadowColor: const Color(0x40000000),
      pathBorderWidth: 12,
      pathInnerStrokeWidth: 7,
    );
  }
}
