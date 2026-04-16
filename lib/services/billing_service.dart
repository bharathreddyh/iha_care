import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/billing/bill.dart';
import '../models/billing/incentive_record.dart';
import '../models/billing/referral_doctor.dart';
import '../models/billing/scan_type.dart';

class BillingService {
  final _db = DatabaseHelper.instance;
  final _uuid = const Uuid();

  // ── Scan Types ────────────────────────────────────────────────────────────

  Future<List<ScanType>> getScanTypes({bool activeOnly = false}) async {
    final rows = await _db.query(
      'scan_types',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'category, name',
    );
    return rows.map(ScanType.fromMap).toList();
  }

  Future<ScanType?> getScanType(String id) async {
    final rows = await _db.query('scan_types', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ScanType.fromMap(rows.first);
  }

  Future<void> saveScanType(ScanType scan) async {
    await _db.insert('scan_types', scan.toMap());
  }

  Future<void> updateScanType(ScanType scan) async {
    await _db.update('scan_types', scan.toMap(), 'id = ?', [scan.id]);
  }

  // ── Referral Doctors ──────────────────────────────────────────────────────

  Future<List<ReferralDoctor>> getReferralDoctors({bool activeOnly = false}) async {
    final rows = await _db.query(
      'referral_doctors',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name',
    );
    return rows.map(ReferralDoctor.fromMap).toList();
  }

  Future<ReferralDoctor?> getReferralDoctor(String id) async {
    final rows = await _db.query('referral_doctors', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ReferralDoctor.fromMap(rows.first);
  }

  Future<void> saveReferralDoctor(ReferralDoctor doc) async {
    final map = doc.toMap();
    if ((map['id'] as String).isEmpty) {
      map['id'] = _uuid.v4();
    }
    await _db.insert('referral_doctors', map);
  }

  Future<void> updateReferralDoctor(ReferralDoctor doc) async {
    await _db.update('referral_doctors', doc.toMap(), 'id = ?', [doc.id]);
  }

  // ── Bills ─────────────────────────────────────────────────────────────────

  Future<String> _generateBillId(DateTime now) async {
    final yymm = DateFormat('yyMM').format(now);
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        columns: ['id'],
        where: "id LIKE ?",
        whereArgs: ['B-$yymm-%'],
        orderBy: 'id DESC',
        limit: 1,
      );
      int next = 1;
      if (rows.isNotEmpty) {
        final lastId = rows.first['id'] as String;
        final parts = lastId.split('-');
        next = (int.tryParse(parts.last) ?? 0) + 1;
      }
      return 'B-$yymm-${next.toString().padLeft(4, '0')}';
    });
  }

  Future<Bill> createBill(Bill bill) async {
    final now = DateTime.now();
    final id = await _generateBillId(now);
    final saved = bill.copyWith(
      id: id,
      accessionNumber: id,
      createdAt: now.toIso8601String(),
    );
    await _db.insert('bills', saved.toMap());
    return saved;
  }

  Future<List<Bill>> getBills({
    String? searchTerm,
    String? statusFilter,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final conditions = <String>[];
    final args = <dynamic>[];

    if (searchTerm != null && searchTerm.isNotEmpty) {
      conditions.add('(patient_name LIKE ? OR id LIKE ?)');
      args.addAll(['%$searchTerm%', '%$searchTerm%']);
    }
    if (statusFilter != null && statusFilter != 'All') {
      conditions.add('status = ?');
      args.add(statusFilter.toLowerCase());
    }
    if (fromDate != null) {
      conditions.add("date(created_at) >= date(?)");
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      conditions.add("date(created_at) <= date(?)");
      args.add(toDate.toIso8601String());
    }

    final rows = await _db.query(
      'bills',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Bill.fromMap).toList();
  }

  Future<Bill?> getBill(String id) async {
    final rows = await _db.query('bills', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Bill.fromMap(rows.first);
  }

  Future<void> markWorklistPushed(String billId) async {
    await _db.update('bills', {'worklist_pushed': 1}, 'id = ?', [billId]);
  }

  Future<void> markScanCompleted(String billId) async {
    await _db.update('bills', {'scan_completed': 1}, 'id = ?', [billId]);
  }

  Future<void> updateBillStatus(String billId, String status) async {
    await _db.update('bills', {'status': status}, 'id = ?', [billId]);
  }

  // ── Dashboard Stats ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboardStats() async {
    final todayRows = await _db.rawQuery(
      "SELECT COALESCE(SUM(final_amount), 0) as total FROM bills WHERE date(created_at) = date('now')",
    );
    final pendingRows = await _db.rawQuery(
      "SELECT COUNT(*) as cnt FROM bills WHERE worklist_pushed = 1 AND scan_completed = 0",
    );
    final monthRows = await _db.rawQuery(
      "SELECT COUNT(*) as cnt FROM bills WHERE strftime('%Y-%m', created_at) = strftime('%Y-%m', 'now')",
    );

    return {
      'todayRevenue': (todayRows.first['total'] as num? ?? 0).toDouble(),
      'pendingScans': pendingRows.first['cnt'] as int? ?? 0,
      'monthBillCount': monthRows.first['cnt'] as int? ?? 0,
    };
  }

  // ── Worklist Entries ──────────────────────────────────────────────────────

  Future<List<Bill>> getWorklistBills() async {
    final rows = await _db.query(
      'bills',
      where: 'worklist_pushed = 1',
      orderBy: 'created_at DESC',
    );
    return rows.map(Bill.fromMap).toList();
  }

  // ── Incentives ────────────────────────────────────────────────────────────

  Future<List<IncentiveRecord>> calculateMonthlyIncentives(String month) async {
    final rows = await _db.rawQuery(
      '''
      SELECT referral_doctor_id,
             COUNT(*) as referral_count,
             SUM(final_amount) as total_billed
      FROM bills
      WHERE strftime('%Y-%m', created_at) = ?
        AND referral_doctor_id IS NOT NULL
      GROUP BY referral_doctor_id
      ''',
      [month],
    );

    final records = <IncentiveRecord>[];
    for (final row in rows) {
      final docId = row['referral_doctor_id'] as String;
      final doc = await getReferralDoctor(docId);
      if (doc == null) continue;

      final totalBilled = (row['total_billed'] as num? ?? 0).toDouble();
      final incentiveAmount = doc.computeIncentive(totalBilled);

      final existing = await _db.query(
        'incentive_ledger',
        where: 'referral_doctor_id = ? AND month = ?',
        whereArgs: [docId, month],
      );

      final record = IncentiveRecord(
        id: existing.isEmpty ? _uuid.v4() : existing.first['id'] as String,
        referralDoctorId: docId,
        month: month,
        referralCount: row['referral_count'] as int? ?? 0,
        totalBilled: totalBilled,
        incentiveAmount: incentiveAmount,
        paymentStatus: existing.isEmpty
            ? 'unpaid'
            : existing.first['payment_status'] as String? ?? 'unpaid',
        paidDate: existing.isEmpty ? null : existing.first['paid_date'] as String?,
      );

      await _db.insert('incentive_ledger', record.toMap());
      records.add(record);
    }
    return records;
  }

  Future<List<IncentiveRecord>> getIncentiveLedger(String month) async {
    final rows = await _db.query(
      'incentive_ledger',
      where: 'month = ?',
      whereArgs: [month],
    );
    return rows.map(IncentiveRecord.fromMap).toList();
  }

  Future<void> markIncentivePaid(String id) async {
    await _db.update(
      'incentive_ledger',
      {'payment_status': 'paid', 'paid_date': DateTime.now().toIso8601String()},
      'id = ?',
      [id],
    );
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getReportData(String month) async {
    final scanVolumeRows = await _db.rawQuery(
      '''
      SELECT b.scan_type_id, s.name, COUNT(*) as cnt, SUM(b.final_amount) as revenue
      FROM bills b
      LEFT JOIN scan_types s ON s.id = b.scan_type_id
      WHERE strftime('%Y-%m', b.created_at) = ?
      GROUP BY b.scan_type_id
      ORDER BY cnt DESC
      ''',
      [month],
    );

    final paymentRows = await _db.rawQuery(
      '''
      SELECT payment_mode, COUNT(*) as cnt, SUM(final_amount) as total
      FROM bills
      WHERE strftime('%Y-%m', created_at) = ?
      GROUP BY payment_mode
      ''',
      [month],
    );

    final pcpdntRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) as cnt FROM pcpndt_form_f
      WHERE strftime('%Y-%m', created_at) = ?
      ''',
      [month],
    );

    return {
      'scanVolume': scanVolumeRows,
      'paymentSplit': paymentRows,
      'pcpdntCount': pcpdntRows.first['cnt'] as int? ?? 0,
    };
  }
}
