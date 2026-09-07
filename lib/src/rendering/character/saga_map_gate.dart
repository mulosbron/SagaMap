/// A barrier on the path that a closed gate holds the character behind.
///
/// The library positions the gate and stops the character at it; whether the
/// gate is open is the host's call — tickets, friends, a purchase are game
/// economy, not map geometry. An open gate is inert.
class SagaMapGate {
  /// Level index the gate sits on. The character stops just before it while
  /// closed, and passes freely once open.
  final double pathPosition;

  /// Whether the road is passable here.
  final bool isOpen;

  const SagaMapGate({
    required this.pathPosition,
    this.isOpen = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SagaMapGate &&
          other.pathPosition == pathPosition &&
          other.isOpen == isOpen);

  @override
  int get hashCode => Object.hash(pathPosition, isOpen);
}

/// Clamps a move from [from] to [to] so it stops at the first closed gate in
/// the way.
///
/// Only gates between the two positions block, and only in the direction of
/// travel. The character halts fractionally before a forward gate so it stands
/// on the near side, not on top of it.
///
/// Both branches are **closed on the destination side**: a gate placed exactly
/// on the destination blocks. The forward branch additionally blocks a gate
/// placed exactly on the origin, nudging the character back to the near side
/// rather than letting it walk off a gate it should never have been standing
/// on. Integer gate positions are the shape the README teaches, so they are the
/// shape that has to work.
double clampTravelThroughGates(
  Iterable<SagaMapGate> gates,
  double from,
  double to, {
  double stopMargin = 0.0001,
}) {
  if (to == from) return to;

  if (to > from) {
    var limit = to;
    for (final gate in gates) {
      if (gate.isOpen) continue;
      final at = gate.pathPosition;
      if (at >= from && at <= limit) {
        limit = at - stopMargin;
      }
    }
    return limit;
  }

  var limit = to;
  for (final gate in gates) {
    if (gate.isOpen) continue;
    final at = gate.pathPosition;
    if (at < from && at >= limit) {
      limit = at + stopMargin;
    }
  }
  return limit > from ? from : limit;
}
