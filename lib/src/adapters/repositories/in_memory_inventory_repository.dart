import '../../core/data/repositories/inventory_repository.dart';
import '../../core/domain/models/inventory_item.dart';

/// In-memory [InventoryRepository] implementation for demos and tests.
class InMemoryInventoryRepository implements InventoryRepository {
  final List<InventoryItem> _items;

  InMemoryInventoryRepository([List<InventoryItem>? seedItems])
      : _items = List<InventoryItem>.from(seedItems ?? const []);

  @override
  Future<void> addItem(InventoryItem item) async {
    _items.add(item);
  }

  @override
  Future<List<InventoryItem>> getItems() async {
    return List<InventoryItem>.unmodifiable(_items);
  }
}
