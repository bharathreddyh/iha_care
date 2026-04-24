import 'dart:convert';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';

enum AppRole { receptionist, typist }

class AppSettingsService extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
  AppRole? _role;
  List<int> _quickPrices = [1000, 1200, 1400];

  AppRole? get role => _role;
  bool get roleSet => _role != null;
  bool get isReceptionist => _role == AppRole.receptionist;
  bool get isTypist => _role == AppRole.typist;
  List<int> get quickPrices => List.unmodifiable(_quickPrices);

  Future<void> load() async {
    final rows = await _db.query('app_settings');
    for (final row in rows) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      if (key == 'role') {
        _role = value == 'typist' ? AppRole.typist : AppRole.receptionist;
      } else if (key == 'quick_prices') {
        try {
          final decoded = jsonDecode(value) as List;
          final prices = decoded.map((e) => (e as num).toInt()).toList();
          if (prices.isNotEmpty) {
            prices.sort();
            _quickPrices = prices;
          }
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> setRole(AppRole role) async {
    await _db.insert('app_settings', {
      'key': 'role',
      'value': role == AppRole.typist ? 'typist' : 'receptionist',
    });
    _role = role;
    notifyListeners();
  }

  Future<void> clearRole() async {
    await _db.delete('app_settings', 'key = ?', ['role']);
    _role = null;
    notifyListeners();
  }

  Future<void> setQuickPrices(List<int> prices) async {
    final sorted = [...prices]..sort();
    await _db.insert('app_settings', {
      'key': 'quick_prices',
      'value': jsonEncode(sorted),
    });
    _quickPrices = sorted;
    notifyListeners();
  }
}
