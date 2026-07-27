import 'package:flutter/material.dart';

import '../../core/domain/models/resolved_saga_layout.dart';
import '../../core/domain/models/saga_geometry.dart';
import 'saga_character_controller.dart';

/// What the character is doing, for a builder that swaps animations.
enum SagaCharacterMotion {
  /// Standing on a node.
  idle,

  /// Travelling between nodes.
  walking,
}

/// Which way along the path the character is oriented.
enum SagaCharacterFacing {
  /// Towards higher level numbers.
  forward,

  /// Towards lower level numbers.
  backward,
}

/// Which part of the character's art sits on the path.
enum SagaCharacterAnchor {
  /// Feet on the node. The usual choice for a standing figure.
  bottomCenter,

  /// Art centred on the node.
  center,

  /// Art hangs below the node.
  topCenter,
}

/// Everything a character builder is told about the current frame.
class SagaCharacterState {
  /// Fractional level index: `3.5` is halfway between levels 3 and 4.
  final double pathPosition;

  /// Level the character is standing on, or heading away from.
  final int nearestLevelId;

  final SagaCharacterMotion motion;
  final SagaCharacterFacing facing;

  /// Unit vector along the path at this point.
  final SagaPoint direction;

  /// [direction] as an angle from the positive x axis.
  final double headingRadians;

  /// Resolved responsive values, so a builder can scale with the map.
  final ResolvedSagaLayout layout;

  const SagaCharacterState({
    required this.pathPosition,
    required this.nearestLevelId,
    required this.motion,
    required this.facing,
    required this.direction,
    required this.headingRadians,
    required this.layout,
  });

  /// Whether the path is heading left across the screen.
  ///
  /// The one thing most sprite sheets need: mirror the art instead of drawing
  /// a second set of frames. Already accounts for a right-to-left layout,
  /// because the direction comes from the mirrored path — do not flip again.
  bool get facesLeft => direction.x < 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaCharacterState &&
          other.pathPosition == pathPosition &&
          other.nearestLevelId == nearestLevelId &&
          other.motion == motion &&
          other.facing == facing &&
          other.direction == direction &&
          other.layout == layout);

  @override
  int get hashCode => Object.hash(
        pathPosition,
        nearestLevelId,
        motion,
        facing,
        direction,
        layout,
      );
}

/// Builds the character's visual.
///
/// The library never draws the character itself, which is what lets any format
/// plug in — sprite sheet, Lottie, Rive, GIF, plain Flutter — without the
/// package depending on any of them.
typedef SagaCharacterBuilder = Widget Function(
  BuildContext context,
  SagaCharacterState state,
);

/// A character standing on, or moving along, the map's path.
class SagaCharacter {
  /// Fractional level index the character occupies.
  ///
  /// Ignored when [controller] is set, which then owns the position.
  final double pathPosition;

  /// Drives movement. Without one the character simply stands at
  /// [pathPosition].
  final SagaCharacterController? controller;

  final SagaCharacterBuilder builder;

  /// Logical size of the art before responsive scaling.
  final Size size;

  /// Which part of [size] sits on the path point.
  final SagaCharacterAnchor anchor;

  /// Extra pixel nudge after anchoring, for art with built-in padding.
  final Offset offset;

  /// Whether [size] grows with [ResolvedSagaLayout.zoom].
  ///
  /// On by default so the character stays in proportion with the map as the
  /// user pinches.
  final bool scaleWithZoom;

  final SagaCharacterMotion motion;
  final SagaCharacterFacing facing;

  /// Screen-reader label. `null` leaves the character unannounced.
  final String? semanticsLabel;

  const SagaCharacter({
    this.pathPosition = 0,
    this.controller,
    required this.builder,
    this.size = const Size(48, 64),
    this.anchor = SagaCharacterAnchor.bottomCenter,
    this.offset = Offset.zero,
    this.scaleWithZoom = true,
    this.motion = SagaCharacterMotion.idle,
    this.facing = SagaCharacterFacing.forward,
    this.semanticsLabel,
  });

  /// Where the character is right now: the controller's position if it has
  /// one, otherwise the fixed [pathPosition].
  double get effectivePathPosition => controller?.pathPosition ?? pathPosition;

  /// Current motion, from the controller when present.
  SagaCharacterMotion get effectiveMotion => controller?.motion ?? motion;

  /// Current facing, from the controller when present.
  SagaCharacterFacing get effectiveFacing => controller?.facing ?? facing;

  /// Upward hop offset in pixels, zero unless a hopping controller is mid-step.
  double get hopOffset => controller?.hopOffset ?? 0;

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

  /// Returns a copy with selective overrides.
  SagaCharacter copyWith({
    double? pathPosition,
    SagaCharacterController? controller,
    SagaCharacterBuilder? builder,
    Size? size,
    SagaCharacterAnchor? anchor,
    Offset? offset,
    bool? scaleWithZoom,
    SagaCharacterMotion? motion,
    SagaCharacterFacing? facing,
    String? semanticsLabel,
  }) {
    return SagaCharacter(
      pathPosition: pathPosition ?? this.pathPosition,
      controller: controller ?? this.controller,
      builder: builder ?? this.builder,
      size: size ?? this.size,
      anchor: anchor ?? this.anchor,
      offset: offset ?? this.offset,
      scaleWithZoom: scaleWithZoom ?? this.scaleWithZoom,
      motion: motion ?? this.motion,
      facing: facing ?? this.facing,
      semanticsLabel: semanticsLabel ?? this.semanticsLabel,
    );
  }
}
