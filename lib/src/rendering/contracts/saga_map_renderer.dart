import '../contracts/saga_map_render_context.dart';

/// Turns a chunk's [SagaMapRenderContext] into some renderable output.
///
/// Implemented by the built-in painter and widget adapters, and the extension
/// point for host-supplied renderers.
abstract interface class SagaMapRenderer<TOutput> {
  TOutput render(SagaMapRenderContext context);
}
