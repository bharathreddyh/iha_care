import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/biometry_measurement.dart';

class BiometryService {
  final String _baseUrl;

  BiometryService({String baseUrl = 'http://127.0.0.1:8000'})
      : _baseUrl = baseUrl;

  Future<List<BiometryMeasurement>> getMeasurements(String accession) async {
    final uri = Uri.parse('$_baseUrl/measurements/$accession');
    final res =
        await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Measurement fetch failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list =
        (body['measurements'] as List? ?? []).cast<Map<String, dynamic>>();
    return list.map(BiometryMeasurement.fromMap).toList();
  }

  Future<bool> isStudyInOrthanc(String accession) async {
    try {
      final uri = Uri.parse('$_baseUrl/measurements/$accession');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['count'] as int? ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }
}
