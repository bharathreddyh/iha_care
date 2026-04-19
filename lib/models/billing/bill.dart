class Bill {
  final String id;
  final String patientName;
  final String? patientId;
  final String? patientDob;
  final String? patientSex;
  final String? patientPhone;
  final String? scanTypeId;
  final String? referralDoctorId;
  final double scanFee;
  final double discount;
  final double finalAmount;
  final double amountPaid;
  final String paymentMode;
  final String status;
  final String? accessionNumber;
  final bool worklistPushed;
  final bool scanCompleted;
  final bool reportCreated;
  final bool dispatched;
  final String? notes;
  final String createdAt;
  final String? cancelledAt;
  final String? cancelReason;
  final bool reportExcluded;

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
    double? amountPaid,
    required this.paymentMode,
    this.status = 'paid',
    this.accessionNumber,
    this.worklistPushed = false,
    this.scanCompleted = false,
    this.reportCreated = false,
    this.dispatched = false,
    this.notes,
    required this.createdAt,
    this.cancelledAt,
    this.cancelReason,
    this.reportExcluded = false,
  }) : amountPaid = amountPaid ?? finalAmount;

  double get pendingAmount =>
      (finalAmount - amountPaid).clamp(0, double.infinity);
  bool get isFullyPaid => pendingAmount < 0.01;
  bool get isWorklistActive => worklistPushed && !scanCompleted;
  bool get isCancelled => status == 'cancelled';

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
        amountPaid: (m['amount_paid'] as num?)?.toDouble(),
        paymentMode: m['payment_mode'] as String,
        status: m['status'] as String? ?? 'paid',
        accessionNumber: m['accession_number'] as String?,
        worklistPushed: (m['worklist_pushed'] as int? ?? 0) == 1,
        scanCompleted: (m['scan_completed'] as int? ?? 0) == 1,
        reportCreated: (m['report_created'] as int? ?? 0) == 1,
        dispatched: (m['dispatched'] as int? ?? 0) == 1,
        notes: m['notes'] as String?,
        createdAt: m['created_at'] as String,
        cancelledAt: m['cancelled_at'] as String?,
        cancelReason: m['cancel_reason'] as String?,
        reportExcluded: (m['report_excluded'] as int? ?? 0) == 1,
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
        'amount_paid': amountPaid,
        'payment_mode': paymentMode,
        'status': status,
        'accession_number': accessionNumber,
        'worklist_pushed': worklistPushed ? 1 : 0,
        'scan_completed': scanCompleted ? 1 : 0,
        'report_created': reportCreated ? 1 : 0,
        'dispatched': dispatched ? 1 : 0,
        'notes': notes,
        'created_at': createdAt,
        'cancelled_at': cancelledAt,
        'cancel_reason': cancelReason,
        'report_excluded': reportExcluded ? 1 : 0,
      };

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
    double? amountPaid,
    String? paymentMode,
    String? status,
    String? accessionNumber,
    bool? worklistPushed,
    bool? scanCompleted,
    bool? reportCreated,
    bool? dispatched,
    String? notes,
    String? createdAt,
    String? cancelledAt,
    String? cancelReason,
    bool? reportExcluded,
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
        amountPaid: amountPaid ?? this.amountPaid,
        paymentMode: paymentMode ?? this.paymentMode,
        status: status ?? this.status,
        accessionNumber: accessionNumber ?? this.accessionNumber,
        worklistPushed: worklistPushed ?? this.worklistPushed,
        scanCompleted: scanCompleted ?? this.scanCompleted,
        reportCreated: reportCreated ?? this.reportCreated,
        dispatched: dispatched ?? this.dispatched,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        cancelReason: cancelReason ?? this.cancelReason,
        reportExcluded: reportExcluded ?? this.reportExcluded,
      );
}
