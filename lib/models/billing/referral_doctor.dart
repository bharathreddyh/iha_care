class ReferralDoctor {
  final String id;
  final String name;
  final String? phone;
  final String? clinicName;
  final String? specialty;
  final bool isActive;

  const ReferralDoctor({
    required this.id,
    required this.name,
    this.phone,
    this.clinicName,
    this.specialty,
    this.isActive = true,
  });

  factory ReferralDoctor.fromMap(Map<String, dynamic> m) => ReferralDoctor(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        clinicName: m['clinic_name'] as String?,
        specialty: m['specialty'] as String?,
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'clinic_name': clinicName,
        'specialty': specialty,
        'is_active': isActive ? 1 : 0,
      };

  ReferralDoctor copyWith({
    String? id,
    String? name,
    String? phone,
    String? clinicName,
    String? specialty,
    bool? isActive,
  }) =>
      ReferralDoctor(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        clinicName: clinicName ?? this.clinicName,
        specialty: specialty ?? this.specialty,
        isActive: isActive ?? this.isActive,
      );
}
