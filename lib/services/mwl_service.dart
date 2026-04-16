import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/billing/bill.dart';
import '../models/billing/scan_type.dart';
import '../models/billing/referral_doctor.dart';

class MwlResult {
  final bool success;
  final String? error;

  const MwlResult({required this.success, this.error});
}

class MwlService {
  static const _baseUrl = 'http://127.0.0.1:8000';
  static const _timeout = Duration(seconds: 5);

  final http.Client _client;

  MwlService({http.Client? client}) : _client = client ?? http.Client();

  Future<MwlResult> pushToWorklist({
    required Bill bill,
    required ScanType scanType,
    ReferralDoctor? referralDoctor,
  }) async {
    try {
      final body = {
        'patient_id': bill.patientId ?? bill.id,
        'patient_name': _formatDicomName(bill.patientName),
        'patient_dob': bill.patientDob ?? '',
        'patient_sex': bill.patientSex ?? 'O',
        'accession_number': bill.accessionNumber ?? bill.id,
        'scan_description': scanType.name,
        'scheduled_datetime': _formatDicomDateTime(DateTime.now()),
        'referring_physician': referralDoctor?.name ?? '',
        'modality': scanType.modality,
        'aet': 'SAMSUNG_V6',
      };

      final res = await _client
          .post(
            Uri.parse('$_baseUrl/worklist/add'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (res.statusCode == 200) {
        return const MwlResult(success: true);
      }
      return MwlResult(success: false, error: 'HTTP ${res.statusCode}: ${res.body}');
    } catch (e) {
      return MwlResult(success: false, error: e.toString());
    }
  }

  Future<MwlResult> removeFromWorklist(String accessionNumber) async {
    try {
      final res = await _client
          .delete(Uri.parse('$_baseUrl/worklist/$accessionNumber'))
          .timeout(_timeout);
      if (res.statusCode == 200) return const MwlResult(success: true);
      return MwlResult(success: false, error: 'HTTP ${res.statusCode}');
    } catch (e) {
      return MwlResult(success: false, error: e.toString());
    }
  }

  Future<int> getWorklistCount() async {
    try {
      final res = await _client
          .get(Uri.parse('$_baseUrl/worklist'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['count'] as int? ?? 0;
      }
    } catch (_) {}
    return -1; // -1 means service unavailable
  }

  String _formatDicomName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return '${parts[0]}^';
    return '${parts.last}^${parts.sublist(0, parts.length - 1).join(' ')}';
  }

  String _formatDicomDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$mo$d$h$mi$s';
  }
}
