import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/services/withu_app_update_service.dart';
import 'package:university_timetable/services/withu_couple_config.dart';

const _sha256 =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  test('parses a valid withU update release', () async {
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
    });
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'success': true,
          'has_update': true,
          'release': {
            'version': '1.2.3',
            'title': 'withU 1.2.3',
            'body': 'fixed scheduling sync',
            'download_url': 'https://withu.example.com/uploads/mikcb-1.2.3.apk',
            'sha256': _sha256,
            'updated_at': '2026-09-07T10:00:00+08:00',
            'force_update': false,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = WithuAppUpdateService(client: client);

    final result = await service.checkForUpdates(currentVersion: '1.2.2');

    expect(result, isNotNull);
    expect(result!.hasUpdate, isTrue);
    expect(result.latestRelease?.version, '1.2.3');
    expect(result.latestRelease?.title, 'withU 1.2.3');
    expect(result.latestRelease?.forceUpdate, isFalse);
    expect(result.latestRelease?.expectedApkSha256, _sha256);
    expect(requestedUri?.path, '/api/app_update.php');
  });

  test('non-forced ignored version stays silent', () async {
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
      WithuAppUpdateService.ignoredVersionPrefsKey: '1.2.3',
    });
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'has_update': true,
          'release': {
            'version': '1.2.3',
            'download_url': 'https://withu.example.com/uploads/mikcb-1.2.3.apk',
            'sha256': _sha256,
          },
        }),
        200,
      );
    });
    final service = WithuAppUpdateService(client: client);

    final result = await service.checkForUpdates(currentVersion: '1.2.2');

    expect(result, isNotNull);
    expect(result!.hasUpdate, isFalse);
  });

  test('forced update overrides the ignored version', () async {
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
      WithuAppUpdateService.ignoredVersionPrefsKey: '1.2.3',
    });
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'has_update': true,
          'release': {
            'version': '1.2.3',
            'download_url': 'https://withu.example.com/uploads/mikcb-1.2.3.apk',
            'sha256': _sha256,
            'force_update': true,
          },
        }),
        200,
      );
    });
    final service = WithuAppUpdateService(client: client);

    final result = await service.checkForUpdates(currentVersion: '1.2.2');

    expect(result, isNotNull);
    expect(result!.hasUpdate, isTrue);
    expect(result.latestRelease?.forceUpdate, isTrue);
  });

  test('rejects non-HTTPS or malformed downloads', () async {
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
    });
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'has_update': true,
          'release': {
            'version': '1.2.3',
            'download_url': 'http://insecure.example.com/app.apk',
            'sha256': _sha256,
          },
        }),
        200,
      );
    });
    final service = WithuAppUpdateService(client: client);

    final result = await service.checkForUpdates(currentVersion: '1.2.2');

    expect(result, isNotNull);
    expect(result!.hasUpdate, isFalse);
  });

  test('rejects download hosts outside the configured withU domain', () async {
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
    });
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'has_update': true,
          'release': {
            'version': '1.2.3',
            'download_url': 'https://cdn.example.com/mikcb-1.2.3.apk',
            'sha256': _sha256,
          },
        }),
        200,
      );
    });
    final service = WithuAppUpdateService(client: client);

    final result = await service.checkForUpdates(currentVersion: '1.2.2');

    expect(result, isNotNull);
    expect(result!.hasUpdate, isFalse);
  });

  test('allows HTTP on the same local Android emulator host', () async {
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'http://10.0.2.2:8080',
      }),
    });
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'has_update': true,
          'release': {
            'version': '1.2.3',
            'download_url': 'http://10.0.2.2:8080/uploads/mikcb-1.2.3.apk',
            'sha256': _sha256,
          },
        }),
        200,
      );
    });
    final service = WithuAppUpdateService(client: client);

    final result = await service.checkForUpdates(currentVersion: '1.2.2');

    expect(result, isNotNull);
    expect(result!.hasUpdate, isTrue);
    expect(
      result.latestRelease?.downloadUrl,
      'http://10.0.2.2:8080/uploads/mikcb-1.2.3.apk',
    );
  });

  test('HTTP failures return null', () async {
    SharedPreferences.setMockInitialValues({
      WithuCoupleConfig.prefsKey: jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
    });
    final client = MockClient((request) async {
      throw Exception('offline');
    });
    final service = WithuAppUpdateService(client: client);

    final result = await service.checkForUpdates(currentVersion: '1.2.2');

    expect(result, isNull);
  });

  test('version comparison orders normal and prerelease versions', () {
    expect(WithuAppUpdateService.isRemoteNewer('1.2.3', '1.2.2'), isTrue);
    expect(WithuAppUpdateService.isRemoteNewer('1.2.0', '1.2.0-rc1'), isTrue);
    expect(WithuAppUpdateService.isRemoteNewer('1.2.0', '1.2.0'), isFalse);
    expect(WithuAppUpdateService.isRemoteNewer('1.2.0-rc1', '1.2.0'), isFalse);
  });
}
