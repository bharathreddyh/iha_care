class ScanType {
  final String id;
  final String name;
  final double price;
  final String category;
  final String modality;
  final bool isActive;

  const ScanType({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.modality = 'US',
    this.isActive = true,
  });

  factory ScanType.fromMap(Map<String, dynamic> m) => ScanType(
        id: m['id'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        category: m['category'] as String,
        modality: m['modality'] as String? ?? 'US',
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'category': category,
        'modality': modality,
        'is_active': isActive ? 1 : 0,
      };

  ScanType copyWith({
    String? id,
    String? name,
    double? price,
    String? category,
    String? modality,
    bool? isActive,
  }) =>
      ScanType(
        id: id ?? this.id,
        name: name ?? this.name,
        price: price ?? this.price,
        category: category ?? this.category,
        modality: modality ?? this.modality,
        isActive: isActive ?? this.isActive,
      );
}
