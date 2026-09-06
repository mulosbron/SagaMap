import 'dart:async';

import 'package:flutter/material.dart';

import 'saga_character.dart';

/// How the character travels between nodes.
enum SagaCharacterGait {
  /// Follows the drawn path.
  walk,

  /// Arcs over the gap between nodes, touching down on each one.
  hop,
}

/// Drives a character along the path.
///
/// Movement is stepped node by node with a short pause on each, which is what
/// makes progress read as a journey rather than a slide. A step's duration
/// scales with the distance it covers, so a five-node move is five times a
/// one-node move instead of the same sprint.
class SagaCharacterController extends ChangeNotifier {
  /// Time spent travelling one whole level.
  final Duration stepDuration;

  /// Pause on each node passed through, excluding the destination.
  final Duration stepPause;

  final Curve curve;
  final SagaCharacterGait gait;

  /// Peak height of a [SagaCharacterGait.hop] arc, in logical pixels.
  final double hopHeight;

  /// Clamps a requested move so it stops at a closed gate in the way.
  ///
  /// Given the start and target, returns how far the character may actually
  /// travel. `null` means no barriers.
  ///
  /// You rarely set this by hand: pass a gate list to
  /// `SagaInfiniteMapView.gates` and the view applies
  /// [clampTravelThroughGates] for you. Set it only for a barrier gates cannot
  /// express — the view then leaves yours in place rather than replacing it.
  double Function(double from, double to)? barrier;

  final AnimationController _animation;

  double _position;
  double _from = 0;
  double _to = 0;
  bool _moving = false;

  /// Identifies the active journey, so a superseded one can bow out.
  Object? _journey;

  SagaCharacterController({
    required TickerProvider vsync,
    double initialPosition = 0,
    this.stepDuration = const Duration(milliseconds: 420),
    this.stepPause = const Duration(milliseconds: 90),
    this.curve = Curves.easeInOut,
    this.gait = SagaCharacterGait.walk,
    this.hopHeight = 28,
    this.barrier,
  })  : _position = initialPosition,
        _animation = AnimationController(vsync: vsync) {
    _animation.addListener(_onAnimationTick);
  }

  /// Fractional level index the character currently occupies.
  double get pathPosition => _position;

  /// Whether a journey is under way.
  bool get isMoving => _moving;

  SagaCharacterMotion get motion =>
      _moving ? SagaCharacterMotion.walking : SagaCharacterMotion.idle;

  SagaCharacterFacing get facing =>
      _to >= _from ? SagaCharacterFacing.forward : SagaCharacterFacing.backward;

  /// Progress through the current step, `0..1`. Zero when standing still.
  double get stepProgress => _moving ? _animation.value : 0;

  /// Upward pixel offset from the hop arc, zero for a walking gait.
  ///
  /// Peaks halfway between nodes and returns to zero on each one, so the
  /// character always lands on the node rather than floating past it.
  double get hopOffset {
    if (gait != SagaCharacterGait.hop || !_moving) return 0;
    final p = _animation.value;
    return -hopHeight * 4 * p * (1 - p);
  }

  void _onAnimationTick() {
    final t = curve.transform(_animation.value.clamp(0.0, 1.0));
    _position = _from + (_to - _from) * t;
    notifyListeners();
  }

  /// Places the character without animating.
  void jumpTo(double position) {
    _journey = null;
    if (_animation.isAnimating) _animation.stop();
    _moving = false;
    _from = position;
    _to = position;
    _position = position;
    notifyListeners();
  }

  /// Walks to [position], one node at a time.
  ///
  /// Interrupting an in-flight journey resumes from wherever the character has
  /// got to, rather than snapping back to where the last one began.
  ///
  /// Set [animate] to `false`, or turn on the platform's reduced-motion
  /// setting, to place the character instead.
  Future<void> moveTo(double position, {bool animate = true}) async {
    // A closed gate shortens the journey to its near side.
    final target = barrier?.call(_position, position) ?? position;

    if (!animate) {
      jumpTo(target);
      return;
    }

    final journey = Object();
    _journey = journey;
    _moving = true;
    notifyListeners();

    while (_position != target) {
      final next = _nextStop(target);
      await _animateStep(next);
      if (_journey != journey) return; // superseded or stopped

      if (next != target && stepPause > Duration.zero) {
        await Future<void>.delayed(stepPause);
        if (_journey != journey) return;
      }
    }

    _moving = false;
    _journey = null;
    notifyListeners();
  }

  /// Walks [steps] levels forward, or backward when negative.
  Future<void> advance({int steps = 1, bool animate = true}) {
    return moveTo(_position.roundToDouble() + steps, animate: animate);
  }

  /// Halts where the character stands.
  void stop() {
    if (!_moving) return;
    _journey = null;
    _animation.stop();
    _moving = false;
    notifyListeners();
  }

  /// Next node on the way to [target], or [target] itself when nearer.
  double _nextStop(double target) {
    if (target > _position) {
      final next = _position.floorToDouble() + 1;
      return next < target ? next : target;
    }
    final next = _position.ceilToDouble() - 1;
    return next > target ? next : target;
  }

  Future<void> _animateStep(double target) {
    _from = _position;
    _to = target;

    // Distance-proportional, so a partial step does not take a whole step's
    // time and the character keeps an even pace throughout a journey.
    final distance = (target - _from).abs();
    _animation.duration = Duration(
      microseconds: (stepDuration.inMicroseconds * distance).round(),
    );
    if (_animation.duration == Duration.zero) {
      _position = target;
      notifyListeners();
      return Future<void>.value();
    }
    return _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _journey = null;
    _animation.removeListener(_onAnimationTick);
    _animation.dispose();
    super.dispose();
  }
}
