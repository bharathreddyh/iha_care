class Bill {
  final String id;
  final String patientName;
  final String? patientId;
  final String? patientDob; // YYYYMMDD
  final String? patientSex; // M/F/O
  final String? patientPhone;
  final String? scanTypeId;
  final String? referralDoctorId;
  final double scanFee;
  final double discount;
  final double finalAmount;
  final String paymentMode; // Cash | UPI | Card | Credit
  final String status; // paid | pending
  final String? accessionNumber;
  final bool worklistPushed;
  final bool scanCompleted;
  final String? notes;
  final String createdAt;

  const Bill({
    required this.id,
    required this.patientName,
    this.patientId,
    this.patientDob,
    this.patientSex,
    this.patientPhone,
    this.scanTypeId,
    this.referralDoctorId,
    required this.scanFee,
    this.discount = 0,
    required this.finalAmount,
    required this.paymentMode,
    this.status = 'paid',
    this.accessionNumber,
    this.worklistPushed = false,
    this.scanCompleted = false,
    this.notes,
    required this.createdAt,
  });

  factory Bill.fromMap(Map<String, dynamic> m) => Bill(
        id: m['id'] as String,
        patientName: m['patient_name'] as String,
        patientId: m['patient_id'] as String?,
        patientDob: m['patient_dob'] as String?,
        patientSex: m['patient_sex'] as String?,
        patientPhone: m['patient_phone'] as String?,
        scanTypeId: m['scan_type_id'] as String?,
        referralDoctorId: m['referral_doctor_id'] as String?,
        scanFee: (m['scan_fee'] as num).toDouble(),
        discount: (m['discount'] as num? ?? 0).toDouble(),
        finalAmount: (m['final_amount'] as num).toDouble(),
        paymentMode: m['payment_mode'] as String,
        status: m['status'] as String? ?? 'paid',
        accessionNumber: m['accession_number'] as String?,
        worklistPushed: (m['worklist_pushed'] as int? ?? 0) == 1,
        scanCompleted: (m['scan_completed'] as int? ?? 0) == 1,
        notes: m['notes'] as String?,
        createdAt: m['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'patient_name': patientName,
        'patient_id': patientId,
        'patient_dob': patientDob,
        'patient_sex': patientSex,
        'patient_phone': patientPhone,
        'scan_type_id': scanTypeId,
        'referral_doctor_id': referralDoctorId,
        'scan_fee': scanFee,
        'discount': discount,
        'final_amount': finalAmount,
        'payment_mode': paymentMode,
        'status': status,
        'accession_number': accessionNumber,
        'worklist_pushed': worklistPushed ? 1 : 0,
        'scan_completed': scanCompleted ? 1 : 0,
        'notes': notes,
        'created_at': createdAt,
      };

  bool get isPending => status == 'pending';
  bool get isWorklistActive => worklistPushed && !scanCompleted;

  Bill copyWith({
    String? id,
    String? patientName,
    String? patientId,
    String? patientDob,
    String? patientSex,
    String? patientPhone,
    String? scanTypeId,
    String? referralDoctorId,
    double? scanFee,
    double? discount,
    double? finalAmount,
    String? paymentMode,
    String? status,
    String? accessionNumber,
    bool? worklistPushed,
    bool? scanCompleted,
    String? notes,
    String? createdAt,
  }) =>
      Bill(
        id: id ?? this.id,
        patientName: patientName ?? this.patientName,
        patientId: patientId ?? this.patientId,
        patientDob: patientDob ?? this.patientDob,
        patientSex: patientSex ?? this.patientSex,
        patientPhone: patientPhone ?? this.patientPhone,
        scanTypeId: scanTypeId ?? this.scanTypeId,
        referralDoctorId: referralDoctorId ?? this.referralDoctorId,
        scanFee: scanFee ?? this.scanFee,
        discount: discount ?? this.discount,
        finalAmount: finalAmount ?? this.finalAmount,
        paymentMode: paymentMode ?? this.paymentMode,
        status: status ?? this.status,
        accessionNumber: accessionNumber ?? this.accessionNumber,
        worklistPushed: worklistPushed ?? this.worklistPushed,
        scanCompleted: scanCompleted ?? this.scanCompleted,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
      );
}
