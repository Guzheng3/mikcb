import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/models/couple_timetable_history.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/data_transfer_service.dart';
import 'package:university_timetable/services/partner_timetable_service.dart';
import 'package:university_timetable/services/withu_couple_auth_service.dart';
import 'package:university_timetable/services/withu_couple_config.dart';
import 'package:university_timetable/services/withu_couple_session_store.dart';
import 'package:university_timetable/services/withu_couple_timetable_service.dart';
import 'package:university_timetable/services/withu_couple_auto_sync_service.dart';
import 'package:university_timetable/services/storage_service.dart';

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
const _bootstrapUrl =
    'https://withu.example.com/api/timetable.php?action=bootstrap';
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

http.Response _loginResponse({
  Map<String, String> headers = const {
    'set-cookie':
        'PHPSESSID=session-id; Path=/; HttpOnly, withu_device=device-token; Path=/',
  },
}) {
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

http.Response _bootstrapResponse(
  String? myContent,
  String? partnerContent, {
  String? partnerContentHash,
  DateTime? serverTime,
  DateTime? updatedAt,
}) {
  return _jsonResponse({
    'success': true,
    'logged_in': true,
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
    if (serverTime != null) 'server_time': serverTime.toIso8601String(),
    if (myContent != null)
      'timetable': {
        'content': jsonDecode(myContent),
        'content_hash': sha256.convert(utf8.encode(myContent)).toString(),
        if (updatedAt != null) 'updated_at': updatedAt.toIso8601String(),
      },
    if (partnerContent != null)
      'partner_timetable': {
        'content': jsonDecode(partnerContent),
        'content_hash':
            partnerContentHash ??
            sha256.convert(utf8.encode(partnerContent)).toString(),
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
    StorageService().resetForTesting();
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
      'session-id',
      'device-token',
      'csrf-token',
      'Alice',
      'Bob',
    });
  });

  test('login parses folded Set-Cookie headers containing commas', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(
        headers: {
          'set-cookie':
              'PHPSESSID=session-id; '
              'Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/; HttpOnly, '
              'withu_device=device-token; '
              'Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/',
        },
      ),
    });

    await WithuCoupleAuthService(
      client: client,
      sessionStore: WithuCoupleSessionStore(storage: storage),
    ).connect(
      baseUrl: 'https://withu.example.com',
      username: 'alice',
      password: 'password',
    );

    final session = await WithuCoupleSessionStore(storage: storage).load();

    expect(
      session?.cookieHeader,
      'PHPSESSID=session-id; withu_device=device-token',
    );
  });

  test('load wipes the legacy stored password from secure storage', () async {
    final storage = _MemorySecureStorage();
    storage.values.addAll({
      'withu_couple_username': 'alice',
      'withu_couple_password': 'legacy-secret',
      'withu_couple_phpsessid': 'session-id',
      'withu_couple_csrf_token': 'csrf-token',
    });
    final store = WithuCoupleSessionStore(storage: storage);

    final session = await store.load();

    expect(session, isNotNull);
    expect(session?.cookieHeader, 'PHPSESSID=session-id');
    expect(storage.values.containsKey('withu_couple_password'), isFalse);
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
  test('pull reports unchanged when no partner is linked', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _jsonResponse({'success': true, 'partner': null}),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);

    final result = await service.pullPartnerTimetable(provider: _provider());

    expect(result.status, WithuCouplePullStatus.unchanged);
    expect(result.errorCode, isNull);
  });

  test('pull reports missing partner timetable content', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _jsonResponse({
        'success': true,
        'partner': {'id': 2, 'username': 'bob'},
      }),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);

    final result = await service.pullPartnerTimetable(provider: _provider());

    expect(result.status, WithuCouplePullStatus.failed);
    expect(result.errorCode, 'withu_partner_timetable_missing');
  });

  test('clears the stored session after an authenticated 401', () async {
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _partnerResponse(
        _backupJson('course-1'),
        sha256.convert(utf8.encode(_backupJson('course-1'))).toString(),
      ),
    });
    final auth = await _connectedAuthService(client, storage);
    client.responses[_partnerUrl] = _jsonResponse({
      'success': false,
    }, statusCode: 401);
    final service = WithuCoupleTimetableService(authService: auth);

    final result = await service.pullPartnerTimetable(provider: _provider());

    expect(result.status, WithuCouplePullStatus.failed);
    expect(result.errorCode, 'withu_session_expired');
    expect(await auth.loadSession(), isNull);
    expect(storage.values, isEmpty);
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
      await StorageService().setMigratedAppLogsDefault(true);
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
    await StorageService().setMigratedAppLogsDefault(true);
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
      expect(settings['homePageWallpaperPath'], defaultHomePageWallpaperPath);
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
        _bootstrapUrl: _bootstrapResponse(content, content),
        _saveUrl: _jsonResponse({'success': true}),
        _partnerUrl: _partnerResponse(content, contentHash),
      });
      final auth = await _connectedAuthService(client, storage);
      final service = WithuCoupleTimetableService(authService: auth);
      final provider = _provider();

      final result = await service.syncAfterLogin(provider: provider);

      expect(result.status, WithuCouplePullStatus.imported);
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

  test('sync after login restores my timetable from cloud', () async {
    final myContent = _backupJson('cloud-course');
    final partnerContent = _backupJson('partner-course');
    final partnerHash = sha256.convert(utf8.encode(partnerContent)).toString();
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _bootstrapUrl: _bootstrapResponse(myContent, partnerContent),
      _saveUrl: _jsonResponse({'success': true}),
      _partnerUrl: _partnerResponse(partnerContent, partnerHash),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);
    final provider = _provider();

    final result = await service.syncAfterLogin(provider: provider);

    expect(result.status, WithuCouplePullStatus.imported);
    final myCourse = provider.myTimetableProfile?.courses.single;
    expect(myCourse?.id, 'cloud-course');
    expect(myCourse?.name, 'Math');
    expect(provider.hasPartnerBinding, isTrue);
    expect(provider.partnerProfile?.name, 'Bob');

    final actionOrder = client.requests
        .map((request) => request.url.queryParameters['action'])
        .toList();
    expect(actionOrder, ['login', 'bootstrap', 'save', 'partner']);
  });

  test('sync after login keeps a newer local timetable', () async {
    final now = DateTime.now();
    final cloudContent = _backupJson('cloud-course');
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _saveUrl: _jsonResponse({'success': true}),
      _bootstrapUrl: _bootstrapResponse(
        cloudContent,
        null,
        serverTime: now,
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      _partnerUrl: _jsonResponse({'success': true, 'partner': null}),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);
    final provider = _provider();
    await provider.initialize();
    await provider.addCourse(
      Course(
        id: 'local-course',
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
    await service.uploadMyTimetableForPartner(provider: provider);
    await provider.addCourse(
      Course(
        id: 'newer-local-course',
        name: 'Physics',
        teacher: 'Teacher',
        location: 'B201',
        dayOfWeek: 2,
        startSection: 3,
        endSection: 4,
        startTime: '10:00',
        endTime: '11:40',
      ),
    );
    final result = await service.syncAfterLogin(provider: provider);

    expect(result.status, WithuCouplePullStatus.unchanged);
    expect(provider.myTimetableProfile?.courses.map((course) => course.id), [
      'local-course',
      'newer-local-course',
    ]);
  });

  test('cloud restore snapshots the prior my timetable', () async {
    final cloudContent = _backupJson('cloud-course');
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _bootstrapUrl: _bootstrapResponse(cloudContent, null),
      _saveUrl: _jsonResponse({'success': true}),
      _partnerUrl: _jsonResponse({'success': true, 'partner': null}),
    });
    final auth = await _connectedAuthService(client, storage);
    final service = WithuCoupleTimetableService(authService: auth);
    final provider = _provider();
    await provider.initialize();
    await provider.updateSettings(
      provider.settings.copyWith(semesterStartDate: DateTime(2026, 9, 7)),
    );
    await provider.addCourse(
      Course(
        id: 'local-course',
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

    final result = await service.syncAfterLogin(provider: provider);
    final history = await provider.coupleTimetableHistoryEntriesFor(
      CoupleTimetableRole.mine,
    );

    expect(result.status, WithuCouplePullStatus.unchanged);
    expect(provider.myTimetableProfile?.courses.single.id, 'cloud-course');
    expect(history.single.courseCount, 1);
    final snapshotCourses = history.single.snapshot['courses'] as List<Object?>;
    final snapshotCourse = snapshotCourses.single as Map<String, Object?>;
    expect(snapshotCourse['id'], 'local-course');
  });

  test('auto sync pulls partner timetable changes', () async {
    final content = _backupJson('course-1');
    final contentHash = sha256.convert(utf8.encode(content)).toString();
    final updatedContent = _backupJson('course-2');
    final updatedHash = sha256.convert(utf8.encode(updatedContent)).toString();
    final storage = _MemorySecureStorage();
    final client = _FakeClient({
      _loginUrl: _loginResponse(),
      _partnerUrl: _partnerResponse(content, contentHash),
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

    await autoSync.pullPartnerChanges();
    expect(provider.partnerProfile?.courses.single.id, 'course-1');

    client.responses[_partnerUrl] = _partnerResponse(
      updatedContent,
      updatedHash,
    );
    await autoSync.pullPartnerChanges();
    expect(provider.partnerProfile?.courses.single.id, 'course-2');

    expect(
      client.requests.where(
        (request) => request.url.queryParameters['action'] == 'partner',
      ),
      hasLength(2),
    );
    expect(
      client.requests.where(
        (request) => request.url.queryParameters['action'] == 'save',
      ),
      isEmpty,
    );
  });

  test(
    'auto sync does not upload after switching to the partner profile',
    () async {
      final content = _backupJson('course-1');
      final contentHash = sha256.convert(utf8.encode(content)).toString();
      final storage = _MemorySecureStorage();
      final client = _FakeClient({
        _loginUrl: _loginResponse(),
        _partnerUrl: _partnerResponse(content, contentHash),
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
      await service.pullPartnerTimetable(provider: provider, force: true);
      autoSync.bind(provider);
      addTearDown(autoSync.dispose);

      await provider.switchProfile(PartnerTimetableService.partnerProfileId);
      await _flushAutoSync();

      expect(
        provider.activeProfileId,
        PartnerTimetableService.partnerProfileId,
      );
      expect(
        client.requests.where(
          (request) => request.url.queryParameters['action'] == 'save',
        ),
        isEmpty,
      );
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
