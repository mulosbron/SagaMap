// Public API surface for the `saga_map` package.
// Import only this file from consuming applications:
// `import 'package:saga_map/saga_map.dart';`
// Everything under `lib/src` is implementation detail.

// Core domain
export 'src/core/domain/biome_ids.dart';
// Includes the concrete subtypes: `show SagaDomainException` alone left
// consumers unable to name the exception ProceduralBiomeGenerator throws.
export 'src/core/domain/errors/saga_domain_exceptions.dart';
export 'src/core/domain/generators/level_generator.dart';
export 'src/core/domain/generators/saga_map_level_generator.dart';
export 'src/core/domain/logging/saga_logger.dart';
export 'src/core/domain/loot_table.dart';
export 'src/core/domain/loot_table_odds.dart';
export 'src/core/domain/models/inventory_item.dart';
export 'src/core/domain/models/level_data.dart';
export 'src/core/domain/models/level_progress.dart';
export 'src/core/domain/models/resolved_saga_layout.dart';
export 'src/core/domain/models/saga_geometry.dart';
export 'src/core/domain/models/saga_map_config.dart';
export 'src/core/domain/models/saga_progress.dart';
export 'src/core/domain/models/saga_progress_stars.dart';
export 'src/core/domain/responsive/saga_map_responsive_config.dart';
export 'src/core/domain/responsive/saga_responsive_resolver.dart';
export 'src/core/domain/saga_dominant_biome.dart';
export 'src/core/domain/saga_map_chunk_constants.dart';
export 'src/core/domain/saga_map_coordinates.dart';
export 'src/core/domain/saga_seed_constants.dart';
export 'src/core/domain/saga_seed_utils.dart';
export 'src/core/domain/saga_stable_hash.dart';
export 'src/core/domain/terrain/biome_noise_generator.dart';
export 'src/core/domain/usecases/complete_level_usecase.dart';

// Repository contracts
export 'src/core/data/repositories/inventory_repository.dart';
export 'src/core/data/repositories/saga_progress_repository.dart';

// Default adapters
export 'src/adapters/repositories/in_memory_inventory_repository.dart';
export 'src/adapters/repositories/in_memory_saga_progress_repository.dart';

// Rendering themes
export 'src/rendering/background/saga_map_background.dart';
export 'src/rendering/theme/saga_biome_theme.dart';
export 'src/rendering/theme/saga_biome_theme_resolver.dart';

// Rendering contracts and built-in adapters.
// These carry the `SagaNodeBuilder` and `SagaNodeProgressResolver` typedefs
// that appear in the widget signatures above, and are the extension point for
// host-supplied renderers.
export 'src/rendering/contracts/saga_map_render_context.dart';
export 'src/rendering/contracts/saga_chunk_context.dart';
export 'src/rendering/contracts/saga_map_renderer.dart';
export 'src/rendering/adapters/painter_renderer_adapter.dart';
export 'src/rendering/painters/saga_path_geometry.dart';
export 'src/rendering/painters/saga_path_metrics.dart';
export 'src/rendering/painters/saga_chunk_fraction.dart';
export 'src/rendering/adapters/widget_renderer_adapter.dart';

// Character on the path
export 'src/rendering/character/saga_character.dart';
export 'src/rendering/decoration/saga_map_decoration.dart';
export 'src/rendering/character/saga_character_controller.dart';
export 'src/rendering/character/saga_map_gate.dart';

// Sprite sheet playback (dependency-free; other formats have their own packages)
export 'src/rendering/sprites/saga_sprite_animation.dart';
export 'src/rendering/sprites/saga_sprite_sheet.dart';

// Rendering widgets
export 'src/rendering/widgets/map_chunk_widget.dart';
export 'src/rendering/widgets/saga_infinite_map_view.dart';

// Rendering interactions and controller
export 'src/rendering/controllers/saga_infinite_map_controller.dart';
export 'src/rendering/controllers/saga_map_camera_controller.dart';
export 'src/rendering/interaction/saga_map_zoom.dart';
export 'src/rendering/interaction/saga_node_interaction_handler.dart';
export 'src/rendering/interaction/saga_node_interaction_policy.dart';


