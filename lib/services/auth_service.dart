import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static const _biometricKey = 'biometric_enabled';
  static const _cachePrefix = 'cache_';
  static String? _deviceInfo;

  static const String backendUrl = 'https://dlg3f2l3-3000.asse.devtunnels.ms';

  static Future<String> getDeviceInfo() async {
    if (_deviceInfo != null) return _deviceInfo!;
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        _deviceInfo = 'Android ${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        _deviceInfo = 'iOS ${info.name} ${info.model}';
      } else if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        _deviceInfo = 'Windows ${info.computerName} ${info.productName}';
      } else {
        _deviceInfo = '${Platform.operatingSystem} device';
      }
    } catch (_) {
      _deviceInfo = '${Platform.operatingSystem} device';
    }
    return _deviceInfo!;
  }

  static Future<Map<String, String>> authHeaders(String token,
      {Map<String, String> extra = const {}}) async {
    return {
      'Authorization': 'Bearer $token',
      'X-Device-Info': await getDeviceInfo(),
      ...extra,
    };
  }

  static Future<Map<String, String>> deviceHeaders(
      {Map<String, String> extra = const {}}) async {
    return {
      'X-Device-Info': await getDeviceInfo(),
      ...extra,
    };
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      final auth = LocalAuthentication();
      return await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateBiometric() async {
    try {
      final auth = LocalAuthentication();
      return await auth.authenticate(
        localizedReason: 'Gunakan sidik jari untuk masuk ke Inventory BKM',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<void> saveJsonCache(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cachePrefix$key', jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'data': value,
    }));
  }

  static Future<Map<String, dynamic>?> getJsonCache(String key,
      {Duration maxAge = const Duration(minutes: 15)}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(decoded['savedAt']?.toString() ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt) > maxAge) {
        return null;
      }
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>?;
  }

  static Future<String?> getRole() async {
    final user = await getUser();
    return user?['role'] as String?;
  }

  static Future<String?> getUsername() async {
    final user = await getUser();
    return user?['username'] as String?;
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$backendUrl/api/auth/logout'),
          headers: await authHeaders(token),
        );
      } catch (_) {}
    }
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
