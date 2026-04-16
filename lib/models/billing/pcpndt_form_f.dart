class PcpdntFormF {
  final String id;
  final String billId;
  final String? patientId;
  final String? referralDoctorId;
  final String? indication;
  final bool declarationSigned;
  final String createdAt;

  const PcpdntFormF({
    required this.id,
    required this.billId,
    this.patientId,
    this.referralDoctorId,
    this.indication,
    this.declarationSigned = false,
    required this.createdAt,
  });

  factory PcpdntFormF.fromMap(Map<String, dynamic> m) => PcpdntFormF(
        id: m['id'] as String,
        billId: m['bill_id'] as String,
        patientId: m['patient_id'] as String?,
        referralDoctorId: m['referral_doctor_id'] as String?,
        indication: m['indication'] as String?,
        declarationSigned: (m['declaration_signed'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'bill_id': billId,
        'patient_id': patientId,
        'referral_doctor_id': referralDoctorId,
        'indication': indication,
        'declaration_signed': declarationSigned ? 1 : 0,
        'created_at': createdAt,
      };
}
