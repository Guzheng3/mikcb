import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/services/withu_couple_auth_service.dart';
import 'package:university_timetable/services/withu_couple_config.dart';
import 'package:university_timetable/services/withu_couple_session_store.dart';

/// 内存版安全存储：预置/清空 withU 凭证，避免测试触碰平台通道。
class _FakeSecureStorage extends WithuCoupleSecureStorage {
  _FakeSecureStorage([Map<String, String>? initial])
    : _values = initial ?? {};

  final Map<String, String> _values;

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}

Map<String, String> _seededSessionValues() => {
  'withu_couple_username': 'me',
  'withu_couple_phpsessid': 'session-id',
  'withu_couple_csrf_token': 'csrf-token',
};

/// 中文昵称必须走 UTF-8 字节：http.Response(String) 默认 Latin-1 编码，
/// 非 Latin-1 字符会在构造时直接抛异常。
http.Response _bootstrapResponse(Map<String, dynamic> payload) =>
    http.Response.bytes(
      utf8.encode(jsonEncode({'success': true, ...payload})),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  // restoreSession 会读 withU 配置（SharedPreferences），需要可用的绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // bootstrap 请求前会读 withU 配置，预置一个合法 baseUrl。
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
    });
  });

  test('no stored session stays logged out with nickname fallbacks', () async {
    final provider = WithuCoupleSessionProvider(
      authService: WithuCoupleAuthService(
        client: MockClient((request) async => http.Response('{}', 200)),
        sessionStore: WithuCoupleSessionStore(storage: _FakeSecureStorage()),
      ),
    );

    await provider.restoreSession();

    expect(provider.isLoggedIn, isFalse);
    expect(provider.isRestoring, isFalse);
    expect(provider.session, isNull);
    expect(provider.userNickname, 'me');
    expect(provider.partnerNickname, 'baby');
  });

  test('bootstrap with logged_in true exposes both nicknames', () async {
    final provider = WithuCoupleSessionProvider(
      authService: WithuCoupleAuthService(
        client: MockClient(
          (request) async => _bootstrapResponse({
            'logged_in': true,
            'user': {
              'id': 1,
              'username': 'me',
              'nickname': '小明',
              'role': 'user1',
            },
            'partner': {
              'id': 2,
              'username': 'her',
              'nickname': '小红',
              'role': 'user2',
            },
          }),
        ),
        sessionStore: WithuCoupleSessionStore(
          storage: _FakeSecureStorage(_seededSessionValues()),
        ),
      ),
    );

    await provider.restoreSession();

    expect(provider.isLoggedIn, isTrue);
    expect(provider.userNickname, '小明');
    expect(provider.partnerNickname, '小红');
    expect(provider.session, isNotNull);
  });

  test('bootstrap logged_in false falls back to logged out', () async {
    final storage = _FakeSecureStorage(_seededSessionValues());
    final provider = WithuCoupleSessionProvider(
      authService: WithuCoupleAuthService(
        client: MockClient(
          (request) async => _bootstrapResponse({'logged_in': false}),
        ),
        sessionStore: WithuCoupleSessionStore(storage: storage),
      ),
    );

    await provider.restoreSession();

    expect(provider.isLoggedIn, isFalse);
    expect(provider.userNickname, 'me');
    expect(provider.partnerNickname, 'baby');
    // 会话过期由认证服务清凭证，下次恢复自然回到未登录。
    expect(await storage.read(key: 'withu_couple_phpsessid'), isNull);
  });

  test('empty nickname from server keeps defensive fallback', () async {
    final provider = WithuCoupleSessionProvider(
      authService: WithuCoupleAuthService(
        client: MockClient(
          (request) async => _bootstrapResponse({
            'logged_in': true,
            'user': {'id': 1, 'username': 'me', 'nickname': '', 'role': 'user1'},
            'partner': null,
          }),
        ),
        sessionStore: WithuCoupleSessionStore(
          storage: _FakeSecureStorage(_seededSessionValues()),
        ),
      ),
    );

    await provider.restoreSession();

    expect(provider.isLoggedIn, isTrue);
    expect(provider.userNickname, 'me');
    expect(provider.partnerNickname, 'baby');
  });
}
