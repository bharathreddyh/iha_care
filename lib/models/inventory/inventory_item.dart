class InventoryItem {
  final String id;
  final String name;
  final String unit; // pcs, bottle, box, roll, ml, g
  final double currentQuantity;
  final double minQuantity; // low-stock threshold
  final double? pricePerUnit;
  final bool isActive;

  const InventoryItem({
    required this.id,
    required this.name,
    this.unit = 'pcs',
    this.currentQuantity = 0,
    this.minQuantity = 0,
    this.pricePerUnit,
    this.isActive = true,
  });

  bool get isLowStock => currentQuantity <= minQuantity && minQuantity > 0;
  bool get isOutOfStock => currentQuantity <= 0;

  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
        id: m['id'] as String,
        name: m['name'] as String,
        unit: m['unit'] as String? ?? 'pcs',
        currentQuantity: (m['current_quantity'] as num? ?? 0).toDouble(),
        minQuantity: (m['min_quantity'] as num? ?? 0).toDouble(),
        pricePerUnit: (m['price_per_unit'] as num?)?.toDouble(),
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'unit': unit,
        'current_quantity': currentQuantity,
        'min_quantity': minQuantity,
        'price_per_unit': pricePerUnit,
        'is_active': isActive ? 1 : 0,
      };

  InventoryItem copyWith({
    String? id,
    String? name,
    String? unit,
    double? currentQuantity,
    double? minQuantity,
    double? pricePerUnit,
    bool? isActive,
  }) =>
      InventoryItem(
        id: id ?? this.id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        currentQuantity: currentQuantity ?? this.currentQuantity,
        minQuantity: minQuantity ?? this.minQuantity,
        pricePerUnit: pricePerUnit ?? this.pricePerUnit,
        isActive: isActive ?? this.isActive,
      );
}
