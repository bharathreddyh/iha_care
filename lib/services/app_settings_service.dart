import 'dart:convert';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';

enum AppRole { receptionist, typist }

// Neutral defaults — each centre sets its own letterhead in Bill Settings.
const _kDefaultHeader1 = 'Your Centre Name';
const _kDefaultHeader2 = 'Scan and Diagnostics Centre';
const _kDefaultFooter  = 'Thank you for visiting';

class AppSettingsService extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
  AppRole? _role;
  List<int> _quickPrices = [1000, 1200, 1400];
  String _receiptHeader1 = _kDefaultHeader1;
  String _receiptHeader2 = _kDefaultHeader2;
  String _receiptFooter  = _kDefaultFooter;

  AppRole? get role => _role;
  bool get roleSet => _role != null;
  bool get isReceptionist => _role == AppRole.receptionist;
  bool get isTypist => _role == AppRole.typist;
  List<int> get quickPrices => List.unmodifiable(_quickPrices);
  String get receiptHeader1 => _receiptHeader1;
  String get receiptHeader2 => _receiptHeader2;
  String get receiptFooter  => _receiptFooter;

  Future<void> load() async {
    final rows = await _db.query('app_settings');
    for (final row in rows) {
      final key   = row['key']   as String;
      final value = row['value'] as String;
      switch (key) {
        case 'role':
          _role = value == 'typist' ? AppRole.typist : AppRole.receptionist;
        case 'quick_prices':
          try {
            final decoded = jsonDecode(value) as List;
            final prices = decoded.map((e) => (e as num).toInt()).toList();
            if (prices.isNotEmpty) { prices.sort(); _quickPrices = prices; }
          } catch (_) {}
        case 'receipt_header1':
          if (value.isNotEmpty) _receiptHeader1 = value;
        case 'receipt_header2':
          _receiptHeader2 = value;
        case 'receipt_footer':
          if (value.isNotEmpty) _receiptFooter = value;
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

  Future<void> setReceiptText({
    required String header1,
    required String header2,
    required String footer,
  }) async {
    await Future.wait([
      _db.insert('app_settings', {'key': 'receipt_header1', 'value': header1}),
      _db.insert('app_settings', {'key': 'receipt_header2', 'value': header2}),
      _db.insert('app_settings', {'key': 'receipt_footer',  'value': footer}),
    ]);
    _receiptHeader1 = header1;
    _receiptHeader2 = header2;
    _receiptFooter  = footer;
    notifyListeners();
  }
}
