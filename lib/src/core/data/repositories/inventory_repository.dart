import '../../domain/models/inventory_item.dart';

/// Persistence contract for inventory items.
abstract interface class InventoryRepository {
  /// Returns all stored items.
  Future<List<InventoryItem>> getItems();

  /// Stores one inventory item.
  Future<void> addItem(InventoryItem item);
}
