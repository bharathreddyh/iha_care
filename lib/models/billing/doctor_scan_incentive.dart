class DoctorScanIncentive {
  final String id;
  final String doctorId;
  final String scanTypeId;
  final double rate; // ₹ per referral (per bill)

  const DoctorScanIncentive({
    required this.id,
    required this.doctorId,
    required this.scanTypeId,
    required this.rate,
  });

  factory DoctorScanIncentive.fromMap(Map<String, dynamic> m) =>
      DoctorScanIncentive(
        id: m['id'] as String,
        doctorId: m['doctor_id'] as String,
        scanTypeId: m['scan_type_id'] as String,
        rate: (m['rate'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'doctor_id': doctorId,
        'scan_type_id': scanTypeId,
        'rate': rate,
      };
}
