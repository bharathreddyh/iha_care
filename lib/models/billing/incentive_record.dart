import 'incentive_scan_breakdown.dart';

class IncentiveRecord {
  final String id;
  final String referralDoctorId;
  final String month; // YYYY-MM
  final int referralCount;
  final double totalBilled;
  final double incentiveAmount;
  final String paymentStatus; // unpaid | paid
  final String? paidDate;
  // In-memory only — not persisted to incentive_ledger
  final List<IncentiveScanBreakdown> breakdown;

  const IncentiveRecord({
    required this.id,
    required this.referralDoctorId,
    required this.month,
    required this.referralCount,
    required this.totalBilled,
    required this.incentiveAmount,
    this.paymentStatus = 'unpaid',
    this.paidDate,
    this.breakdown = const [],
  });

  factory IncentiveRecord.fromMap(Map<String, dynamic> m) => IncentiveRecord(
        id: m['id'] as String,
        referralDoctorId: m['referral_doctor_id'] as String,
        month: m['month'] as String,
        referralCount: m['referral_count'] as int? ?? 0,
        totalBilled: (m['total_billed'] as num? ?? 0).toDouble(),
        incentiveAmount: (m['incentive_amount'] as num? ?? 0).toDouble(),
        paymentStatus: m['payment_status'] as String? ?? 'unpaid',
        paidDate: m['paid_date'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'referral_doctor_id': referralDoctorId,
        'month': month,
        'referral_count': referralCount,
        'total_billed': totalBilled,
        'incentive_amount': incentiveAmount,
        'payment_status': paymentStatus,
        'paid_date': paidDate,
      };

  IncentiveRecord copyWith({
    String? id,
    String? referralDoctorId,
    String? month,
    int? referralCount,
    double? totalBilled,
    double? incentiveAmount,
    String? paymentStatus,
    String? paidDate,
    List<IncentiveScanBreakdown>? breakdown,
  }) =>
      IncentiveRecord(
        id: id ?? this.id,
        referralDoctorId: referralDoctorId ?? this.referralDoctorId,
        month: month ?? this.month,
        referralCount: referralCount ?? this.referralCount,
        totalBilled: totalBilled ?? this.totalBilled,
        incentiveAmount: incentiveAmount ?? this.incentiveAmount,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paidDate: paidDate ?? this.paidDate,
        breakdown: breakdown ?? this.breakdown,
      );
}
