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
