import 'package:flutter/widgets.dart';

import '../../core/domain/models/saga_geometry.dart';
import '../character/saga_character.dart';

/// A scenery item placed on a chunk — a tree, a house, a cloud.
///
/// Positioned by the library, drawn by the host. Two placements: beside the
/// path at a level, or at a free point in the chunk. Decorations sit below the
/// nodes and the path, so scenery never covers a level a player wants to tap.
class SagaMapDecoration {
  /// Level index to place beside, when this decoration hugs the path.
  ///
  /// Mutually exclusive with [chunkFraction]. A fractional value places it
  /// between two levels.
  final double? pathPosition;

  /// Signed pixels off the path along the lateral axis: negative one side,
  /// positive the other. Only meaningful with [pathPosition].
  final double lateralOffset;

  /// Normalized `0..1` point in the chunk box, when the decoration floats free
  /// of the path. Mutually exclusive with [pathPosition].
  final Offset? chunkFraction;

  /// Logical size before responsive scaling.
  final Size size;

  /// Which part of [size] sits on the resolved point.
  final SagaCharacterAnchor anchor;

  /// Extra pixel nudge after anchoring.
  final Offset offset;

  /// Whether [size] grows with the map's zoom.
  final bool scaleWithZoom;

  /// Draw order among decorations. Higher paints later, so on top.
  final int z;

  final WidgetBuilder builder;

  const SagaMapDecoration.besidePath({
    required double this.pathPosition,
    required this.builder,
    this.lateralOffset = 0,
    this.size = const Size(48, 48),
    this.anchor = SagaCharacterAnchor.bottomCenter,
    this.offset = Offset.zero,
    this.scaleWithZoom = true,
    this.z = 0,
  }) : chunkFraction = null;

  /// Top-left corner for art of [scaledSize] anchored at [point].
  Offset topLeftFor(SagaPoint point, Size scaledSize) {
    final double dy;
    switch (anchor) {
      case SagaCharacterAnchor.bottomCenter:
        dy = -scaledSize.height;
      case SagaCharacterAnchor.center:
        dy = -scaledSize.height / 2;
      case SagaCharacterAnchor.topCenter:
        dy = 0;
    }
    return Offset(
      point.x - scaledSize.width / 2 + offset.dx,
      point.y + dy + offset.dy,
    );
  }

  const SagaMapDecoration.atFraction({
    required Offset this.chunkFraction,
    required this.builder,
    this.size = const Size(48, 48),
    this.anchor = SagaCharacterAnchor.center,
    this.offset = Offset.zero,
    this.scaleWithZoom = true,
    this.z = 0,
  })  : pathPosition = null,
        lateralOffset = 0;
}

/// Produces the decorations for one chunk.
///
/// Called per chunk, so a host can scatter scenery deterministically from the
/// chunk index. Returning `const []` for a chunk leaves it bare.
typedef SagaMapDecorationBuilder = List<SagaMapDecoration> Function(
  BuildContext context,
  int chunkIndex,
);
