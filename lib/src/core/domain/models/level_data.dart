import 'saga_geometry.dart';

/// Immutable map node model that describes one level on the path.
///
/// Ids are zero-based: the first level a player sees has `id == 0`.
/// Display `id + 1` wherever a player reads the number.
class LevelData {
  /// Zero-based identifier for the level.
  final int id;

  /// Normalized position: `y` advances along the path axis, `x` is the lateral
  /// zig-zag. Which screen axis each maps to is decided by the path axis.
  final SagaPoint position;

  final String biomeId;

  /// Difficulty level, typically calculated as `1 + (id % 5)` (where id is zero-based).
  final int difficulty;

  const LevelData({
    required this.id,
    required this.position,
    required this.biomeId,
    this.difficulty = 1,
  });

  /// Returns a copy with selective field overrides.
  LevelData copyWith({
    int? id,
    SagaPoint? position,
    String? biomeId,
    int? difficulty,
  }) {
    return LevelData(
      id: id ?? this.id,
      position: position ?? this.position,
      biomeId: biomeId ?? this.biomeId,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LevelData &&
        other.id == id &&
        other.position == position &&
        other.biomeId == biomeId &&
        other.difficulty == difficulty;
  }

  @override
  int get hashCode => Object.hash(id, position, biomeId, difficulty);

  @override
  String toString() =>
      'LevelData(id: $id, position: $position, biomeId: $biomeId, '
      'difficulty: $difficulty)';
}
