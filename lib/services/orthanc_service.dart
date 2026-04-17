import 'dart:convert';

import 'package:http/http.dart' as http;

class OrthancService {
  static const _baseUrl = 'http://127.0.0.1:8042';
  static const _timeout = Duration(seconds: 5);

  final http.Client _client;

  OrthancService({http.Client? client}) : _client = client ?? http.Client();

  // ── Connectivity ──────────────────────────────────────────────────────────

  Future<bool> isReachable() async {
    try {
      final res = await _client
          .get(Uri.parse('$_baseUrl/system'))
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Study lookup ──────────────────────────────────────────────────────────

  Future<bool> isStudyCompleted(String accessionNumber) async {
    final id = await getStudyIdByAccession(accessionNumber);
    return id != null;
  }

  /// Returns the Orthanc study ID for the given accession number, or null.
  Future<String?> getStudyIdByAccession(String accessionNumber) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl/tools/find'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'Level': 'Study',
              'Query': {'AccessionNumber': accessionNumber},
            }),
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final ids = jsonDecode(res.body) as List<dynamic>;
        return ids.isEmpty ? null : ids.first as String;
      }
    } catch (_) {}
    return null;
  }

  // ── Instance (image) retrieval ────────────────────────────────────────────

  /// Returns all Orthanc instance IDs for every series in the study.
  Future<List<String>> getInstanceIds(String studyId) async {
    try {
      final studyRes = await _client
          .get(Uri.parse('$_baseUrl/studies/$studyId'))
          .timeout(_timeout);
      if (studyRes.statusCode != 200) return [];

      final study = jsonDecode(studyRes.body) as Map<String, dynamic>;
      final seriesIds = (study['Series'] as List<dynamic>).cast<String>();

      final instanceIds = <String>[];
      for (final seriesId in seriesIds) {
        final seriesRes = await _client
            .get(Uri.parse('$_baseUrl/series/$seriesId/instances'))
            .timeout(_timeout);
        if (seriesRes.statusCode == 200) {
          final instances = jsonDecode(seriesRes.body) as List<dynamic>;
          for (final inst in instances) {
            instanceIds.add((inst as Map<String, dynamic>)['ID'] as String);
          }
        }
      }
      return instanceIds;
    } catch (_) {
      return [];
    }
  }

  /// JPEG preview URL for an instance (rendered by Orthanc).
  String instancePreviewUrl(String instanceId) =>
      '$_baseUrl/instances/$instanceId/preview';

  /// Full JPEG download URL for an instance.
  String instanceDownloadUrl(String instanceId) =>
      '$_baseUrl/instances/$instanceId/rendered';

  // ── Convenience ───────────────────────────────────────────────────────────

  /// Fetches all instance IDs for the study matching [accessionNumber].
  Future<List<String>> getInstancesForAccession(String accessionNumber) async {
    final studyId = await getStudyIdByAccession(accessionNumber);
    if (studyId == null) return [];
    return getInstanceIds(studyId);
  }

  Future<List<Map<String, dynamic>>> getRecentStudies() async {
    try {
      final res = await _client
          .get(Uri.parse('$_baseUrl/studies?expand'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }
}
