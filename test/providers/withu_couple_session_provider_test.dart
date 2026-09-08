import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/services/withu_couple_auth_service.dart';
import 'package:university_timetable/services/withu_couple_avatar_cache.dart';
import 'package:university_timetable/services/withu_couple_config.dart';
import 'package:university_timetable/services/withu_couple_session_store.dart';

/// 内存版安全存储：预置/清空 withU 凭证，避免测试触碰平台通道。
class _FakeSecureStorage extends WithuCoupleSecureStorage {
  _FakeSecureStorage([Map<String, String>? initial]) : _values = initial ?? {};

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

Map<String, String> _seededCachedProfileValues() => {
  ..._seededSessionValues(),
  'withu_couple_user_nickname': 'Cached Me',
  'withu_couple_partner_nickname': 'Cached Her',
};

Map<String, String> _seededCachedAvatarProfileValues() => {
  ..._seededCachedProfileValues(),
  'withu_couple_user_avatar': '/avatars/me.png',
  'withu_couple_partner_avatar': 'https://cdn.example.com/partner.png',
};

class _FakeAvatarCache extends WithuCoupleAvatarCache {
  _FakeAvatarCache({
    Map<Uri, String> cachedPaths = const {},
    Map<Uri, WithuCoupleAvatarCacheResult> refreshResults = const {},
  }) : _cachedPaths = Map.of(cachedPaths),
       _refreshResults = Map.of(refreshResults);

  final Map<Uri, String> _cachedPaths;
  final Map<Uri, WithuCoupleAvatarCacheResult> _refreshResults;
  final List<Uri> cacheLookups = <Uri>[];
  final List<Uri> refreshes = <Uri>[];

  @override
  Future<String?> cachedPath(Uri? uri) async {
    if (uri != null) {
      cacheLookups.add(uri);
    }
    return uri == null ? null : _cachedPaths[uri];
  }

  @override
  Future<WithuCoupleAvatarCacheResult?> refresh(Uri? uri) async {
    if (uri != null) {
      refreshes.add(uri);
    }
    return uri == null ? null : _refreshResults[uri];
  }
}

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
              'avatar': '/avatars/me.png',
            },
            'partner': {
              'id': 2,
              'username': 'her',
              'nickname': '小红',
              'role': 'user2',
              'avatar': 'https://cdn.example.com/her.jpg',
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
    expect(provider.serverBaseUrl, 'https://withu.example.com');
    expect(provider.userAvatar, '/avatars/me.png');
    expect(provider.partnerAvatar, 'https://cdn.example.com/her.jpg');
    expect(provider.session, isNotNull);
  });

  test('cached nicknames render before bootstrap finishes', () async {
    final bootstrap = Completer<http.Response>();
    final provider = WithuCoupleSessionProvider(
      authService: WithuCoupleAuthService(
        client: MockClient((request) async => bootstrap.future),
        sessionStore: WithuCoupleSessionStore(
          storage: _FakeSecureStorage(_seededCachedProfileValues()),
        ),
      ),
    );

    final restoring = provider.restoreSession();
    await pumpEventQueue();

    expect(provider.hasStoredSession, isTrue);
    expect(provider.isLoggedIn, isTrue);
    expect(provider.userNickname, 'Cached Me');
    expect(provider.partnerNickname, 'Cached Her');

    bootstrap.complete(
      _bootstrapResponse({
        'logged_in': true,
        'user': {
          'id': 1,
          'username': 'me',
          'nickname': 'Fresh Me',
          'role': 'user1',
        },
        'partner': {
          'id': 2,
          'username': 'her',
          'nickname': 'Fresh Her',
          'role': 'user2',
        },
      }),
    );
    await restoring;

    expect(provider.isLoggedIn, isTrue);
    expect(provider.userNickname, 'Fresh Me');
    expect(provider.partnerNickname, 'Fresh Her');
  });

  test(
    'cached avatar files render first and unchanged bytes stay quiet',
    () async {
      final userUri = Uri.parse('https://withu.example.com/avatars/me.png');
      final partnerUri = Uri.parse('https://cdn.example.com/partner.png');
      final cache = _FakeAvatarCache(
        cachedPaths: {
          userUri: '/cache/me-v1.png',
          partnerUri: '/cache/partner-v1.png',
        },
        refreshResults: {
          userUri: const WithuCoupleAvatarCacheResult(
            path: '/cache/me-v1.png',
            changed: false,
          ),
          partnerUri: const WithuCoupleAvatarCacheResult(
            path: '/cache/partner-v1.png',
            changed: false,
          ),
        },
      );
      final provider = WithuCoupleSessionProvider(
        authService: WithuCoupleAuthService(
          client: MockClient(
            (request) async => _bootstrapResponse({
              'logged_in': true,
              'user': {
                'id': 1,
                'username': 'me',
                'nickname': 'Fresh Me',
                'role': 'user1',
                'avatar': '/avatars/me.png',
              },
              'partner': {
                'id': 2,
                'username': 'her',
                'nickname': 'Fresh Her',
                'role': 'user2',
                'avatar': 'https://cdn.example.com/partner.png',
              },
            }),
          ),
          sessionStore: WithuCoupleSessionStore(
            storage: _FakeSecureStorage(_seededCachedAvatarProfileValues()),
          ),
        ),
        avatarCache: cache,
      );
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.restoreSession();
      await pumpEventQueue();

      expect(provider.userAvatarPath, '/cache/me-v1.png');
      expect(provider.partnerAvatarPath, '/cache/partner-v1.png');
      expect(cache.cacheLookups, containsAll(<Uri>[userUri, partnerUri]));
      expect(cache.refreshes, containsAll(<Uri>[userUri, partnerUri]));
      expect(notifications, 2);
    },
  );

  test(
    'fresh avatar bytes publish the new local file after bootstrap',
    () async {
      final freshUserUri = Uri.parse(
        'https://withu.example.com/avatars/new.png',
      );
      final cache = _FakeAvatarCache(
        cachedPaths: {},
        refreshResults: {
          freshUserUri: const WithuCoupleAvatarCacheResult(
            path: '/cache/me-v2.png',
            changed: true,
          ),
        },
      );
      final storage = _FakeSecureStorage({
        ..._seededCachedProfileValues(),
        'withu_couple_user_avatar': '/avatars/old.png',
        'withu_couple_partner_avatar': 'https://cdn.example.com/partner.png',
      });
      final provider = WithuCoupleSessionProvider(
        authService: WithuCoupleAuthService(
          client: MockClient(
            (request) async => _bootstrapResponse({
              'logged_in': true,
              'user': {
                'id': 1,
                'username': 'me',
                'nickname': 'Fresh Me',
                'role': 'user1',
                'avatar': '/avatars/new.png',
              },
              'partner': {
                'id': 2,
                'username': 'her',
                'nickname': 'Fresh Her',
                'role': 'user2',
                'avatar': 'https://cdn.example.com/partner.png',
              },
            }),
          ),
          sessionStore: WithuCoupleSessionStore(storage: storage),
        ),
        avatarCache: cache,
      );
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.restoreSession();
      await pumpEventQueue();

      expect(provider.userAvatar, '/avatars/new.png');
      expect(provider.userAvatarPath, '/cache/me-v2.png');
      expect(cache.refreshes, contains(freshUserUri));
      expect(
        await storage.read(key: 'withu_couple_user_avatar'),
        '/avatars/new.png',
      );
      expect(notifications, 3);
    },
  );

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
            'user': {
              'id': 1,
              'username': 'me',
              'nickname': '',
              'role': 'user1',
            },
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

  test('cached nicknames survive bootstrap connection failure', () async {
    final provider = WithuCoupleSessionProvider(
      authService: WithuCoupleAuthService(
        client: MockClient((request) async {
          throw http.ClientException('offline');
        }),
        sessionStore: WithuCoupleSessionStore(
          storage: _FakeSecureStorage(_seededCachedProfileValues()),
        ),
      ),
    );

    await provider.restoreSession();

    expect(provider.isLoggedIn, isFalse);
    expect(provider.hasStoredSession, isTrue);
    expect(provider.userNickname, 'Cached Me');
    expect(provider.partnerNickname, 'Cached Her');
  });
}
