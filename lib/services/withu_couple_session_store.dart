import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WithuCoupleSession {
  final String username;
  final String password;
  final String sessionId;
  final String? deviceToken;
  final String csrfToken;

  const WithuCoupleSession({
    required this.username,
    required this.password,
    required this.sessionId,
    required this.csrfToken,
    this.deviceToken,
  });

  bool get isUsable =>
      username.trim().isNotEmpty &&
      sessionId.trim().isNotEmpty &&
      csrfToken.trim().isNotEmpty;

  String get cookieHeader {
    final parts = ['PHPSESSID=$sessionId'];
    final device = deviceToken?.trim();
    if (device != null && device.isNotEmpty) {
      parts.add('withu_device=$device');
    }
    return parts.join('; ');
  }

  WithuCoupleSession copyWith({
    String? username,
    String? password,
    String? sessionId,
    String? deviceToken,
    String? csrfToken,
  }) {
    return WithuCoupleSession(
      username: username ?? this.username,
      password: password ?? this.password,
      sessionId: sessionId ?? this.sessionId,
      deviceToken: deviceToken ?? this.deviceToken,
      csrfToken: csrfToken ?? this.csrfToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WithuCoupleSession &&
      other.username == username &&
      other.password == password &&
      other.sessionId == sessionId &&
      other.deviceToken == deviceToken &&
      other.csrfToken == csrfToken;

  @override
  int get hashCode =>
      Object.hash(username, password, sessionId, deviceToken, csrfToken);
}

abstract class WithuCoupleSecureStorage {
  const WithuCoupleSecureStorage();

  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterWithuCoupleSecureStorage extends WithuCoupleSecureStorage {
  const FlutterWithuCoupleSecureStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage;

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class WithuCoupleSessionStore {
  static const String _usernameKey = 'withu_couple_username';
  static const String _passwordKey = 'withu_couple_password';
  static const String _sessionIdKey = 'withu_couple_phpsessid';
  static const String _deviceTokenKey = 'withu_couple_device';
  static const String _csrfTokenKey = 'withu_couple_csrf_token';

  const WithuCoupleSessionStore({WithuCoupleSecureStorage? storage})
    : _storage = storage ?? const FlutterWithuCoupleSecureStorage();

  final WithuCoupleSecureStorage _storage;

  Future<WithuCoupleSession?> load() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    final sessionId = await _storage.read(key: _sessionIdKey);
    final deviceToken = await _storage.read(key: _deviceTokenKey);
    final csrfToken = await _storage.read(key: _csrfTokenKey);
    if (username == null ||
        password == null ||
        sessionId == null ||
        csrfToken == null) {
      return null;
    }
    return WithuCoupleSession(
      username: username,
      password: password,
      sessionId: sessionId,
      deviceToken: deviceToken,
      csrfToken: csrfToken,
    );
  }

  Future<void> save(WithuCoupleSession session) async {
    await _storage.write(key: _usernameKey, value: session.username);
    await _storage.write(key: _passwordKey, value: session.password);
    await _storage.write(key: _sessionIdKey, value: session.sessionId);
    await _storage.write(key: _csrfTokenKey, value: session.csrfToken);
    if (session.deviceToken == null || session.deviceToken!.trim().isEmpty) {
      await _storage.delete(key: _deviceTokenKey);
    } else {
      await _storage.write(key: _deviceTokenKey, value: session.deviceToken!);
    }
  }

  Future<void> clear() async {
    for (final key in [
      _usernameKey,
      _passwordKey,
      _sessionIdKey,
      _deviceTokenKey,
      _csrfTokenKey,
    ]) {
      await _storage.delete(key: key);
    }
  }
}
