import 'package:flutter/material.dart';

import '../database/database_helper.dart';

enum AppRole { receptionist, typist }

class AppSettingsService extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
  AppRole? _role;

  AppRole? get role => _role;
  bool get roleSet => _role != null;
  bool get isReceptionist => _role == AppRole.receptionist;
  bool get isTypist => _role == AppRole.typist;

  Future<void> load() async {
    final rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['role'],
    );
    if (rows.isNotEmpty) {
      _role = (rows.first['value'] as String) == 'typist'
          ? AppRole.typist
          : AppRole.receptionist;
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
}
