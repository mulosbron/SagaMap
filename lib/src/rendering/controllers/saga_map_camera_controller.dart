import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Scrolls the map so [pathPosition] sits at [alignment] in the viewport.
typedef SagaCameraScrollHandler = Future<void> Function(
  double pathPosition, {
  required double alignment,
  required Duration duration,
  required Curve curve,
});

/// Imperative handle for moving the map's viewport.
///
/// Attach one to [SagaInfiniteMapView] to scroll to a level from outside the
/// widget tree — after a level completes, from a "where am I" button, and so
/// on. The view attaches on mount and detaches on dispose.
class SagaMapCameraController extends ChangeNotifier {
  SagaCameraScrollHandler? _onScroll;
  double Function()? _characterPosition;

  /// Whether a view is currently listening.
  bool get isAttached => _onScroll != null;

  /// Called by [SagaInfiniteMapView]; hosts do not need this.
  void attach({
    required SagaCameraScrollHandler onScroll,
    required double Function() characterPosition,
  }) {
    _onScroll = onScroll;
    _characterPosition = characterPosition;
  }

  /// Called by [SagaInfiniteMapView] on dispose.
  ///
  /// Compared with `==` rather than `identical`: two tear-offs of the same
  /// instance method are equal but not identical, so identity would leave the
  /// controller wired to a dead view.
  void detach(SagaCameraScrollHandler onScroll) {
    if (_onScroll == onScroll) {
      _onScroll = null;
      _characterPosition = null;
    }
  }

  /// Scrolls so [pathPosition] sits at [alignment] within the viewport.
  ///
  /// [alignment] runs from `0` for the leading edge to `1` for the trailing
  /// one. Loads whatever chunks the destination needs first, so a player
  /// returning at level 250 does not scroll into empty space.
  ///
  /// Does nothing while no view is attached.
  Future<void> scrollToPathPosition(
    double pathPosition, {
    double alignment = 0.5,
    Duration duration = const Duration(milliseconds: 450),
    Curve curve = Curves.easeInOut,
  }) async {
    await _onScroll?.call(
      pathPosition,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }

  /// Scrolls to where the character currently stands.
  Future<void> scrollToCharacter({
    double alignment = 0.5,
    Duration duration = const Duration(milliseconds: 450),
    Curve curve = Curves.easeInOut,
  }) async {
    final position = _characterPosition?.call();
    if (position == null) return;
    await scrollToPathPosition(
      position,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }
}
