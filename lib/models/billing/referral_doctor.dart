class ReferralDoctor {
  final String id;
  final String name;
  final String? phone;
  final String? clinicName;
  final String? specialty;
  final String incentiveType; // 'percentage' | 'flat'
  final double incentiveValue;
  final bool isActive;

  const ReferralDoctor({
    required this.id,
    required this.name,
    this.phone,
    this.clinicName,
    this.specialty,
    this.incentiveType = 'flat',
    this.incentiveValue = 0,
    this.isActive = true,
  });

  factory ReferralDoctor.fromMap(Map<String, dynamic> m) => ReferralDoctor(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        clinicName: m['clinic_name'] as String?,
        specialty: m['specialty'] as String?,
        incentiveType: m['incentive_type'] as String? ?? 'flat',
        incentiveValue: (m['incentive_value'] as num? ?? 0).toDouble(),
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'clinic_name': clinicName,
        'specialty': specialty,
        'incentive_type': incentiveType,
        'incentive_value': incentiveValue,
        'is_active': isActive ? 1 : 0,
      };

  double computeIncentive(double billedAmount) {
    if (incentiveType == 'percentage') {
      return billedAmount * incentiveValue / 100;
    }
    return incentiveValue;
  }

  ReferralDoctor copyWith({
    String? id,
    String? name,
    String? phone,
    String? clinicName,
    String? specialty,
    String? incentiveType,
    double? incentiveValue,
    bool? isActive,
  }) =>
      ReferralDoctor(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        clinicName: clinicName ?? this.clinicName,
        specialty: specialty ?? this.specialty,
        incentiveType: incentiveType ?? this.incentiveType,
        incentiveValue: incentiveValue ?? this.incentiveValue,
        isActive: isActive ?? this.isActive,
      );
}
