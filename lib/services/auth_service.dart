import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/auth/app_centre.dart';

class AuthService extends ChangeNotifier {
  static const _prefDeviceId = 'device_id';
  static const _prefCentreId = 'centre_id';
  static const _prefCentreName = 'centre_name';
  static const _prefCentreCode = 'centre_code';

  final _client = Supabase.instance.client;

  String? _centreId;
  String? _centreName;
  String? _centreCode;
  String? _deviceId;
  int _activeDeviceCount = 0;
  Timer? _heartbeatTimer;

  String? get centreId => _centreId;
  String? get centreName => _centreName;
  String? get centreCode => _centreCode;
  int get activeDeviceCount => _activeDeviceCount;
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserEmail => _client.auth.currentUser?.email;
  bool get isLoggedIn => _client.auth.currentUser != null && _centreId != null;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _centreId = prefs.getString(_prefCentreId);
    _centreName = prefs.getString(_prefCentreName);
    _centreCode = prefs.getString(_prefCentreCode);
    _deviceId = prefs.getString(_prefDeviceId);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_prefDeviceId, _deviceId!);
    }
    if (isLoggedIn) {
      _startHeartbeat();
    }
    notifyListeners();
  }

  Future<List<AppCentre>> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    return _fetchCentres();
  }

  /// Registers a new account. Returns true if the user is immediately signed in
  /// (email confirmation disabled), false if they must confirm their email first.
  Future<bool> signUp(String email, String password) async {
    final res = await _client.auth.signUp(email: email, password: password);
    final signedIn = res.session != null;
    if (signedIn) notifyListeners();
    return signedIn;
  }

  /// Creates a new centre owned by the currently signed-in user and returns it.
  /// Requires an active session (see [signUp]).
  Future<AppCentre> createCentre(String name, String code) async {
    final result = await _client.rpc(
      'create_centre_for_current_user',
      params: {'p_name': name, 'p_code': code},
    );
    final row = (result as List).first as Map<String, dynamic>;
    return AppCentre(
      id: row['id'] as String,
      name: row['name'] as String,
      code: row['code'] as String,
      role: row['role'] as String,
    );
  }

  /// Joins an existing centre by its code, adding the current user as staff,
  /// and returns it. Requires an active session (see [signUp]).
  Future<AppCentre> joinCentre(String code) async {
    final result = await _client.rpc(
      'join_centre_by_code',
      params: {'p_code': code},
    );
    final row = (result as List).first as Map<String, dynamic>;
    return AppCentre(
      id: row['id'] as String,
      name: row['name'] as String,
      code: row['code'] as String,
      role: row['role'] as String,
    );
  }

  /// Sends a password-recovery email to [email]. With the Supabase "Reset
  /// Password" email template configured to show {{ .Token }}, this delivers a
  /// 6-digit code the user enters via [confirmPasswordReset].
  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  /// Changes the signed-in user's password after verifying [currentPassword].
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) {
      throw Exception('Not signed in');
    }
    // Re-authenticate to confirm the current password is correct.
    await _client.auth
        .signInWithPassword(email: email, password: currentPassword);
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Verifies the emailed recovery [code] and sets a new password.
  /// The temporary recovery session is cleared afterwards so the user signs in
  /// fresh with the new password.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.recovery,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    await _client.auth.signOut();
  }

  /// Returns everyone in the current centre (email + role).
  Future<List<CentreMemberInfo>> listCentreMembers() async {
    if (_centreId == null) return [];
    final result = await _client.rpc(
      'list_centre_members',
      params: {'p_centre_id': _centreId},
    );
    return (result as List).map((r) {
      final row = r as Map<String, dynamic>;
      return CentreMemberInfo(
        userId: row['user_id'] as String,
        email: row['email'] as String? ?? '',
        role: row['role'] as String? ?? 'staff',
      );
    }).toList();
  }

  Future<List<AppCentre>> _fetchCentres() async {
    final response = await _client
        .from('centre_members')
        .select('role, centres(id, name, code)');
    return response.map<AppCentre>((row) {
      final c = row['centres'] as Map<String, dynamic>;
      return AppCentre(
        id: c['id'] as String,
        name: c['name'] as String,
        code: c['code'] as String,
        role: row['role'] as String,
      );
    }).toList();
  }

  Future<void> selectCentre(AppCentre centre) async {
    final prefs = await SharedPreferences.getInstance();
    _centreId = centre.id;
    _centreName = centre.name;
    _centreCode = centre.code;
    await prefs.setString(_prefCentreId, centre.id);
    await prefs.setString(_prefCentreName, centre.name);
    await prefs.setString(_prefCentreCode, centre.code);
    await _registerDeviceSession();
    _startHeartbeat();
    notifyListeners();
  }

  Future<void> _registerDeviceSession() async {
    if (_centreId == null || _deviceId == null) return;
    try {
      await _client.from('device_sessions').upsert({
        'id': _deviceId,
        'user_id': _client.auth.currentUser!.id,
        'centre_id': _centreId,
        'device_name': _deviceName,
        'last_seen': DateTime.now().toIso8601String(),
        'is_active': true,
      }, onConflict: 'id');
      await _updateDeviceCount();
    } catch (_) {}
  }

  String get _deviceName {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'Unknown PC';
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _sendHeartbeat();
    });
    _updateDeviceCount();
  }

  Future<void> _sendHeartbeat() async {
    if (_deviceId == null) return;
    try {
      await _client.from('device_sessions').update({
        'last_seen': DateTime.now().toIso8601String(),
        'is_active': true,
      }).eq('id', _deviceId!);
      await _updateDeviceCount();
    } catch (_) {}
  }

  Future<void> _updateDeviceCount() async {
    if (_centreId == null) return;
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
      final response = await _client
          .from('device_sessions')
          .select('id')
          .eq('centre_id', _centreId!)
          .eq('is_active', true)
          .gte('last_seen', cutoff);
      _activeDeviceCount = (response as List).length;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> signOut() async {
    _heartbeatTimer?.cancel();
    if (_deviceId != null) {
      try {
        await _client
            .from('device_sessions')
            .update({'is_active': false}).eq('id', _deviceId!);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefCentreId);
    await prefs.remove(_prefCentreName);
    await prefs.remove(_prefCentreCode);
    _centreId = null;
    _centreName = null;
    _centreCode = null;
    _activeDeviceCount = 0;
    await _client.auth.signOut();
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}

/// A member of a centre, as returned by [AuthService.listCentreMembers].
class CentreMemberInfo {
  final String userId;
  final String email;
  final String role;

  const CentreMemberInfo({
    required this.userId,
    required this.email,
    required this.role,
  });
}
