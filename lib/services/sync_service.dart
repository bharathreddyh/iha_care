import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_helper.dart';
import 'auth_service.dart';

enum SyncStatus { idle, syncing, error, offline }

class SyncService extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
  final AuthService _auth;
  final _client = Supabase.instance.client;

  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSync;
  String? _lastError;
  StreamSubscription? _connectivitySub;
  Timer? _syncTimer;

  SyncStatus get status => _status;
  DateTime? get lastSync => _lastSync;
  String? get lastError => _lastError;

  SyncService(this._auth) {
    _auth.addListener(_onAuthChanged);
    if (_auth.isLoggedIn) start();
  }

  void _onAuthChanged() {
    if (_auth.isLoggedIn) {
      start();
    } else {
      stop();
    }
  }

  void start() {
    _connectivitySub?.cancel();
    _syncTimer?.cancel();

    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        syncAll();
      } else {
        _setStatus(SyncStatus.offline);
      }
    });

    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => syncAll());
    syncAll();
  }

  void stop() {
    _connectivitySub?.cancel();
    _syncTimer?.cancel();
    _connectivitySub = null;
    _syncTimer = null;
    _setStatus(SyncStatus.idle);
  }

  Future<void> syncAll() async {
    if (!_auth.isLoggedIn) return;
    final centreId = _auth.centreId!;
    _setStatus(SyncStatus.syncing);
    try {
      await _pushScanTypes();
      await _pushReferralDoctors(centreId);
      await _pushDoctorScanIncentives(centreId);
      await _pushBills(centreId);
      await _pushIncentiveLedger(centreId);

      await _pullScanTypes();
      await _pullReferralDoctors(centreId);
      await _pullDoctorScanIncentives(centreId);
      await _pullBills(centreId);

      _lastSync = DateTime.now();
      _lastError = null;
      _setStatus(SyncStatus.idle);
      _saveSyncTime();
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SyncStatus.error);
    }
  }

  // ── Push helpers ─────────────────────────────────────────────────────────

  Future<void> _pushBills(String centreId) async {
    final rows = await _db.query('bills', where: 'synced = 0');
    if (rows.isEmpty) return;
    final batch = rows.map((row) {
      final r = Map<String, dynamic>.from(row);
      r['centre_id'] = centreId;
      r['worklist_pushed'] = r['worklist_pushed'] == 1;
      r['scan_completed'] = r['scan_completed'] == 1;
      r.remove('synced');
      return r;
    }).toList();
    await _client.from('bills').upsert(batch, onConflict: 'id');
    for (final row in rows) {
      await _db.update('bills', {'synced': 1}, 'id = ?', [row['id']]);
    }
  }

  Future<void> _pushReferralDoctors(String centreId) async {
    final rows = await _db.query('referral_doctors', where: 'synced = 0');
    if (rows.isEmpty) return;
    final batch = rows.map((row) {
      final r = Map<String, dynamic>.from(row);
      r['centre_id'] = centreId;
      r['is_active'] = r['is_active'] == 1;
      r.remove('synced');
      r.remove('incentive_type');
      r.remove('incentive_value');
      return r;
    }).toList();
    await _client.from('referral_doctors').upsert(batch, onConflict: 'id');
    for (final row in rows) {
      await _db.update(
          'referral_doctors', {'synced': 1}, 'id = ?', [row['id']]);
    }
  }

  Future<void> _pushScanTypes() async {
    final rows = await _db.query('scan_types', where: 'synced = 0');
    if (rows.isEmpty) return;
    final batch = rows.map((row) {
      final r = Map<String, dynamic>.from(row);
      r['is_active'] = r['is_active'] == 1;
      r.remove('synced');
      return r;
    }).toList();
    await _client.from('scan_types').upsert(batch, onConflict: 'id');
    for (final row in rows) {
      await _db.update('scan_types', {'synced': 1}, 'id = ?', [row['id']]);
    }
  }

  Future<void> _pushDoctorScanIncentives(String centreId) async {
    final rows =
        await _db.query('doctor_scan_incentives', where: 'synced = 0');
    if (rows.isEmpty) return;
    final batch = rows.map((row) {
      final r = Map<String, dynamic>.from(row);
      r['centre_id'] = centreId;
      r.remove('synced');
      return r;
    }).toList();
    await _client
        .from('doctor_scan_incentives')
        .upsert(batch, onConflict: 'id');
    for (final row in rows) {
      await _db.update(
          'doctor_scan_incentives', {'synced': 1}, 'id = ?', [row['id']]);
    }
  }

  Future<void> _pushIncentiveLedger(String centreId) async {
    final rows = await _db.query('incentive_ledger', where: 'synced = 0');
    if (rows.isEmpty) return;
    final batch = rows.map((row) {
      final r = Map<String, dynamic>.from(row);
      r['centre_id'] = centreId;
      r.remove('synced');
      return r;
    }).toList();
    await _client.from('incentive_ledger').upsert(batch, onConflict: 'id');
    for (final row in rows) {
      await _db.update(
          'incentive_ledger', {'synced': 1}, 'id = ?', [row['id']]);
    }
  }

  // ── Pull helpers ─────────────────────────────────────────────────────────

  Future<void> _pullBills(String centreId) async {
    final lastPull = await _getLastPullTime('bills');
    final List<Map<String, dynamic>> remote;
    if (lastPull != null) {
      remote = await _client
          .from('bills')
          .select()
          .eq('centre_id', centreId)
          .gte('updated_at', lastPull)
          .order('created_at', ascending: false)
          .limit(500);
    } else {
      remote = await _client
          .from('bills')
          .select()
          .eq('centre_id', centreId)
          .order('created_at', ascending: false)
          .limit(500);
    }
    for (final row in remote) {
      final r = _toBillSqlite(row);
      await _db.insert('bills', r);
    }
    await _setLastPullTime('bills');
  }

  Future<void> _pullReferralDoctors(String centreId) async {
    final remote = await _client
        .from('referral_doctors')
        .select()
        .eq('centre_id', centreId);
    for (final row in remote) {
      final r = Map<String, dynamic>.from(row);
      r['is_active'] = r['is_active'] == true ? 1 : 0;
      r['synced'] = 1;
      r.remove('centre_id');
      r.remove('updated_at');
      await _db.insert('referral_doctors', r);
    }
  }

  Future<void> _pullScanTypes() async {
    final remote =
        await _client.from('scan_types').select();
    for (final row in remote) {
      final r = Map<String, dynamic>.from(row);
      r['is_active'] = r['is_active'] == true ? 1 : 0;
      r['synced'] = 1;
      r.remove('updated_at');
      await _db.insert('scan_types', r);
    }
  }

  Future<void> _pullDoctorScanIncentives(String centreId) async {
    final remote = await _client
        .from('doctor_scan_incentives')
        .select()
        .eq('centre_id', centreId);
    for (final row in remote) {
      final r = Map<String, dynamic>.from(row);
      r['synced'] = 1;
      r.remove('centre_id');
      r.remove('updated_at');
      await _db.insert('doctor_scan_incentives', r);
    }
  }

  Map<String, dynamic> _toBillSqlite(Map<String, dynamic> row) {
    final r = Map<String, dynamic>.from(row);
    r['worklist_pushed'] = r['worklist_pushed'] == true ? 1 : 0;
    r['scan_completed'] = r['scan_completed'] == true ? 1 : 0;
    r['synced'] = 1;
    r.remove('centre_id');
    r.remove('updated_at');
    return r;
  }

  // ── Persistence helpers ───────────────────────────────────────────────────

  Future<String?> _getLastPullTime(String table) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_pull_$table');
  }

  Future<void> _setLastPullTime(String table) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'last_pull_$table', DateTime.now().toIso8601String());
  }

  Future<void> _saveSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync', DateTime.now().toIso8601String());
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _connectivitySub?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
