import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';
import 'package:university_timetable/services/app_update_service.dart';

const _validSha256 =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  test('rejects a malformed download URL before network access', () async {
    final service = AppUpdateService();

    final result = await service.downloadAndInstallUpdate(
      'ftp://example.com/app.apk',
      (_, _) {},
      null,
      expectedApkSha256: _validSha256,
    );

    expect(result, 'update_download_url_untrusted');
  });

  test('missing and blank SHA-256 digests are refused', () async {
    final service = AppUpdateService();

    final missingDigest = await service.downloadAndInstallUpdate(
      'https://withu.example.com/app.apk',
      (_, _) {},
      null,
    );
    final blankDigest = await service.downloadAndInstallUpdate(
      'https://withu.example.com/app.apk',
      (_, _) {},
      null,
      expectedApkSha256: '   ',
    );

    expect(missingDigest, 'update_sha256_unverified_install_refused');
    expect(blankDigest, 'update_sha256_unverified_install_refused');
  });

  test('HTTP failure returns a status code without leaving an APK', () async {
    final tempDir = await Directory.systemTemp.createTemp('mikcb_update_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = 404;
        await request.response.close();
      }
    }());

    final service = AppUpdateService(
      temporaryDirectoryProvider: () async => tempDir,
    );

    final result = await service.downloadAndInstallUpdate(
      'http://${server.address.host}:${server.port}/app.apk',
      (_, _) {},
      null,
      expectedApkSha256: _validSha256,
    );

    expect(
      result,
      encodeServiceMessage('update_download_http_failed', {'statusCode': 404}),
    );
    expect(File('${tempDir.path}/mikcb_update.apk').existsSync(), isFalse);

    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  test(
    'successful download opens the installer after digest verification',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mikcb_update_test_',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(() async {
        await for (final request in server) {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.binary;
          request.response.contentLength = 6;
          request.response.add(List<int>.filled(6, 7));
          await request.response.close();
        }
      }());

      String? openedPath;
      final progress = <int>[];
      final service = AppUpdateService(
        temporaryDirectoryProvider: () async => tempDir,
        openInstaller: (path) async {
          openedPath = path;
          return OpenResult();
        },
      );

      final result = await service.downloadAndInstallUpdate(
        'http://${server.address.host}:${server.port}/app.apk',
        (downloadedBytes, totalBytes) {
          progress.add(downloadedBytes);
          expect(totalBytes, 6);
        },
        null,
        expectedApkSha256: sha256.convert(List<int>.filled(6, 7)).toString(),
      );

      expect(result, isNull);
      expect(openedPath, '${tempDir.path}/mikcb_update.apk');
      expect(progress.last, 6);
      expect(File(openedPath!).existsSync(), isTrue);

      await server.close(force: true);
      await tempDir.delete(recursive: true);
    },
  );

  test('SHA-256 mismatch deletes the downloaded APK', () async {
    final tempDir = await Directory.systemTemp.createTemp('mikcb_update_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.binary;
        request.response.add(List<int>.filled(6, 7));
        await request.response.close();
      }
    }());

    final service = AppUpdateService(
      temporaryDirectoryProvider: () async => tempDir,
      openInstaller: (path) async {
        fail('tampered APK must not reach the installer');
      },
    );

    final result = await service.downloadAndInstallUpdate(
      'http://${server.address.host}:${server.port}/app.apk',
      (_, _) {},
      null,
      expectedApkSha256: sha256.convert(<int>[1, 2, 3]).toString(),
    );

    expect(result, 'update_download_hash_mismatch');
    expect(File('${tempDir.path}/mikcb_update.apk').existsSync(), isFalse);

    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  test('cancelled download cleans up its partial APK', () async {
    final tempDir = await Directory.systemTemp.createTemp('mikcb_update_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = 12;
        request.response.add(List<int>.filled(4, 1));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        request.response.add(List<int>.filled(4, 2));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        request.response.add(List<int>.filled(4, 3));
        await request.response.close();
      }
    }());

    final controller = AppUpdateDownloadController();
    final service = AppUpdateService(
      temporaryDirectoryProvider: () async => tempDir,
      openInstaller: (path) async {
        fail('cancelled download should not open the installer');
      },
    );

    final result = await service.downloadAndInstallUpdate(
      'http://${server.address.host}:${server.port}/app.apk',
      (downloadedBytes, _) {
        if (downloadedBytes >= 4) {
          controller.cancel();
        }
      },
      controller,
      expectedApkSha256: sha256.convert(List<int>.filled(12, 1)).toString(),
    );

    expect(result, AppUpdateService.downloadCancelledMessage);
    expect(File('${tempDir.path}/mikcb_update.apk').existsSync(), isFalse);

    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  test('controller reset allows a clean resumed download', () async {
    final tempDir = await Directory.systemTemp.createTemp('mikcb_update_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestIndex = 0;
    unawaited(() async {
      await for (final request in server) {
        final isFirstRequest = requestIndex++ == 0;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = 6;
        try {
          request.response.add(List<int>.filled(3, 7));
          await request.response.flush();
          if (isFirstRequest) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          request.response.add(List<int>.filled(3, 7));
          await request.response.close();
        } catch (_) {
          // The first attempt is force-closed by cancellation.
        }
      }
    }());

    final controller = AppUpdateDownloadController();
    var cancelFirstAttempt = true;
    String? openedPath;
    final service = AppUpdateService(
      temporaryDirectoryProvider: () async => tempDir,
      openInstaller: (path) async {
        openedPath = path;
        return OpenResult();
      },
    );
    final expectedDigest = sha256.convert(List<int>.filled(6, 7)).toString();

    final firstAttempt = await service.downloadAndInstallUpdate(
      'http://${server.address.host}:${server.port}/app.apk',
      (_, _) {
        if (cancelFirstAttempt) {
          cancelFirstAttempt = false;
          controller.cancel();
        }
      },
      controller,
      expectedApkSha256: expectedDigest,
    );

    expect(firstAttempt, AppUpdateService.downloadCancelledMessage);
    expect(openedPath, isNull);

    controller.reset();
    final secondAttempt = await service.downloadAndInstallUpdate(
      'http://${server.address.host}:${server.port}/app.apk',
      (_, _) {},
      controller,
      expectedApkSha256: expectedDigest,
    );

    expect(secondAttempt, isNull);
    expect(openedPath, '${tempDir.path}/mikcb_update.apk');

    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  test('cancellation closes a stalled HTTP response immediately', () async {
    final tempDir = await Directory.systemTemp.createTemp('mikcb_update_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final responseStarted = Completer<void>();
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = 1;
        request.response.add([1]);
        await request.response.flush();
        responseStarted.complete();
        try {
          await request.response.done;
        } catch (_) {
          // Force-closing the client is expected to abort the response.
        }
      }
    }());

    final controller = AppUpdateDownloadController();
    final service = AppUpdateService(
      temporaryDirectoryProvider: () async => tempDir,
      openInstaller: (path) async {
        fail('cancelled download should not open the installer');
      },
    );

    try {
      final downloadFuture = service.downloadAndInstallUpdate(
        'http://${server.address.host}:${server.port}/app.apk',
        (_, _) {},
        controller,
        expectedApkSha256: sha256.convert(<int>[1]).toString(),
      );
      await responseStarted.future.timeout(const Duration(seconds: 2));
      controller.cancel();
      final result = await downloadFuture.timeout(const Duration(seconds: 2));

      expect(result, AppUpdateService.downloadCancelledMessage);
      expect(File('${tempDir.path}/mikcb_update.apk').existsSync(), isFalse);
    } finally {
      await server.close(force: true);
      await tempDir.delete(recursive: true);
    }
  });

  test('stale managed APK files are cleared before a new download', () async {
    final tempDir = await Directory.systemTemp.createTemp('mikcb_update_test_');
    final staleOldApk = File('${tempDir.path}/mikcb_update_old.apk');
    await staleOldApk.writeAsString('stale');
    final staleCurrentApk = File('${tempDir.path}/mikcb_update.apk');
    await staleCurrentApk.writeAsString('old-current');

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.binary;
        request.response.add(List<int>.filled(6, 7));
        await request.response.close();
      }
    }());

    String? openedPath;
    final service = AppUpdateService(
      temporaryDirectoryProvider: () async => tempDir,
      openInstaller: (path) async {
        openedPath = path;
        return OpenResult();
      },
    );

    final result = await service.downloadAndInstallUpdate(
      'http://${server.address.host}:${server.port}/app.apk',
      (_, _) {},
      null,
      expectedApkSha256: sha256.convert(List<int>.filled(6, 7)).toString(),
    );

    expect(result, isNull);
    expect(openedPath, '${tempDir.path}/mikcb_update.apk');
    expect(staleOldApk.existsSync(), isFalse);
    expect(staleCurrentApk.existsSync(), isTrue);
    expect(await staleCurrentApk.length(), 6);

    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });
}
