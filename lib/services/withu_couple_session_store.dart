import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WithuCoupleSession {
  final String username;
  final String sessionId;
  final String? deviceToken;
  final String csrfToken;

  const WithuCoupleSession({
    required this.username,
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
    String? sessionId,
    String? deviceToken,
    String? csrfToken,
  }) {
    return WithuCoupleSession(
      username: username ?? this.username,
      sessionId: sessionId ?? this.sessionId,
      deviceToken: deviceToken ?? this.deviceToken,
      csrfToken: csrfToken ?? this.csrfToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WithuCoupleSession &&
      other.username == username &&
      other.sessionId == sessionId &&
      other.deviceToken == deviceToken &&
      other.csrfToken == csrfToken;

  @override
  int get hashCode => Object.hash(username, sessionId, deviceToken, csrfToken);
}

class WithuCoupleDisplayProfile {
  final String userNickname;
  final String partnerNickname;
  final String? userAvatar;
  final String? partnerAvatar;

  const WithuCoupleDisplayProfile({
    required this.userNickname,
    required this.partnerNickname,
    this.userAvatar,
    this.partnerAvatar,
  });
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
  static const String _sessionIdKey = 'withu_couple_phpsessid';
  static const String _deviceTokenKey = 'withu_couple_device';
  static const String _csrfTokenKey = 'withu_couple_csrf_token';
  static const String _userNicknameKey = 'withu_couple_user_nickname';
  static const String _partnerNicknameKey = 'withu_couple_partner_nickname';
  static const String _userAvatarKey = 'withu_couple_user_avatar';
  static const String _partnerAvatarKey = 'withu_couple_partner_avatar';

  /// 旧版本曾把登录密码一并写入安全存储。服务端登录后会下发
  /// withu_device 可信设备 Cookie，PHP 会话过期时凭它即可自动恢复会话，
  /// 密码在客户端从未被读取；读取会话时顺手清掉历史遗留值。
  static const String _legacyPasswordKey = 'withu_couple_password';

  const WithuCoupleSessionStore({WithuCoupleSecureStorage? storage})
    : _storage = storage ?? const FlutterWithuCoupleSecureStorage();

  final WithuCoupleSecureStorage _storage;

  Future<WithuCoupleSession?> load() async {
    final username = await _storage.read(key: _usernameKey);
    final sessionId = await _storage.read(key: _sessionIdKey);
    final deviceToken = await _storage.read(key: _deviceTokenKey);
    final csrfToken = await _storage.read(key: _csrfTokenKey);
    await _storage.delete(key: _legacyPasswordKey);
    if (username == null || sessionId == null || csrfToken == null) {
      return null;
    }
    return WithuCoupleSession(
      username: username,
      sessionId: sessionId,
      deviceToken: deviceToken,
      csrfToken: csrfToken,
    );
  }

  Future<void> save(WithuCoupleSession session) async {
    await _storage.write(key: _usernameKey, value: session.username);
    await _storage.write(key: _sessionIdKey, value: session.sessionId);
    await _storage.write(key: _csrfTokenKey, value: session.csrfToken);
    if (session.deviceToken == null || session.deviceToken!.trim().isEmpty) {
      await _storage.delete(key: _deviceTokenKey);
    } else {
      await _storage.write(key: _deviceTokenKey, value: session.deviceToken!);
    }
  }

  Future<WithuCoupleDisplayProfile?> loadDisplayProfile() async {
    final userNickname = await _storage.read(key: _userNicknameKey);
    final partnerNickname = await _storage.read(key: _partnerNicknameKey);
    final userAvatar = (await _storage.read(key: _userAvatarKey))?.trim();
    final partnerAvatar = (await _storage.read(key: _partnerAvatarKey))?.trim();
    if (userNickname == null ||
        userNickname.trim().isEmpty ||
        partnerNickname == null ||
        partnerNickname.trim().isEmpty) {
      return null;
    }
    return WithuCoupleDisplayProfile(
      userNickname: userNickname.trim(),
      partnerNickname: partnerNickname.trim(),
      userAvatar: userAvatar?.isEmpty ?? true ? null : userAvatar,
      partnerAvatar: partnerAvatar?.isEmpty ?? true ? null : partnerAvatar,
    );
  }

  Future<void> saveDisplayProfile(WithuCoupleDisplayProfile profile) async {
    final userNickname = profile.userNickname.trim();
    final partnerNickname = profile.partnerNickname.trim();
    if (userNickname.isEmpty || partnerNickname.isEmpty) {
      return;
    }
    await _storage.write(key: _userNicknameKey, value: userNickname);
    await _storage.write(key: _partnerNicknameKey, value: partnerNickname);
    final userAvatar = profile.userAvatar?.trim();
    final partnerAvatar = profile.partnerAvatar?.trim();
    if (userAvatar == null || userAvatar.isEmpty) {
      await _storage.delete(key: _userAvatarKey);
    } else {
      await _storage.write(key: _userAvatarKey, value: userAvatar);
    }
    if (partnerAvatar == null || partnerAvatar.isEmpty) {
      await _storage.delete(key: _partnerAvatarKey);
    } else {
      await _storage.write(key: _partnerAvatarKey, value: partnerAvatar);
    }
  }

  Future<void> clear() async {
    for (final key in [
      _usernameKey,
      _legacyPasswordKey,
      _sessionIdKey,
      _deviceTokenKey,
      _csrfTokenKey,
      _userNicknameKey,
      _partnerNicknameKey,
      _userAvatarKey,
      _partnerAvatarKey,
    ]) {
      await _storage.delete(key: key);
    }
  }
}
