import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/inventory/inventory_item.dart';
import '../models/inventory/inventory_scan_usage.dart';
import '../models/inventory/inventory_transaction.dart';

class InventoryService {
  final _db = DatabaseHelper.instance;
  final _uuid = const Uuid();

  // ── Items ─────────────────────────────────────────────────────────────────

  Future<List<InventoryItem>> getItems({bool activeOnly = true}) async {
    final rows = await _db.query(
      'inventory_items',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name',
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<List<InventoryItem>> getLowStockItems() async {
    final rows = await _db.rawQuery(
      'SELECT * FROM inventory_items WHERE is_active = 1 AND min_quantity > 0 AND current_quantity <= min_quantity ORDER BY name',
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<void> saveItem(InventoryItem item) async {
    final map = item.toMap();
    map['synced'] = 0;
    await _db.insert('inventory_items', map);
  }

  Future<void> updateItem(InventoryItem item) async {
    final map = item.toMap();
    map['synced'] = 0;
    await _db.update('inventory_items', map, 'id = ?', [item.id]);
  }

  // ── Scan usage config ─────────────────────────────────────────────────────

  Future<List<InventoryScanUsage>> getScanUsage(String scanTypeId) async {
    final rows = await _db.query(
      'inventory_scan_usage',
      where: 'scan_type_id = ?',
      whereArgs: [scanTypeId],
    );
    return rows.map(InventoryScanUsage.fromMap).toList();
  }

  Future<void> saveScanUsage(
      String scanTypeId, List<InventoryScanUsage> usages) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'inventory_scan_usage',
        where: 'scan_type_id = ?',
        whereArgs: [scanTypeId],
      );
      for (final u in usages) {
        if (u.quantity > 0) {
          final map = u.toMap();
          map['synced'] = 0;
          await txn.insert('inventory_scan_usage', map,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  Future<List<InventoryTransaction>> getTransactions(String itemId,
      {int limit = 50}) async {
    final rows = await _db.query(
      'inventory_transactions',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(InventoryTransaction.fromMap).toList();
  }

  Future<void> addPurchase(
      String itemId, double quantity, double? cost, String? notes) async {
    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('inventory_transactions', {
        'id': _uuid.v4(),
        'item_id': itemId,
        'type': 'purchase',
        'quantity': quantity,
        'cost': cost,
        'notes': notes,
        'created_at': now,
        'synced': 0,
      });
      await txn.rawUpdate(
        'UPDATE inventory_items SET current_quantity = current_quantity + ?, synced = 0 WHERE id = ?',
        [quantity, itemId],
      );
    });
  }

  Future<void> addAdjustment(
      String itemId, double quantity, String? notes) async {
    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('inventory_transactions', {
        'id': _uuid.v4(),
        'item_id': itemId,
        'type': 'adjustment',
        'quantity': quantity,
        'notes': notes,
        'created_at': now,
        'synced': 0,
      });
      await txn.rawUpdate(
        'UPDATE inventory_items SET current_quantity = current_quantity + ?, synced = 0 WHERE id = ?',
        [quantity, itemId],
      );
    });
  }

  /// Called after a bill is created — deducts configured items for the scan type.
  Future<void> deductForBill(String billId, String scanTypeId) async {
    final usages = await getScanUsage(scanTypeId);
    if (usages.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      for (final u in usages) {
        await txn.insert('inventory_transactions', {
          'id': _uuid.v4(),
          'item_id': u.itemId,
          'type': 'usage',
          'quantity': -u.quantity,
          'bill_id': billId,
          'created_at': now,
          'synced': 0,
        });
        await txn.rawUpdate(
          'UPDATE inventory_items SET current_quantity = MAX(0, current_quantity - ?), synced = 0 WHERE id = ?',
          [u.quantity, u.itemId],
        );
      }
    });
  }
}
