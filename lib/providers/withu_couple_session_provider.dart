import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/withu_couple_auth_service.dart';
import '../services/withu_couple_avatar_cache.dart';
import '../services/withu_couple_config.dart';
import '../services/withu_couple_session_store.dart';

/// withU 情侣登录态：首页情侣标题区（昵称 / 爱心 / 登录提示）的数据源。
///
/// 只负责「会话是否存在 + 双方昵称展示」。登录、退出和服务器配置继续由
/// 现有 WithuCouple 登录链路处理，这里通过 [WithuCoupleAuthService] 复用
/// 同一份凭证存储与网络栈，不复制认证逻辑。
class WithuCoupleSessionProvider extends ChangeNotifier {
  WithuCoupleSessionProvider({
    WithuCoupleAuthService? authService,
    WithuCoupleAvatarCache? avatarCache,
  }) : _authService = authService ?? WithuCoupleAuthService(),
       _avatarCache = avatarCache ?? WithuCoupleAvatarCache() {
    _ownsAvatarCache = avatarCache == null;
  }

  final WithuCoupleAuthService _authService;
  final WithuCoupleAvatarCache _avatarCache;

  WithuCoupleAuthService get authService => _authService;
  bool _isRestoring = false;
  bool _disposed = false;
  bool _ownsAvatarCache = false;
  int _avatarRefreshGeneration = 0;
  WithuCoupleDisplayProfile? _lastCachedProfile;

  /// 原始凭证会话；null 表示本机从未登录过 withU。
  WithuCoupleSession? session;

  /// 远端登录态是否有效（bootstrap 校验通过）。
  bool isLoggedIn = false;

  bool hasStoredSession = false;

  /// 是否正在恢复会话。
  bool get isRestoring => _isRestoring;

  /// 登录态返回的用户昵称；仅接口异常返回空字符串时兜底 "me"。
  String userNickname = 'me';

  /// 登录态返回的对方昵称；仅接口异常返回空字符串时兜底 "baby"。
  String partnerNickname = 'baby';

  /// withU 服务地址；相对路径头像需要用它补全。
  String serverBaseUrl = WithuCoupleConfig.defaultBaseUrl;

  /// 登录用户头像地址；空值时由 UI 使用服务器默认头像。
  String? userAvatar;

  /// 对方头像地址；空值时由 UI 使用服务器默认头像。
  String? partnerAvatar;

  /// Local, immediately renderable copies of the avatars.
  String? userAvatarPath;

  String? partnerAvatarPath;

  /// 启动或登录成功后恢复/刷新会话：读本地凭证 → bootstrap 登录态校验 →
  /// 保存双方展示昵称。任何失败都保持未登录态（登录提示照常显示），
  /// 不向调用方抛出。
  Future<void> restoreSession() async {
    if (_isRestoring) {
      return;
    }
    _isRestoring = true;
    try {
      final storedSession = await _authService.loadSession();
      session = storedSession;
      if (storedSession == null || !storedSession.isUsable) {
        _applyLoggedOut();
        return;
      }
      hasStoredSession = true;
      _lastCachedProfile = await _authService.loadDisplayProfile();
      await _loadAvatarConfiguration();
      final cachedProfile = _lastCachedProfile;
      if (cachedProfile != null) {
        userNickname = cachedProfile.userNickname;
        partnerNickname = cachedProfile.partnerNickname;
        userAvatar = cachedProfile.userAvatar;
        partnerAvatar = cachedProfile.partnerAvatar;
      }
      await _applyCachedAvatarPaths();
      isLoggedIn = true;
      notifyListeners();
      unawaited(_refreshAvatars());

      final payload = await _authService.getJson('bootstrap');
      if (payload['logged_in'] != true) {
        _applyLoggedOut();
        return;
      }
      isLoggedIn = true;
      userNickname = _displayNameOf(payload['user'], fallback: userNickname);
      partnerNickname = _displayNameOf(
        payload['partner'],
        fallback: partnerNickname,
      );
      userAvatar = _displayAvatarOf(payload['user']);
      partnerAvatar = _displayAvatarOf(payload['partner']);
      await _authService.saveDisplayProfile(
        WithuCoupleDisplayProfile(
          userNickname: userNickname,
          partnerNickname: partnerNickname,
          userAvatar: userAvatar,
          partnerAvatar: partnerAvatar,
        ),
      );
      unawaited(_refreshAvatars());
    } on WithuCoupleApiException catch (error) {
      if (error.code == 'withu_session_expired') {
        _applyLoggedOut();
      } else {
        _applyLoggedOut(preserveCachedProfile: true);
      }
    } catch (_) {
      _applyLoggedOut(preserveCachedProfile: true);
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  String _displayNameOf(Object? raw, {required String fallback}) {
    if (raw is! Map) {
      return fallback;
    }
    final user = WithuCoupleUser.fromJson(Map<String, dynamic>.from(raw));
    final nickname = user.nickname.trim();
    return nickname.isEmpty ? fallback : nickname;
  }

  String? _displayAvatarOf(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final user = WithuCoupleUser.fromJson(Map<String, dynamic>.from(raw));
    final avatar = user.avatar?.trim();
    return (avatar == null || avatar.isEmpty) ? null : avatar;
  }

  void _applyLoggedOut({bool preserveCachedProfile = false}) {
    isLoggedIn = false;
    hasStoredSession = preserveCachedProfile && _lastCachedProfile != null;
    final cachedProfile = _lastCachedProfile;
    if (hasStoredSession && cachedProfile != null) {
      userNickname = cachedProfile.userNickname;
      partnerNickname = cachedProfile.partnerNickname;
      userAvatar = cachedProfile.userAvatar;
      partnerAvatar = cachedProfile.partnerAvatar;
    } else {
      userNickname = 'me';
      partnerNickname = 'baby';
      userAvatarPath = null;
      partnerAvatarPath = null;
    }
    if (!preserveCachedProfile) {
      userAvatar = null;
      partnerAvatar = null;
    }
  }

  Future<void> _loadAvatarConfiguration() async {
    final config = await _authService.loadConfig();
    serverBaseUrl = config.baseUrl.trim().isEmpty
        ? WithuCoupleConfig.defaultBaseUrl
        : config.baseUrl.trim();
  }

  Future<void> _applyCachedAvatarPaths() async {
    try {
      final paths = await Future.wait<String?>([
        _avatarCache.cachedPath(
          WithuCoupleAvatarCache.resolveUri(serverBaseUrl, userAvatar),
        ),
        _avatarCache.cachedPath(
          WithuCoupleAvatarCache.resolveUri(serverBaseUrl, partnerAvatar),
        ),
      ]);
      if (paths[0] != null) {
        userAvatarPath = paths[0];
      }
      if (paths[1] != null) {
        partnerAvatarPath = paths[1];
      }
    } catch (_) {
      // A missing storage plugin must not turn a cached login into logged-out.
    }
  }

  Future<void> _refreshAvatars() async {
    final generation = ++_avatarRefreshGeneration;
    final results = await Future.wait<WithuCoupleAvatarCacheResult?>([
      _avatarCache.refresh(
        WithuCoupleAvatarCache.resolveUri(serverBaseUrl, userAvatar),
      ),
      _avatarCache.refresh(
        WithuCoupleAvatarCache.resolveUri(serverBaseUrl, partnerAvatar),
      ),
    ]);
    if (_disposed || generation != _avatarRefreshGeneration) {
      return;
    }

    var changed = false;
    final userPath = results[0]?.path;
    if (userPath != null &&
        (userAvatarPath != userPath || results[0]?.changed == true)) {
      userAvatarPath = userPath;
      changed = true;
    }
    final partnerPath = results[1]?.path;
    if (partnerPath != null &&
        (partnerAvatarPath != partnerPath || results[1]?.changed == true)) {
      partnerAvatarPath = partnerPath;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsAvatarCache) {
      _avatarCache.dispose();
    }
    _authService.dispose();
    super.dispose();
  }
}
