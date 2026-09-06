import 'package:flutter/foundation.dart';

import '../services/withu_couple_auth_service.dart';
import '../services/withu_couple_session_store.dart';

/// withU 情侣登录态：首页情侣标题区（昵称 / 爱心 / 登录提示）的数据源。
///
/// 只负责「会话是否存在 + 双方昵称展示」。登录、退出和服务器配置继续由
/// 现有 WithuCouple 登录链路处理，这里通过 [WithuCoupleAuthService] 复用
/// 同一份凭证存储与网络栈，不复制认证逻辑。
class WithuCoupleSessionProvider extends ChangeNotifier {
  WithuCoupleSessionProvider({WithuCoupleAuthService? authService})
    : _authService = authService ?? WithuCoupleAuthService();

  final WithuCoupleAuthService _authService;
  bool _isRestoring = false;

  /// 原始凭证会话；null 表示本机从未登录过 withU。
  WithuCoupleSession? session;

  /// 远端登录态是否有效（bootstrap 校验通过）。
  bool isLoggedIn = false;

  /// 是否正在恢复会话。
  bool get isRestoring => _isRestoring;

  /// 登录态返回的用户昵称；仅接口异常返回空字符串时兜底 "me"。
  String userNickname = 'me';

  /// 登录态返回的对方昵称；仅接口异常返回空字符串时兜底 "baby"。
  String partnerNickname = 'baby';

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
    } on WithuCoupleApiException {
      _applyLoggedOut();
    } catch (_) {
      _applyLoggedOut();
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

  void _applyLoggedOut() {
    isLoggedIn = false;
    userNickname = 'me';
    partnerNickname = 'baby';
  }

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
  }
}
