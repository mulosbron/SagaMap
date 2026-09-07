import '../contracts/saga_map_render_context.dart';

/// Turns a chunk's [SagaMapRenderContext] into some renderable output.
///
/// Implemented by the built-in painter and widget adapters, and the injection
/// point for a host-supplied one: pass a `SagaMapRenderer<CustomPainter>` as
/// `MapChunkWidget.pathRenderer` (or `SagaInfiniteMapView.pathRenderer`) and
/// the chunk's path, terrain and biome tint are painted by yours instead. The
/// context arrives with node positions, path geometry and progress already
/// resolved.
///
/// Nodes are not injected through this interface. A node is a widget and needs
/// a [BuildContext], which `render` does not receive; `nodeBuilder` is the seam
/// for those, and it is passed the same layout the built-in adapter uses.
abstract interface class SagaMapRenderer<TOutput> {
  TOutput render(SagaMapRenderContext context);
}
