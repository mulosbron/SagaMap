/// Item rarity tiers used by loot tables and inventory UI.
enum InventoryRarity {
  common,
  rare,
  legendary;

  static InventoryRarity fromString(String value) {
    return InventoryRarity.values.firstWhere(
      (entry) => entry.name == value,
      orElse: () => InventoryRarity.common,
    );
  }
}

/// Immutable inventory item model returned from rewards flow.
class InventoryItem {
  final String itemId;
  final String itemName;
  final InventoryRarity rarity;
  final int obtainedFromLevelId;
  final DateTime obtainedAt;

  const InventoryItem({
    required this.itemId,
    required this.itemName,
    required this.rarity,
    required this.obtainedFromLevelId,
    required this.obtainedAt,
  });

  /// Serializes this item for persistence.
  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'rarity': rarity.name,
      'obtainedFromLevelId': obtainedFromLevelId,
      'obtainedAt': obtainedAt.toIso8601String(),
    };
  }

  /// Deserializes an item from persisted JSON.
  static InventoryItem fromJson(Map<String, dynamic> json) {
    // `is` guards throughout: a wrong-typed field in a tampered save coerces to
    // a default rather than throwing.
    final rawId = json['itemId'];
    final rawName = json['itemName'];
    final rawRarity = json['rarity'];
    final rawLevel = json['obtainedFromLevelId'];
    final rawAt = json['obtainedAt'];
    return InventoryItem(
      itemId: rawId is String ? rawId : 'unknown_item',
      itemName: rawName is String ? rawName : 'Unknown',
      rarity: InventoryRarity.fromString(
          rawRarity is String ? rawRarity : 'common'),
      obtainedFromLevelId: rawLevel is num ? rawLevel.toInt() : 0,
      obtainedAt: (rawAt is String ? DateTime.tryParse(rawAt) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
