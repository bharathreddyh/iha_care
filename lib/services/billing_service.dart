import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/billing/bill.dart';
import '../models/billing/doctor_scan_incentive.dart';
import '../models/billing/incentive_record.dart';
import '../models/billing/incentive_scan_breakdown.dart';
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

  Future<int> rawBillCountForScanType(String scanTypeId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) as cnt FROM bills WHERE scan_type_id = ?',
      [scanTypeId],
    );
    return rows.first['cnt'] as int? ?? 0;
  }

  /// Deletes a scan type and nulls out scan_type_id on any bills that used it.
  /// Returns the count of bills that were affected.
  Future<int> deleteScanType(String id) async {
    final refs = await _db.rawQuery(
      'SELECT COUNT(*) as cnt FROM bills WHERE scan_type_id = ?',
      [id],
    );
    final affectedBills = refs.first['cnt'] as int? ?? 0;
    await _db.transaction((txn) async {
      if (affectedBills > 0) {
        await txn.rawUpdate(
          'UPDATE bills SET scan_type_id = NULL, synced = 0 WHERE scan_type_id = ?',
          [id],
        );
      }
      await txn.delete('scan_types', where: 'id = ?', whereArgs: [id]);
      await txn.delete('doctor_scan_incentives',
          where: 'scan_type_id = ?', whereArgs: [id]);
    });
    return affectedBills;
  }

  // ── Patient ID ────────────────────────────────────────────────────────────

  Future<String> generatePatientId() async {
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final rows = await _db.rawQuery(
      "SELECT patient_id FROM bills WHERE patient_id LIKE ? ORDER BY patient_id DESC LIMIT 1",
      ['${today}_%'],
    );
    int next = 1;
    if (rows.isNotEmpty) {
      final last = rows.first['patient_id'] as String? ?? '';
      final parts = last.split('_');
      next = (int.tryParse(parts.last) ?? 0) + 1;
    }
    return '${today}_${next.toString().padLeft(3, '0')}';
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

  // ── Doctor Scan Incentive Rates ───────────────────────────────────────────

  /// Returns all per-scan rates for a doctor, keyed by scan_type_id.
  Future<Map<String, DoctorScanIncentive>> getDoctorRates(String doctorId) async {
    final rows = await _db.query(
      'doctor_scan_incentives',
      where: 'doctor_id = ?',
      whereArgs: [doctorId],
    );
    return {
      for (final r in rows.map(DoctorScanIncentive.fromMap)) r.scanTypeId: r,
    };
  }

  /// Replaces all rates for a doctor atomically.
  /// Only persists rows with rate > 0; zero means "no incentive".
  Future<void> saveAllDoctorRates(
      String doctorId, List<DoctorScanIncentive> rates) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'doctor_scan_incentives',
        where: 'doctor_id = ?',
        whereArgs: [doctorId],
      );
      for (final r in rates) {
        if (r.rate > 0) {
          await txn.insert(
            'doctor_scan_incentives',
            r.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
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
    await _db.update('bills', {'scan_completed': 1, 'synced': 0}, 'id = ?', [billId]);
  }

  Future<void> markReportCreated(String billId, {bool value = true}) async {
    await _db.update('bills', {'report_created': value ? 1 : 0, 'synced': 0}, 'id = ?', [billId]);
  }

  Future<void> markDispatched(String billId, {bool value = true}) async {
    await _db.update('bills', {'dispatched': value ? 1 : 0, 'synced': 0}, 'id = ?', [billId]);
  }

  Future<void> updateAmountPaid(String billId, double amountPaid, double finalAmount) async {
    final status = amountPaid >= finalAmount ? 'paid' : 'pending';
    await _db.update('bills', {
      'amount_paid': amountPaid,
      'status': status,
      'synced': 0,
    }, 'id = ?', [billId]);
  }

  Future<void> updateBillStatus(String billId, String status) async {
    await _db.update('bills', {'status': status, 'synced': 0}, 'id = ?', [billId]);
  }

  Future<void> toggleReportExclusion(String billId, {required bool exclude}) async {
    await _db.update(
      'bills',
      {'report_excluded': exclude ? 1 : 0, 'synced': 0},
      'id = ?',
      [billId],
    );
  }

  /// Returns all bills for a given patient_id (or by name if id is null/empty).
  Future<List<Bill>> getBillsForPatient(String patientId) async {
    final rows = await _db.query(
      'bills',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Bill.fromMap).toList();
  }

  /// Cancels all non-cancelled bills for a patient. Returns count cancelled.
  Future<int> cancelAllBillsForPatient(String patientId, String reason) async {
    final bills = await getBillsForPatient(patientId);
    int count = 0;
    final now = DateTime.now().toIso8601String();
    for (final bill in bills) {
      if (!bill.isCancelled) {
        await _db.update('bills', {
          'status': 'cancelled',
          'amount_paid': 0,
          'cancelled_at': now,
          'cancel_reason': reason,
          'synced': 0,
        }, 'id = ?', [bill.id]);
        count++;
      }
    }
    return count;
  }

  /// Completely purges patient data from the database.
  /// Hard-deletes bills that are eligible (recent, unpaid, not pushed, not synced).
  /// For the rest, scrubs PII fields (name/id/dob/sex/phone) so no identifying
  /// info remains, while keeping the bill row for accounting integrity.
  /// Also deletes any pcpndt_form_f rows for this patient.
  ///
  /// Returns {deleted: n, anonymized: n} counts.
  Future<Map<String, int>> purgePatientData(String patientId) async {
    final rows = await _db.query(
      'bills',
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    int deleted = 0;
    int anonymized = 0;
    final now = DateTime.now();

    for (final row in rows) {
      final billId = row['id'] as String;
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
      final ageMin = createdAt == null
          ? 99999
          : now.difference(createdAt).inMinutes;
      final worklistPushed = (row['worklist_pushed'] as int? ?? 0) == 1;
      final amountPaid = (row['amount_paid'] as num? ?? 0).toDouble();
      final synced = (row['synced'] as int? ?? 0) == 1;

      final eligibleForHardDelete =
          ageMin <= 5 && !worklistPushed && amountPaid <= 0 && !synced;

      if (eligibleForHardDelete) {
        await _db.transaction((txn) async {
          await txn.delete('inventory_transactions',
              where: 'bill_id = ?', whereArgs: [billId]);
          await txn.delete('pcpndt_form_f',
              where: 'bill_id = ?', whereArgs: [billId]);
          await txn.delete('bills', where: 'id = ?', whereArgs: [billId]);
        });
        deleted++;
      } else {
        await _db.update('bills', {
          'patient_name': 'DELETED',
          'patient_id': null,
          'patient_dob': null,
          'patient_sex': null,
          'patient_phone': null,
          'notes': null,
          'synced': 0,
        }, 'id = ?', [billId]);
        anonymized++;
      }
    }

    // Scrub PCPNDT form rows for this patient that are still linked
    await _db.delete('pcpndt_form_f',
        where: 'patient_id = ?', whereArgs: [patientId]);

    return {'deleted': deleted, 'anonymized': anonymized};
  }

  /// Soft-cancel a bill. Sets status='cancelled', amount_paid=0, records reason + timestamp.
  /// Caller is responsible for reversing inventory and removing MWL.
  Future<void> cancelBill(String billId, String reason) async {
    await _db.update(
      'bills',
      {
        'status': 'cancelled',
        'amount_paid': 0,
        'cancelled_at': DateTime.now().toIso8601String(),
        'cancel_reason': reason,
        'synced': 0,
      },
      'id = ?',
      [billId],
    );
  }

  /// Hard-delete a bill. Only allowed when created <5 min ago,
  /// not pushed to MWL, no payment recorded, and not yet synced to cloud.
  /// Returns true if deleted, false if guards reject.
  Future<bool> deleteBillIfEligible(String billId) async {
    final rows = await _db.query('bills', where: 'id = ?', whereArgs: [billId]);
    if (rows.isEmpty) return false;
    final row = rows.first;
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
    if (createdAt == null) return false;
    final ageMinutes = DateTime.now().difference(createdAt).inMinutes;
    final worklistPushed = (row['worklist_pushed'] as int? ?? 0) == 1;
    final amountPaid = (row['amount_paid'] as num? ?? 0).toDouble();
    final synced = (row['synced'] as int? ?? 0) == 1;
    if (ageMinutes > 5 || worklistPushed || amountPaid > 0 || synced) {
      return false;
    }
    await _db.transaction((txn) async {
      await txn.delete('inventory_transactions',
          where: 'bill_id = ?', whereArgs: [billId]);
      await txn.delete('pcpndt_form_f',
          where: 'bill_id = ?', whereArgs: [billId]);
      await txn.delete('bills', where: 'id = ?', whereArgs: [billId]);
    });
    return true;
  }

  // ── Dashboard Stats ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboardStats() async {
    final todayRows = await _db.rawQuery(
      "SELECT COALESCE(SUM(final_amount), 0) as total FROM bills WHERE date(created_at) = date('now') AND status != 'cancelled' AND report_excluded = 0",
    );
    final pendingRows = await _db.rawQuery(
      "SELECT COUNT(*) as cnt FROM bills WHERE worklist_pushed = 1 AND scan_completed = 0 AND status != 'cancelled'",
    );
    final monthRows = await _db.rawQuery(
      "SELECT COUNT(*) as cnt FROM bills WHERE strftime('%Y-%m', created_at) = strftime('%Y-%m', 'now') AND status != 'cancelled' AND report_excluded = 0",
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
    // Single-pass aggregation: per-doctor per-scan-type counts and billed amounts
    final billRows = await _db.rawQuery(
      '''
      SELECT b.referral_doctor_id,
             b.scan_type_id,
             s.name AS scan_type_name,
             COUNT(*) AS cnt,
             COALESCE(SUM(b.final_amount), 0) AS billed
      FROM bills b
      LEFT JOIN scan_types s ON s.id = b.scan_type_id
      WHERE strftime('%Y-%m', b.created_at) = ?
        AND b.referral_doctor_id IS NOT NULL
        AND b.status != 'cancelled'
      GROUP BY b.referral_doctor_id, b.scan_type_id
      ''',
      [month],
    );

    if (billRows.isEmpty) return [];

    // Load incentive rates for all involved doctors in one query
    final doctorIds =
        billRows.map((r) => r['referral_doctor_id'] as String).toSet().toList();
    final placeholders = List.filled(doctorIds.length, '?').join(',');
    final rateRows = await _db.rawQuery(
      'SELECT doctor_id, scan_type_id, rate FROM doctor_scan_incentives WHERE doctor_id IN ($placeholders)',
      doctorIds,
    );

    // rateMap[doctorId][scanTypeId] = rate
    final rateMap = <String, Map<String, double>>{};
    for (final row in rateRows) {
      final did = row['doctor_id'] as String;
      final sid = row['scan_type_id'] as String;
      rateMap.putIfAbsent(did, () => {})[sid] =
          (row['rate'] as num? ?? 0).toDouble();
    }

    // Group bill rows by doctor
    final perDoctor = <String, List<Map<String, dynamic>>>{};
    for (final row in billRows) {
      perDoctor.putIfAbsent(row['referral_doctor_id'] as String, () => []).add(row);
    }

    final records = <IncentiveRecord>[];

    for (final entry in perDoctor.entries) {
      final docId = entry.key;
      final scanRows = entry.value;

      final breakdown = <IncentiveScanBreakdown>[];
      int totalCount = 0;
      double totalBilled = 0;
      double totalIncentive = 0;

      for (final row in scanRows) {
        final scanId = (row['scan_type_id'] as String?) ?? '__unknown__';
        final scanName = (row['scan_type_name'] as String?) ?? 'Unknown';
        final count = row['cnt'] as int? ?? 0;
        final billed = (row['billed'] as num? ?? 0).toDouble();
        final rate = rateMap[docId]?[scanId] ?? 0.0;

        breakdown.add(IncentiveScanBreakdown(
          scanTypeId: scanId,
          scanTypeName: scanName,
          count: count,
          rate: rate,
          total: count * rate,
        ));

        totalCount += count;
        totalBilled += billed;
        totalIncentive += count * rate;
      }

      // Preserve existing payment status
      final existing = await _db.query(
        'incentive_ledger',
        where: 'referral_doctor_id = ? AND month = ?',
        whereArgs: [docId, month],
      );

      final record = IncentiveRecord(
        id: existing.isEmpty ? _uuid.v4() : existing.first['id'] as String,
        referralDoctorId: docId,
        month: month,
        referralCount: totalCount,
        totalBilled: totalBilled,
        incentiveAmount: totalIncentive,
        paymentStatus: existing.isEmpty
            ? 'unpaid'
            : existing.first['payment_status'] as String? ?? 'unpaid',
        paidDate:
            existing.isEmpty ? null : existing.first['paid_date'] as String?,
        breakdown: breakdown,
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

  Future<Map<String, dynamic>> getReportData(
    String month, {
    bool includeExcluded = false,
    bool includeCancelled = false,
  }) async {
    String buildFilter(String alias) {
      final parts = <String>[];
      if (!includeCancelled) parts.add("$alias.status != 'cancelled'");
      if (!includeExcluded) parts.add('$alias.report_excluded = 0');
      return parts.isEmpty ? '' : 'AND ${parts.join(' AND ')}';
    }

    final bareFilter = buildFilter('bills');
    final aliasedFilter = buildFilter('b');

    final scanVolumeRows = await _db.rawQuery(
      '''
      SELECT b.scan_type_id, s.name, COUNT(*) as cnt, SUM(b.final_amount) as revenue
      FROM bills b
      LEFT JOIN scan_types s ON s.id = b.scan_type_id
      WHERE strftime('%Y-%m', b.created_at) = ?
        $aliasedFilter
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
        $bareFilter
      GROUP BY payment_mode
      ''',
      [month],
    );

    final totalsRow = await _db.rawQuery(
      '''
      SELECT COUNT(*) as cnt,
             COALESCE(SUM(final_amount), 0) as total,
             COALESCE(SUM(discount), 0) as discount
      FROM bills
      WHERE strftime('%Y-%m', created_at) = ?
        $bareFilter
      ''',
      [month],
    );

    final excludedRow = await _db.rawQuery(
      '''
      SELECT COUNT(*) as cnt,
             COALESCE(SUM(final_amount), 0) as total
      FROM bills
      WHERE strftime('%Y-%m', created_at) = ?
        AND report_excluded = 1
        AND status != 'cancelled'
      ''',
      [month],
    );

    final cancelledRow = await _db.rawQuery(
      '''
      SELECT COUNT(*) as cnt FROM bills
      WHERE strftime('%Y-%m', created_at) = ?
        AND status = 'cancelled'
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
      'totalCount': totalsRow.first['cnt'] as int? ?? 0,
      'totalRevenue': (totalsRow.first['total'] as num? ?? 0).toDouble(),
      'totalDiscount': (totalsRow.first['discount'] as num? ?? 0).toDouble(),
      'excludedCount': excludedRow.first['cnt'] as int? ?? 0,
      'excludedRevenue': (excludedRow.first['total'] as num? ?? 0).toDouble(),
      'cancelledCount': cancelledRow.first['cnt'] as int? ?? 0,
    };
  }
}
