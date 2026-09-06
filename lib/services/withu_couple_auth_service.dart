import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_http_client.dart';
import 'withu_couple_config.dart';
import 'withu_couple_session_store.dart';

class WithuCoupleApiException implements Exception {
  final String code;
  final String? serverMessage;

  const WithuCoupleApiException(this.code, {this.serverMessage});

  @override
  String toString() =>
      'WithuCoupleApiException: $code${serverMessage == null ? '' : ': $serverMessage'}';
}

class WithuCoupleUser {
  final int id;
  final String username;
  final String nickname;
  final String role;
  final String? avatar;

  const WithuCoupleUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.role,
    this.avatar,
  });

  factory WithuCoupleUser.fromJson(Map<String, dynamic> json) {
    return WithuCoupleUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      role: json['role'] as String? ?? '',
      avatar: json['avatar'] as String?,
    );
  }

  String get displayName {
    final trimmedNickname = nickname.trim();
    return trimmedNickname.isEmpty ? username : trimmedNickname;
  }
}

class WithuCoupleLoginResult {
  final WithuCoupleSession session;
  final WithuCoupleUser user;
  final WithuCoupleUser? partner;

  const WithuCoupleLoginResult({
    required this.session,
    required this.user,
    this.partner,
  });
}

class WithuCoupleAuthService {
  WithuCoupleAuthService({
    http.Client? client,
    WithuCoupleConfigStore? configStore,
    WithuCoupleSessionStore? sessionStore,
  }) : _client = client ?? createAppHttpClient(),
       _configStore = configStore ?? const WithuCoupleConfigStore(),
       _sessionStore = sessionStore ?? const WithuCoupleSessionStore() {
    _ownsClient = client == null && !isSharedAppHttpClient(_client);
  }

  final http.Client _client;
  final WithuCoupleConfigStore _configStore;
  final WithuCoupleSessionStore _sessionStore;
  late final bool _ownsClient;
  WithuCoupleSession? _cachedSession;

  Future<WithuCoupleConfig> loadConfig() => _configStore.load();

  Future<WithuCoupleSession?> loadSession() async {
    return _cachedSession ??= await _sessionStore.load();
  }

  Future<WithuCoupleLoginResult> connect({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    if (baseUrl.trim().isEmpty ||
        normalizedUsername.isEmpty ||
        password.isEmpty) {
      throw const WithuCoupleApiException('withu_missing_credentials');
    }

    final config = WithuCoupleConfig(baseUrl: baseUrl.trim());
    final uri = config.apiUri;
    final result = await _request(
      uri: _actionUri(uri, 'login'),
      method: 'POST',
      body: {'username': normalizedUsername, 'password': password},
    );
    final payload = result.payload;

    final rawUser = payload['user'];
    final csrfToken = payload['csrf_token'] as String?;
    if (rawUser is! Map || csrfToken == null || csrfToken.trim().isEmpty) {
      throw const WithuCoupleApiException('withu_invalid_response');
    }

    final sessionId = _cookieValue(result.response, 'PHPSESSID');
    if (sessionId == null || sessionId.isEmpty) {
      throw const WithuCoupleApiException('withu_session_cookie_missing');
    }

    // 密码只用于本次登录请求；会话过期后由服务端凭 withu_device
    // 可信设备 Cookie 自动恢复，不落盘。
    final session = WithuCoupleSession(
      username: normalizedUsername,
      sessionId: sessionId,
      deviceToken: _cookieValue(result.response, 'withu_device'),
      csrfToken: csrfToken.trim(),
    );
    await _configStore.save(config);
    await _sessionStore.save(session);
    _cachedSession = session;

    final user = WithuCoupleUser.fromJson(Map<String, dynamic>.from(rawUser));
    final rawPartner = payload['partner'];
    final partner = rawPartner is Map
        ? WithuCoupleUser.fromJson(Map<String, dynamic>.from(rawPartner))
        : null;
    return WithuCoupleLoginResult(
      session: session,
      user: user,
      partner: partner,
    );
  }

  Future<Map<String, dynamic>> getJson(String action) async {
    final session = await _requireSession();
    final config = await _configStore.load();
    return (await _request(
      uri: _actionUri(config.apiUri, action),
      method: 'GET',
      session: session,
    )).payload;
  }

  Future<Map<String, dynamic>> postJson(
    String action,
    Map<String, dynamic> body,
  ) async {
    final session = await _requireSession();
    final config = await _configStore.load();
    return (await _request(
      uri: _actionUri(config.apiUri, action),
      method: 'POST',
      session: session,
      body: {...body, '_token': session.csrfToken},
    )).payload;
  }

  Future<void> disconnect() async {
    final session = await loadSession();
    if (session != null) {
      try {
        final config = await _configStore.load();
        await _request(
          uri: _actionUri(config.apiUri, 'logout'),
          method: 'POST',
          session: session,
          body: {'_token': session.csrfToken},
        );
      } catch (_) {
        // A stale server session must not keep local credentials alive.
      }
    }
    await _sessionStore.clear();
    _cachedSession = null;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<({http.Response response, Map<String, dynamic> payload})> _request({
    required Uri uri,
    required String method,
    WithuCoupleSession? session,
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (session != null) {
      request.headers['Cookie'] = session.cookieHeader;
      if (method == 'POST') {
        request.headers['X-CSRF-Token'] = session.csrfToken;
      }
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await _client.send(request);
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw const WithuCoupleApiException('withu_network_failed');
    }
    Map<String, dynamic> payload;
    try {
      final text = utf8.decode(response.bodyBytes);
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException();
      }
      payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const WithuCoupleApiException('withu_invalid_response');
    }

    if (response.statusCode != 200) {
      throw WithuCoupleApiException(
        _statusCode(response.statusCode, action: _queryAction(uri)),
        serverMessage: payload['message'] as String?,
      );
    }
    if (payload['success'] != true) {
      throw WithuCoupleApiException(
        'withu_request_failed',
        serverMessage: payload['message'] as String?,
      );
    }

    if (session != null) {
      await _updateSessionFromResponse(session, response, payload);
    }
    return (response: response, payload: payload);
  }

  Future<WithuCoupleSession> _requireSession() async {
    final session = await loadSession();
    if (session == null || !session.isUsable) {
      throw const WithuCoupleApiException('withu_couple_not_connected');
    }
    return session;
  }

  Future<void> _updateSessionFromResponse(
    WithuCoupleSession session,
    http.Response response,
    Map<String, dynamic> payload,
  ) async {
    if (payload['logged_in'] == false) {
      await _sessionStore.clear();
      _cachedSession = null;
      throw const WithuCoupleApiException('withu_session_expired');
    }

    final updatedSession = session.copyWith(
      sessionId: _cookieValue(response, 'PHPSESSID'),
      deviceToken: _cookieValue(response, 'withu_device'),
      csrfToken: (payload['csrf_token'] as String?)?.trim(),
    );
    if (updatedSession.isUsable && updatedSession != session) {
      await _sessionStore.save(updatedSession);
      _cachedSession = updatedSession;
    }
  }

  Uri _actionUri(Uri base, String action) {
    return base.replace(
      queryParameters: {...base.queryParameters, 'action': action},
    );
  }

  String _queryAction(Uri uri) => uri.queryParameters['action'] ?? '';

  String _statusCode(int statusCode, {required String action}) {
    if (statusCode == 401) {
      return action == 'login' ? 'withu_auth_failed' : 'withu_session_expired';
    }
    if (statusCode == 403) {
      return 'withu_couple_account_required';
    }
    return 'withu_http_failed';
  }

  String? _cookieValue(http.Response response, String name) {
    String? raw;
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        raw = entry.value;
        break;
      }
    }
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final match = RegExp(
      '(?:^|[,;]\\s*)$name=([^;]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    return match?.group(1)?.trim();
  }
}
