class InventoryTransaction {
  final String id;
  final String itemId;
  final String type; // 'purchase' | 'usage' | 'adjustment'
  final double quantity; // positive = in, negative = out
  final String? billId;
  final double? cost; // for purchases
  final String? notes;
  final String createdAt;

  const InventoryTransaction({
    required this.id,
    required this.itemId,
    required this.type,
    required this.quantity,
    this.billId,
    this.cost,
    this.notes,
    required this.createdAt,
  });

  bool get isIncoming => quantity > 0;

  factory InventoryTransaction.fromMap(Map<String, dynamic> m) =>
      InventoryTransaction(
        id: m['id'] as String,
        itemId: m['item_id'] as String,
        type: m['type'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        billId: m['bill_id'] as String?,
        cost: (m['cost'] as num?)?.toDouble(),
        notes: m['notes'] as String?,
        createdAt: m['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'item_id': itemId,
        'type': type,
        'quantity': quantity,
        'bill_id': billId,
        'cost': cost,
        'notes': notes,
        'created_at': createdAt,
      };
}
