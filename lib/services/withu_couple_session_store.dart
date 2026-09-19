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
  /// 服务端把性别编码进角色槽位（男=user1，女=user2），登录与 bootstrap
  /// 载荷里都带 role，因此客户端不必新增接口即可判定双方性别。
  static const String genderMale = 'male';
  static const String genderFemale = 'female';

  /// 由角色槽位推出性别；未知角色（如管理员）返回空串。
  static String genderFromRole(Object? role) {
    switch (role?.toString().trim()) {
      case 'user1':
        return genderMale;
      case 'user2':
        return genderFemale;
      default:
        return '';
    }
  }

  final String userNickname;
  final String partnerNickname;
  final String? userAvatar;
  final String? partnerAvatar;

  /// 空串表示未知：旧版本缓存或未登录过，此时桌面卡片沿用默认配色。
  final String userGender;
  final String partnerGender;

  const WithuCoupleDisplayProfile({
    required this.userNickname,
    required this.partnerNickname,
    this.userAvatar,
    this.partnerAvatar,
    this.userGender = '',
    this.partnerGender = '',
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
  static const String _userGenderKey = 'withu_couple_user_gender';
  static const String _partnerGenderKey = 'withu_couple_partner_gender';

  /// 旧版本曾把登录密码一并写入安全存储。服务端登录后会下发
  /// withu_device 可信设备 Cookie，PHP 会话过期时凭它即可自动恢复会话，
  /// 密码在客户端从未被读取；读取会话时顺手清掉历史遗留值。
  static const String _legacyPasswordKey = 'withu_couple_password';

  const WithuCoupleSessionStore({WithuCoupleSecureStorage? storage})
    : _storage = storage ?? const FlutterWithuCoupleSecureStorage();

  final WithuCoupleSecureStorage _storage;

  /// 凭证写入代次：每次 [save] / [clear] 开始前同步自增。
  ///
  /// 只用于判断「读取期间是否有新的登录/换号落盘」，见 [clearIfSession]。
  /// 刻意用一个同步整数，而不是把读写串行化的 Future 队列：队列会把跨
  /// FakeAsync 与真实异步 zone 的微任务串在一起，只要有一个操作没跑完，
  /// 之后所有读写都会永久阻塞（widget 测试里立刻就会死锁）。
  static int _writeEpoch = 0;

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
    _writeEpoch++;
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
    final userGender = await _storage.read(key: _userGenderKey);
    final partnerGender = await _storage.read(key: _partnerGenderKey);
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
      userGender: _normalizeGender(userGender),
      partnerGender: _normalizeGender(partnerGender),
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
    await _writeGender(key: _userGenderKey, value: profile.userGender);
    await _writeGender(key: _partnerGenderKey, value: profile.partnerGender);
  }

  static String _normalizeGender(String? value) {
    return switch (value?.trim().toLowerCase()) {
      WithuCoupleDisplayProfile.genderMale =>
        WithuCoupleDisplayProfile.genderMale,
      WithuCoupleDisplayProfile.genderFemale =>
        WithuCoupleDisplayProfile.genderFemale,
      _ => '',
    };
  }

  Future<void> _writeGender({required String key, required String value}) async {
    final normalized = _normalizeGender(value);
    if (normalized.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: normalized);
    }
  }

  Future<void> clear() async {
    _writeEpoch++;
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
      _userGenderKey,
      _partnerGenderKey,
    ]) {
      await _storage.delete(key: key);
    }
  }

  /// 仅当存储里的会话仍是 [session] 时才清空。
  ///
  /// 401 针对的是某一个具体会话：请求在途时用户可能已经重新登录甚至换了账号，
  /// 此时存储里是新凭证，按旧会话的 401 去 [clear] 会把新登录直接删掉。
  ///
  /// 两步判定都是同步完成的：先比会话本身，再比 [_writeEpoch]（读取期间是否有人
  /// 写入新凭证）。这样「新登录刚落盘就被旧会话的 401 删掉」不会发生；极端情况下
  /// 仍可能与一次写入交错（表现为半份凭证，需要重新登录），这里不做串行化是因为
  /// 跨 zone 的 Future 队列一旦卡住会让之后所有读写永久阻塞。
  Future<void> clearIfSession(WithuCoupleSession session) async {
    final epoch = _writeEpoch;
    final current = await load();
    if (current != null && current != session) {
      return;
    }
    if (_writeEpoch != epoch) {
      return;
    }
    await clear();
  }
}
