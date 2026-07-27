import 'package:equatable/equatable.dart';
import 'package:fast_noise/fast_noise.dart';

import '../errors/saga_domain_exceptions.dart';
import '../logging/saga_logger.dart';

/// Input parameters for procedural terrain generation.
class TerrainMapConfig extends Equatable {
  final int width;
  final int height;
  final double frequency;
  final double threshold;

  const TerrainMapConfig({
    required this.width,
    required this.height,
    this.frequency = 0.045,
    this.threshold = 0.0,
  });

  @override
  List<Object?> get props => [width, height, frequency, threshold];
}

/// One sampled cell from generated terrain.
class TerrainCell extends Equatable {
  final int x;
  final int y;
  final int biomeIndex;
  final int occupancy;

  const TerrainCell({
    required this.x,
    required this.y,
    required this.biomeIndex,
    required this.occupancy,
  });

  @override
  List<Object?> get props => [x, y, biomeIndex, occupancy];
}

/// Full generated terrain payload with occupancy and biome layers.
class TerrainMapData extends Equatable {
  final int width;
  final int height;
  final List<List<int>> occupancy;
  final List<List<int>> biomeIndices;
  final List<List<TerrainCell>> cells;

  const TerrainMapData({
    required this.width,
    required this.height,
    required this.occupancy,
    required this.biomeIndices,
    required this.cells,
  });

  @override
  List<Object?> get props => [width, height, occupancy, biomeIndices, cells];
}

/// Noise-based biome generator for map terrain prototyping.
class ProceduralBiomeGenerator {
  final SagaLogger _logger;

  const ProceduralBiomeGenerator({SagaLogger logger = const NoopSagaLogger()})
      : _logger = logger;

  /// Generates biome and occupancy matrices for a given [seed].
  TerrainMapData generate({
    required int seed,
    required TerrainMapConfig config,
  }) {
    _validateConfig(config);
    _logger.debug(
      'Generating terrain: seed=$seed width=${config.width} height=${config.height}',
    );
    final occupancyNoise = buildNoise(
      seed: seed,
      noiseType: NoiseType.perlinFractal,
      frequency: config.frequency,
      octaves: 4,
      gain: 0.5,
      lacunarity: 2.0,
    );
    final biomeNoise = buildNoise(
      seed: seed ^ 0x9E3779B9,
      noiseType: NoiseType.simplexFractal,
      frequency: config.frequency * 0.65,
      octaves: 3,
      gain: 0.5,
      lacunarity: 2.0,
    );

    final occupancy =
        List.generate(config.height, (_) => List.filled(config.width, 0));
    final biomeIndices =
        List.generate(config.height, (_) => List.filled(config.width, 0));

    for (var y = 0; y < config.height; y++) {
      for (var x = 0; x < config.width; x++) {
        final nx = x.toDouble();
        final ny = y.toDouble();
        final value = occupancyNoise.getNoise2(nx, ny);
        occupancy[y][x] = value >= config.threshold ? 1 : 0;
        final biomeValue = biomeNoise.getNoise2(nx, ny);
        biomeIndices[y][x] = _biomeFromNoise(biomeValue);
      }
    }

    final cells = List.generate(config.height, (y) {
      return List.generate(
        config.width,
        (x) => TerrainCell(
          x: x,
          y: y,
          biomeIndex: biomeIndices[y][x],
          occupancy: occupancy[y][x],
        ),
      );
    });

    return TerrainMapData(
      width: config.width,
      height: config.height,
      occupancy: occupancy,
      biomeIndices: biomeIndices,
      cells: cells,
    );
  }

  int _biomeFromNoise(double value) {
    if (value < -0.2) return 0;
    if (value < 0.25) return 1;
    return 2;
  }

  void _validateConfig(TerrainMapConfig config) {
    if (config.width <= 0 || config.height <= 0) {
      throw const InvalidTerrainConfigException(
        'TerrainMapConfig width/height must be > 0',
      );
    }
    // Cap the grid so a mistaken or hostile config cannot ask for an
    // allocation that exhausts memory. generate() builds several width×height
    // matrices, so the product — not either side alone — is what matters.
    if (config.width > kMaxTerrainDimension ||
        config.height > kMaxTerrainDimension) {
      throw const InvalidTerrainConfigException(
        'TerrainMapConfig width/height must be <= $kMaxTerrainDimension',
      );
    }
    if (config.width * config.height > kMaxTerrainCellCount) {
      throw const InvalidTerrainConfigException(
        'TerrainMapConfig width*height must be <= $kMaxTerrainCellCount',
      );
    }
    if (config.frequency <= 0) {
      throw const InvalidTerrainConfigException(
        'TerrainMapConfig frequency must be > 0',
      );
    }
  }
}

/// Largest side length [ProceduralBiomeGenerator] will accept.
const int kMaxTerrainDimension = 4096;

/// Largest total cell count [ProceduralBiomeGenerator] will accept.
///
/// A generous ceiling (~4M cells) that still bounds the several
/// `width×height` matrices `generate` allocates, so a bad config fails fast
/// instead of exhausting memory.
const int kMaxTerrainCellCount = 4 * 1024 * 1024;
