import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/withu_couple_auth_service.dart';
import '../services/withu_couple_avatar_cache.dart';
import '../services/withu_couple_config.dart';
import '../services/withu_couple_session_store.dart';

/// withU 情侣登录态。
///
/// 有本地凭证 ≠ 已登录：凭证可能已经过期，服务端也可能暂时问不到。这两件事
/// 对界面含义完全不同（一个该显示登录提示，一个该显示缓存的昵称），所以这里
/// 用显式状态而不是若干个布尔量表示。
enum WithuCoupleLoginStatus {
  /// 本机没有可用的 withU 凭证。
  signedOut,

  /// 有本地凭证，正在向服务端确认；此间展示缓存的昵称/头像。
  restoring,

  /// 服务端已确认会话有效。
  connected,

  /// 有本地凭证，但服务端暂时无法确认（离线、5xx）。展示缓存资料，
  /// 不宣称已登录，也不清凭证——网络恢复后即可转回 [connected]。
  staleOffline,
}

/// withU 情侣登录态：首页情侣标题区（昵称 / 爱心 / 登录提示）的数据源，
/// 也是登录、退出这两个状态变更的唯一入口。
///
/// 只负责「会话是否存在 + 双方昵称展示」。凭证读写复用
/// [WithuCoupleAuthService]，不复制认证逻辑。
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

  /// 全应用共享的认证服务。UI（登录弹窗、设置页、情侣中心）借用这一份，
  /// 不要自己 new：登录与退出都要立刻反映到首页登录态上。
  /// 借用方**不得**调用 [WithuCoupleAuthService.dispose]。
  WithuCoupleAuthService get authService => _authService;

  bool _isRestoring = false;
  bool _restorePending = false;
  bool _disposed = false;
  bool _ownsAvatarCache = false;
  int _avatarRefreshGeneration = 0;

  /// 最近一次已知的情侣资料（服务端下发或本地缓存）。退出登录会清掉：
  /// 不能让上一个账号的昵称留在内存里被后续的离线兜底当成自己的资料。
  WithuCoupleDisplayProfile? _lastCachedProfile;

  /// [signOutLocally] 捕获、待 [completeServerLogout] 注销的服务端会话。
  WithuCoupleSession? _pendingServerLogout;

  /// 登录态代次：退出登录（或开启新一轮恢复）会 +1，让在途的恢复结果作废，
  /// 避免它们拿着旧凭证把刚退出的状态又写回「已登录」。
  int _stateEpoch = 0;

  WithuCoupleLoginStatus _status = WithuCoupleLoginStatus.signedOut;

  /// 当前登录态。
  WithuCoupleLoginStatus get status => _status;

  /// 原始凭证会话；null 表示本机没有 withU 凭证。
  WithuCoupleSession? session;

  /// 服务端是否已确认登录（[WithuCoupleLoginStatus.connected]）。
  bool get isLoggedIn => _status == WithuCoupleLoginStatus.connected;

  /// 本地是否有可展示的情侣资料（凭证或缓存昵称）：首页据此决定显示情侣标题
  /// 还是「未登录 · 点击登录」。它**不**代表服务端已确认，判断登录请用
  /// [isLoggedIn]。
  bool get hasStoredSession => _status != WithuCoupleLoginStatus.signedOut;

  /// 是否正在恢复会话。
  bool get isRestoring => _isRestoring;

  /// 仅测试使用：直接落定登录态，免得为了构造某个状态搭一整套存储与网络。
  @visibleForTesting
  void debugSetStatus(WithuCoupleLoginStatus value) {
    _status = value;
  }

  /// 登录态返回的用户昵称；取不到时为空串，由 UI 退回本地课表名/本地化文案。
  String userNickname = '';

  /// 登录态返回的对方昵称；取不到时为空串，由 UI 退回本地化文案。
  String partnerNickname = '';

  /// withU 服务地址；相对路径头像需要用它补全。
  String serverBaseUrl = WithuCoupleConfig.defaultBaseUrl;

  /// 登录用户头像地址；空值时由 UI 使用服务器默认头像。
  String? userAvatar;

  /// 对方头像地址；空值时由 UI 使用服务器默认头像。
  String? partnerAvatar;

  /// Local, immediately renderable copies of the avatars.
  String? userAvatarPath;

  String? partnerAvatarPath;

  /// 恢复会话：读本地凭证 → 用缓存资料先铺界面 → bootstrap 校验 → 落定状态。
  ///
  /// 任何失败都不向调用方抛出：会话过期回到未登录，网络失败退到
  /// [WithuCoupleLoginStatus.staleOffline]。
  ///
  /// 并发调用不会丢：恢复进行中再来的调用会排队，等本轮结束后按最新的本地
  /// 凭证再跑一次，而不是静默丢弃。
  Future<void> restoreSession() async {
    if (_disposed) {
      return;
    }
    if (_isRestoring) {
      _restorePending = true;
      return;
    }
    _isRestoring = true;
    _stateEpoch++;
    try {
      do {
        _restorePending = false;
        await _restoreOnce();
      } while (_restorePending && !_disposed);
    } finally {
      _isRestoring = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _restoreOnce() async {
    final epoch = _stateEpoch;
    final storedSession = await _loadLocalState(epoch);
    if (_stale(epoch) || storedSession == null) {
      return;
    }

    try {
      final payload = await _authService.getJson('bootstrap');
      if (_stale(epoch)) {
        return;
      }
      if (payload['logged_in'] != true) {
        _applySignedOut();
        return;
      }
      await _applyBootstrapPayload(payload);
      if (_stale(epoch)) {
        return;
      }
      _status = WithuCoupleLoginStatus.connected;
      unawaited(_refreshAvatars());
    } on WithuCoupleApiException catch (error) {
      if (_stale(epoch)) {
        return;
      }
      if (error.code == 'withu_session_expired') {
        _applySignedOut();
      } else {
        _status = WithuCoupleLoginStatus.staleOffline;
      }
    } catch (_) {
      if (!_stale(epoch)) {
        _status = WithuCoupleLoginStatus.staleOffline;
      }
    }
  }

  /// 读取本地凭证并把缓存资料铺到界面，返回可用会话（null 表示已回到未登录）。
  ///
  /// 先铺缓存资料是为了冷启动不闪「未登录」；此时状态是
  /// [WithuCoupleLoginStatus.restoring] 而不是已登录：一个已失效的会话不该让
  /// 首页先亮起情侣标题再掉回登录提示。
  ///
  /// 每个 await 之后都要复核 [epoch]：期间用户可能已经退出登录或换号，读取
  /// 前后跨越了那次变更的旧值不能落到界面上。
  Future<WithuCoupleSession?> _loadLocalState(int epoch) async {
    final storedSession = await _authService.loadSession();
    if (_stale(epoch)) {
      return null;
    }
    if (storedSession == null || !storedSession.isUsable) {
      _applySignedOut();
      return null;
    }

    final cachedProfile = await _authService.loadDisplayProfile();
    await _loadAvatarConfiguration();
    if (_stale(epoch)) {
      return null;
    }
    session = storedSession;
    _lastCachedProfile = cachedProfile;
    _applyCachedProfile(cachedProfile);
    _status = WithuCoupleLoginStatus.restoring;
    notifyListeners();

    await _applyCachedAvatarPaths(epoch);
    return storedSession;
  }

  /// 本轮的登录态是否已被更新的变更（退出登录 / 换号 / dispose）取代。
  bool _stale(int epoch) => _disposed || epoch != _stateEpoch;

  /// 本机立即退出登录：清空凭证与展示状态并通知界面，**不等服务端**。
  ///
  /// 服务端注销（吊销 withu_device 可信设备）由 [completeServerLogout] 接着做，
  /// 调用方可以先关掉界面再等它——退出登录因此不会卡在网络上。
  /// 若还要清课表同步点，见 `WithuCoupleTimetableService.forgetPartnerPullMarkers`。
  Future<void> signOutLocally() async {
    if (_disposed) {
      return;
    }
    // 先留下要注销的服务端会话：本地凭证马上就没了，之后就拿不到它了。
    _pendingServerLogout = await _authService.loadSession();
    _stateEpoch++;
    await _authService.clearLocalCredentials();
    if (_disposed) {
      return;
    }
    _applySignedOut();
    notifyListeners();
  }

  /// 尽力完成服务端注销，返回服务端是否确认；没有待注销的会话时返回 false。
  ///
  /// 拿不到确认意味着那台可信设备在服务端仍然有效，UI 需要提示用户。
  Future<bool> completeServerLogout() {
    final session = _pendingServerLogout;
    _pendingServerLogout = null;
    if (session == null) {
      return Future<bool>.value(false);
    }
    return _authService.notifyServerLogout(session);
  }

  /// 本地凭证刚被改动（登录成功）后同步登录态，**不访问网络**。
  ///
  /// 登录请求本身已经确认过身份，再补一次 bootstrap 只会拖慢界面，还可能因为
  /// 多出来的那次网络失败把刚登录的成功状态降级成「离线」，所以只重新读本地凭证。
  Future<void> refreshFromLocal() async {
    if (_disposed) {
      return;
    }
    final epoch = ++_stateEpoch;
    final storedSession = await _loadLocalState(epoch);
    if (_stale(epoch)) {
      return;
    }
    if (storedSession != null) {
      _status = WithuCoupleLoginStatus.connected;
      unawaited(_refreshAvatars());
    }
    notifyListeners();
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

  /// 性别取不到（旧服务端 / 非情侣角色）时保留缓存值，避免刷新把已知性别抹掉。
  String _genderOf(Object? raw, {required String fallback}) {
    if (raw is! Map) {
      return fallback;
    }
    final user = WithuCoupleUser.fromJson(Map<String, dynamic>.from(raw));
    final gender = WithuCoupleDisplayProfile.genderFromRole(user.role);
    return gender.isEmpty ? fallback : gender;
  }

  Future<void> _applyBootstrapPayload(Map<String, dynamic> payload) async {
    final cachedProfile = _lastCachedProfile;
    userNickname = _displayNameOf(
      payload['user'],
      fallback: cachedProfile?.userNickname ?? '',
    );
    partnerNickname = _displayNameOf(
      payload['partner'],
      fallback: cachedProfile?.partnerNickname ?? '',
    );
    userAvatar = _displayAvatarOf(payload['user']);
    partnerAvatar = _displayAvatarOf(payload['partner']);
    final profile = WithuCoupleDisplayProfile(
      userNickname: userNickname,
      partnerNickname: partnerNickname,
      userAvatar: userAvatar,
      partnerAvatar: partnerAvatar,
      userGender: _genderOf(
        payload['user'],
        fallback: cachedProfile?.userGender ?? '',
      ),
      partnerGender: _genderOf(
        payload['partner'],
        fallback: cachedProfile?.partnerGender ?? '',
      ),
    );
    _lastCachedProfile = profile;
    await _authService.saveDisplayProfile(profile);
  }

  /// 回到「本机没有凭证」：清掉内存里的缓存资料，否则上一个账号的昵称会在
  /// 后续「服务端问不到」的场景里被当成自己的展示出来。
  void _applySignedOut() {
    _lastCachedProfile = null;
    session = null;
    _status = WithuCoupleLoginStatus.signedOut;
    _applyCachedProfile(null);
    _avatarRefreshGeneration++;
  }

  /// 把缓存资料铺到界面字段；没有缓存时回到空串，由 UI 决定兜底文案。
  void _applyCachedProfile(WithuCoupleDisplayProfile? profile) {
    userNickname = profile?.userNickname ?? '';
    partnerNickname = profile?.partnerNickname ?? '';
    userAvatar = profile?.userAvatar;
    partnerAvatar = profile?.partnerAvatar;
    if (profile == null) {
      userAvatarPath = null;
      partnerAvatarPath = null;
    }
  }

  Future<void> _loadAvatarConfiguration() async {
    final config = await _authService.loadConfig();
    serverBaseUrl = config.baseUrl.trim().isEmpty
        ? WithuCoupleConfig.defaultBaseUrl
        : config.baseUrl.trim();
  }

  Future<void> _applyCachedAvatarPaths(int epoch) async {
    try {
      final paths = await Future.wait<String?>([
        _avatarCache.cachedPath(
          WithuCoupleAvatarCache.resolveUri(serverBaseUrl, userAvatar),
        ),
        _avatarCache.cachedPath(
          WithuCoupleAvatarCache.resolveUri(serverBaseUrl, partnerAvatar),
        ),
      ]);
      if (_stale(epoch)) {
        return;
      }
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
