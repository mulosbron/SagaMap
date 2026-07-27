import 'package:flutter/gestures.dart';

/// Bounds for user-driven pinch zoom.
///
/// Pass one to [SagaInfiniteMapView.zoomConfig] to enable pinch zoom; leaving
/// it `null` keeps the map at a fixed scale.
class SagaMapZoomConfig {
  /// Most zoomed out the user may go. Below `1` the map shows more levels.
  final double min;

  /// Most zoomed in the user may go.
  final double max;

  /// Zoom the map starts at.
  final double initial;

  const SagaMapZoomConfig({
    this.min = 0.6,
    this.max = 2.5,
    this.initial = 1.0,
  })  : assert(min > 0, 'min must be greater than 0'),
        assert(max >= min, 'max must not be below min'),
        assert(
          initial >= min && initial <= max,
          'initial must lie within min..max',
        );

  /// Clamps [zoom] into this config's range.
  double clamp(double zoom) => zoom.clamp(min, max);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaMapZoomConfig &&
          other.min == min &&
          other.max == max &&
          other.initial == initial);

  @override
  int get hashCode => Object.hash(min, max, initial);
}

/// Scale recognizer that ignores single-finger gestures.
///
/// [ScaleGestureRecognizer] normally claims the gesture arena as soon as one
/// finger travels past the pan slop, which would take every drag away from the
/// surrounding scrollable and stop the map scrolling at all. Withholding
/// single-pointer movement keeps the recognizer out of the arena until a second
/// finger lands, so one finger scrolls and two fingers zoom.
class SagaPinchGestureRecognizer extends ScaleGestureRecognizer {
  SagaPinchGestureRecognizer({super.debugOwner});

  final Set<int> _pointers = <int>{};

  /// Number of fingers currently down on the map.
  int get activePointerCount => _pointers.length;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointers.add(event.pointer);
    super.addAllowedPointer(event);
    if (_pointers.length >= 2) {
      // Claim the arena the moment a second finger lands, before anyone moves.
      // Waiting for movement loses the race to the scrollable underneath, which
      // sits deeper in the tree and so is offered each event first — that is
      // why a pinch along the scroll axis would otherwise just scroll.
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    if (event is PointerMoveEvent && _pointers.length < 2) {
      // Swallowed on purpose: forwarding this is what would make the scale
      // machine resolve the arena in its favour on a one-finger drag.
      return;
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _pointers.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    _pointers.clear();
    super.dispose();
  }

  @override
  String get debugDescription => 'saga pinch';
}
