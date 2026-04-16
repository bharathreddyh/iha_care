import 'dart:convert';

import 'package:http/http.dart' as http;

class OrthancService {
  static const _baseUrl = 'http://127.0.0.1:8042';
  static const _timeout = Duration(seconds: 5);

  final http.Client _client;

  OrthancService({http.Client? client}) : _client = client ?? http.Client();

  Future<bool> isStudyCompleted(String accessionNumber) async {
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
        return ids.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

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
