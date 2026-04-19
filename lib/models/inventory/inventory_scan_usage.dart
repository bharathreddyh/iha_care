class InventoryScanUsage {
  final String id;
  final String scanTypeId;
  final String itemId;
  final double quantity;

  const InventoryScanUsage({
    required this.id,
    required this.scanTypeId,
    required this.itemId,
    required this.quantity,
  });

  factory InventoryScanUsage.fromMap(Map<String, dynamic> m) =>
      InventoryScanUsage(
        id: m['id'] as String,
        scanTypeId: m['scan_type_id'] as String,
        itemId: m['item_id'] as String,
        quantity: (m['quantity'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'scan_type_id': scanTypeId,
        'item_id': itemId,
        'quantity': quantity,
      };
}
