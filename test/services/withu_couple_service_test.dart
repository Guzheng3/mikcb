import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/data_transfer_service.dart';
import 'package:university_timetable/services/withu_couple_auth_service.dart';
import 'package:university_timetable/services/withu_couple_config.dart';
import 'package:university_timetable/services/withu_couple_session_store.dart';
import 'package:university_timetable/services/withu_couple_timetable_service.dart';
import 'package:university_timetable/services/withu_couple_auto_sync_service.dart';

class _FakeClient extends http.BaseClient {
  final Map<String, http.Response> responses;
  final List<http.Request> requests = [];

  _FakeClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      requests.add(request);
    }
    final response = responses[request.url.toString()];
    if (response == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('not found')),
        404,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _MemorySecureStorage implements WithuCoupleSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

const _loginUrl = 'https://withu.example.com/api/timetable.php?action=login';
const _partnerUrl =
    'https://withu.example.com/api/timetable.php?action=partner';
const _saveUrl = 'https://withu.example.com/api/timetable.php?action=save';
const _saveSettingsUrl =
    'https://withu.example.com/api/timetable.php?action=save_settings';

http.Response _jsonResponse(
  Map<String, dynamic> payload, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(payload)),
    statusCode,
    headers: headers,
  );
}

http.Response _loginResponse() {
  return _jsonResponse(
    {
      'success': true,
      'csrf_token': 'csrf-token',
      'user': {
        'id': 1,
        'username': 'alice',
        'nickname': 'Alice',
        'role': 'couple',
      },
      'partner': {
        'id': 2,
        'username': 'bob',
        'nickname': 'Bob',
        'role': 'couple',
      },
    },
    headers: {
      'set-cookie':
          'PHPSESSID=session-id; Path=/; HttpOnly, withu_device=device-token; Path=/',
    },
  );
}

String _backupJson(String courseId) {
  return DataTransferService().buildBackupJson(
    profileName: 'Bob',
    courses: [
      Course(
        id: courseId,
        name: 'Math',
        teacher: 'Teacher',
        location: 'A101',
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        startTime: '08:00',
        endTime: '09:40',
      ),
    ],
    settings: TimetableSettings.defaults(),
    currentWeek: 1,
  );
}

http.Response _partnerResponse(String content, String contentHash) {
  return _jsonResponse({
    'success': true,
    'partner': {
      'id': 2,
      'username': 'bob',
      'nickname': 'Bob',
      'role': 'couple',
    },
    'partner_timetable': {
      'content': jsonDecode(content),
      'content_hash': contentHash,
    },
  });
}

Future<WithuCoupleAuthService> _connectedAuthService(
  _FakeClient client,
  _MemorySecureStorage storage,
) async {
  final service = WithuCoupleAuthService(
    client: client,
    sessionStore: WithuCoupleSessionStore(storage: storage),
  );
  await service.connect(
    baseUrl: 'https://withu.example.com',
    username: ' alice ',
    password: 'password',
  );
  return service;
}

TimetableProvider _provider() {
  return TimetableProvider(
    autoInitialize: false,
    enableLiveActivitySync: false,
  );
}

Future<void> _flushAutoSync() async {
  await Future<void>.delayed(Duration.zero);
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('normalizes withU server URLs', () {
    expect(
      const WithuCoupleConfig(baseUrl: 'https://withu.example.com').apiUri,
      Uri.parse('https://withu.example.com/api/timetable.php'),
    );
    expect(
      const WithuCoupleConfig(baseUrl: 'https://withu.example.com/').apiUri,
      Uri.parse('https://withu.example.com/api/timetable.php'),
    );
    expect(
      const WithuCoupleConfig(
        baseUrl: 'https://withu.example.com/custom',
      ).apiUri,
      Uri.parse('https://withu.example.com/custom/api/timetable.php'),
    );
  });

  test('login stores cookies and CSRF token from the login response', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({_loginUrl: _loginResponse()});
    final service = await _connectedAuthService(client, storage);

    final request = client.requests.single;
    final result = await service.loadSession();

    expect(request.url.toString(), _loginUrl);
    expect(request.headers['Accept'], 'application/json');
    expect(request.headers['Content-Type'], 'application/json');
    expect(jsonDecode(request.body), {
      'username': 'alice',
      'password': 'password',
    });
    expect(
      result?.cookieHeader,
      'PHPSESSID=session-id; withu_device=device-token',
    );
    expect(result?.csrfToken, 'csrf-token');
    expect(storage.values.values.toSet(), {
      'alice',
      'password',
      'session-id',
      'device-token',
      'csrf-token',
    });
  });

  test('pull imports, updates, then reports unchanged', () async {
    final content = _backupJson('course-1');
    final contentHash = sha256.convert(utf8.encode(content)).toString();
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _partnerResponse(content, contentHash),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);
    final provider = _provider();

    final imported = await service.pullPartnerTimetable(provider: provider);
    expect(imported.status, WithuCouplePullStatus.imported);
    expect(provider.hasPartnerBinding, isTrue);
    expect(provider.partnerProfile?.name, 'Bob');

    final updatedContent = _backupJson('course-2');
    final updatedHash = sha256.convert(utf8.encode(updatedContent)).toString();
    client.responses[_partnerUrl] = _partnerResponse(
      updatedContent,
      updatedHash,
    );
    final updated = await service.pullPartnerTimetable(provider: provider);
    expect(updated.status, WithuCouplePullStatus.updated);

    final unchanged = await service.pullPartnerTimetable(provider: provider);
    expect(unchanged.status, WithuCouplePullStatus.unchanged);

    final config = await service.loadConfig();
    expect(config.lastRemoteContentHash, updatedHash);
    expect(config.lastPulledAt, isNotNull);
  });

  test('pull imports legacy withU partner timetable content', () async {
    final content = jsonEncode({
      'week': 1,
      'courses': [
        {'day': 1, 'start': '08:00', 'end': '09:40', 'title': 'Legacy Math'},
      ],
    });
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _partnerResponse(
        content,
        sha256.convert(utf8.encode(content)).toString(),
      ),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);
    final provider = _provider();

    final result = await service.pullPartnerTimetable(provider: provider);

    expect(
      result.status,
      isIn([WithuCouplePullStatus.imported, WithuCouplePullStatus.updated]),
    );
    expect(provider.partnerProfile?.courses, hasLength(1));
    expect(provider.partnerProfile?.courses.single.name, 'Legacy Math');
    expect(provider.partnerProfile?.courses.single.startSection, 1);
    expect(provider.partnerProfile?.courses.single.endSection, 2);
  });
  test('pull reports missing partner timetable content', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _jsonResponse({'success': true}),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);

    final result = await service.pullPartnerTimetable(provider: _provider());

    expect(result.status, WithuCouplePullStatus.failed);
    expect(result.errorCode, 'withu_partner_timetable_missing');
  });

  test('preserves the partner package validation error code', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _partnerResponse(
        jsonEncode({
          'app': 'mikcb',
          'schemaVersion': DataTransferService.schemaVersion,
          'courses': const [],
        }),
        'invalid-package-hash',
      ),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);

    final result = await service.pullPartnerTimetable(provider: _provider());

    expect(result.status, WithuCouplePullStatus.failed);
    expect(result.errorCode, 'missing_settings_data');
  });

  test('upload sends a JSON object with the CSRF token', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _saveUrl: _jsonResponse({'success': true}),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);
    final provider = _provider();
    await provider.initialize();

    final error = await service.uploadMyTimetableForPartner(provider: provider);

    expect(error, isNull);
    final saveRequest = client.requests.singleWhere(
      (request) => request.url.queryParameters['action'] == 'save',
    );
    final body = jsonDecode(saveRequest.body) as Map<String, dynamic>;
    expect(body['content'], isA<Map<String, dynamic>>());
    expect(body['_token'], 'csrf-token');
    expect(
      saveRequest.headers['Cookie'],
      'PHPSESSID=session-id; withu_device=device-token',
    );
    expect(saveRequest.headers['X-CSRF-Token'], 'csrf-token');
  });

  test(
    'auto sync uploads timetable changes without uploading settings',
    () async {
      final storage = _MemorySecureStorage();
      final client = _FakeClient({
        _loginUrl: _loginResponse(),
        _saveUrl: _jsonResponse({'success': true}),
        _saveSettingsUrl: _jsonResponse({'success': true}),
      });
      final auth = await _connectedAuthService(client, storage);
      final service = WithuCoupleTimetableService(authService: auth);
      final autoSync = WithuCoupleAutoSyncService(
        timetableService: service,
        debounceDelay: Duration.zero,
        pullOnBind: false,
      );
      final provider = _provider();
      await provider.initialize();
      autoSync.bind(provider);
      addTearDown(autoSync.dispose);

      await provider.addCourse(
        Course(
          id: 'course-1',
          name: 'Math',
          teacher: 'Teacher',
          location: 'A101',
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          startTime: '08:00',
          endTime: '09:40',
        ),
      );
      await _flushAutoSync();

      expect(
        client.requests.where(
          (request) => request.url.queryParameters['action'] == 'save',
        ),
        hasLength(1),
      );
      expect(
        client.requests.where(
          (request) => request.url.queryParameters['action'] == 'save_settings',
        ),
        isEmpty,
      );
    },
  );

  test('auto sync uploads timetable metadata changes', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _saveUrl: _jsonResponse({'success': true}),
      _saveSettingsUrl: _jsonResponse({'success': true}),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);
    final autoSync = WithuCoupleAutoSyncService(
      timetableService: service,
      debounceDelay: Duration.zero,
      pullOnBind: false,
    );
    final provider = _provider();
    await provider.initialize();
    autoSync.bind(provider);
    addTearDown(autoSync.dispose);

    await provider.createTimeScheme(name: 'Evening');
    await _flushAutoSync();

    expect(
      client.requests.where(
        (request) => request.url.queryParameters['action'] == 'save',
      ),
      hasLength(1),
    );
    expect(
      client.requests.where(
        (request) => request.url.queryParameters['action'] == 'save_settings',
      ),
      isEmpty,
    );
  });

  test(
    'upload strips personal settings from the partner timetable package',
    () async {
      final storage = _MemorySecureStorage();
      final client = _FakeClient({
        _loginUrl: _loginResponse(),
        _saveUrl: _jsonResponse({'success': true}),
      });
      final auth = await _connectedAuthService(client, storage);
      final service = WithuCoupleTimetableService(authService: auth);
      final provider = _provider();
      await provider.initialize();
      await provider.updateSettings(
        provider.settings.copyWith(
          homePageWallpaperPath: '/private/wallpaper.jpg',
          savedThemes: const [],
        ),
      );

      final error = await service.uploadMyTimetableForPartner(
        provider: provider,
      );

      expect(error, isNull);
      final saveRequest = client.requests.singleWhere(
        (request) => request.url.queryParameters['action'] == 'save',
      );
      final body = jsonDecode(saveRequest.body) as Map<String, dynamic>;
      final content = body['content'] as Map<String, dynamic>;
      final settings = content['settings'] as Map<String, dynamic>;
      expect(settings['homePageWallpaperPath'], isNull);
      expect(settings['sections'], isNotEmpty);
      expect(
        settings['semesterWeekCount'],
        provider.settings.semesterWeekCount,
      );
    },
  );

  test(
    'sync after login uploads my timetable before pulling partner',
    () async {
      final content = _backupJson('course-1');
      final contentHash = sha256.convert(utf8.encode(content)).toString();
      final storage = _MemorySecureStorage();
      final client = _FakeClient({
        _loginUrl: _loginResponse(),
        _saveUrl: _jsonResponse({'success': true}),
        _partnerUrl: _partnerResponse(content, contentHash),
      });
      final auth = await _connectedAuthService(client, storage);
      final service = WithuCoupleTimetableService(authService: auth);
      final provider = _provider();

      final result = await service.syncAfterLogin(provider: provider);

      expect(result.status, WithuCouplePullStatus.updated);
      final saveRequest = client.requests.singleWhere(
        (request) => request.url.queryParameters['action'] == 'save',
      );
      final partnerRequest = client.requests.singleWhere(
        (request) => request.url.queryParameters['action'] == 'partner',
      );
      expect(
        client.requests.indexOf(saveRequest),
        lessThan(client.requests.indexOf(partnerRequest)),
      );
      expect(provider.hasPartnerBinding, isTrue);
      expect(provider.partnerProfile?.name, 'Bob');
    },
  );

  test(
    'auto sync uploads personal settings without uploading timetable',
    () async {
      final storage = _MemorySecureStorage();
      final client = _FakeClient({
        _loginUrl: _loginResponse(),
        _saveUrl: _jsonResponse({'success': true}),
        _saveSettingsUrl: _jsonResponse({'success': true}),
      });
      final auth = await _connectedAuthService(client, storage);
      final service = WithuCoupleTimetableService(authService: auth);
      final autoSync = WithuCoupleAutoSyncService(
        timetableService: service,
        debounceDelay: Duration.zero,
        pullOnBind: false,
      );
      final provider = _provider();
      await provider.initialize();
      autoSync.bind(provider);
      addTearDown(autoSync.dispose);

      await provider.updateSettings(
        provider.settings.copyWith(homePageWallpaperPath: '/personal/bg.jpg'),
      );
      await _flushAutoSync();

      final settingsRequest = client.requests.singleWhere(
        (request) => request.url.queryParameters['action'] == 'save_settings',
      );
      final body = jsonDecode(settingsRequest.body) as Map<String, dynamic>;
      expect(body['content'], isA<Map<String, dynamic>>());
      expect(
        client.requests.where(
          (request) => request.url.queryParameters['action'] == 'save',
        ),
        isEmpty,
      );
    },
  );

  test('bind pulls the partner timetable once for a saved session', () async {
    final content = _backupJson('course-1');
    final contentHash = sha256.convert(utf8.encode(content)).toString();
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _partnerResponse(content, contentHash),
    });
    final auth = await _connectedAuthService(client, storage);
    final autoSync = WithuCoupleAutoSyncService(
      timetableService: WithuCoupleTimetableService(authService: auth),
      debounceDelay: Duration.zero,
    );
    final provider = _provider();
    await provider.initialize();
    autoSync.bind(provider);
    addTearDown(autoSync.dispose);
    await _flushAutoSync();

    expect(
      client.requests.where(
        (request) => request.url.queryParameters['action'] == 'partner',
      ),
      hasLength(1),
    );
    expect(provider.hasPartnerBinding, isTrue);
    expect(
      client.requests.where(
        (request) => request.url.queryParameters['action'] == 'save',
      ),
      isEmpty,
    );
  });

  test('auto sync makes no requests when withU is not connected', () async {
    final client = _FakeClient({});
    final auth = WithuCoupleAuthService(client: client);
    final autoSync = WithuCoupleAutoSyncService(
      timetableService: WithuCoupleTimetableService(authService: auth),
      debounceDelay: Duration.zero,
      pullOnBind: true,
    );
    final provider = _provider();
    await provider.initialize();
    autoSync.bind(provider);
    addTearDown(autoSync.dispose);

    await provider.updateSettings(
      provider.settings.copyWith(homePageWallpaperPath: '/personal/bg.jpg'),
    );
    await _flushAutoSync();

    expect(client.requests, isEmpty);
  });

  test('maps login 401 and authenticated 403 responses', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _jsonResponse({
        'success': false,
        'message': 'invalid credentials',
      }, statusCode: 401),
      _partnerUrl: _jsonResponse({
        'success': false,
        'message': 'couple account required',
      }, statusCode: 403),
    });
    final auth = WithuCoupleAuthService(
      client: client,
      sessionStore: WithuCoupleSessionStore(storage: storage),
    );

    await expectLater(
      auth.connect(
        baseUrl: 'https://withu.example.com',
        username: 'alice',
        password: 'password',
      ),
      throwsA(
        isA<WithuCoupleApiException>().having(
          (error) => error.code,
          'code',
          'withu_auth_failed',
        ),
      ),
    );

    final values = {
      'withu_couple_username': 'alice',
      'withu_couple_password': 'password',
      'withu_couple_phpsessid': 'session-id',
      'withu_couple_csrf_token': 'csrf-token',
    };
    storage.values.addAll(values);
    await const WithuCoupleConfigStore().save(
      const WithuCoupleConfig(baseUrl: 'https://withu.example.com'),
    );
    final service = WithuCoupleTimetableService(authService: auth);
    final result = await service.pullPartnerTimetable(provider: _provider());

    expect(result.errorCode, 'withu_couple_account_required');
  });
}
