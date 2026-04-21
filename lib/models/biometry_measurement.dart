class BiometryMeasurement {
  final String name;
  final dynamic value;
  final String unit;

  const BiometryMeasurement({
    required this.name,
    required this.value,
    required this.unit,
  });

  factory BiometryMeasurement.fromMap(Map<String, dynamic> m) =>
      BiometryMeasurement(
        name: m['name'] as String? ?? '',
        value: m['value'],
        unit: m['unit'] as String? ?? '',
      );

  String get displayValue {
    if (value is double || value is int) {
      final d = (value as num).toDouble();
      return d == d.truncateToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
    }
    return value?.toString() ?? '';
  }

  String get displayUnit => unit == 'date' ? '' : unit;
}
