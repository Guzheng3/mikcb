import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../logging/app_debug_log.dart';
import '../l10n/service_message_localizer.dart';
import '../utils/async_utils.dart';

class UpdateLogEntry {
  final DateTime timestamp;
  final String message;

  const UpdateLogEntry(this.timestamp, this.message);

  String get timeString {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class AppReleaseInfo {
  final String version;
  final String title;
  final String body;
  final String releaseUrl;
  final String? downloadUrl;
  final DateTime? updatedAt;
  final bool isPrerelease;
  final bool forceUpdate;
  final String? expectedApkSha256;

  const AppReleaseInfo({
    required this.version,
    required this.title,
    required this.body,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.updatedAt,
    required this.isPrerelease,
    this.forceUpdate = false,
    this.expectedApkSha256,
  });
}

class AppUpdateCheckResult {
  final bool hasRelease;
  final bool hasUpdate;
  final String currentVersion;
  final AppReleaseInfo? latestRelease;
  final String? message;

  const AppUpdateCheckResult({
    required this.hasRelease,
    required this.hasUpdate,
    required this.currentVersion,
    this.latestRelease,
    this.message,
  });
}

enum SystemDownloadStatus {
  pending,
  running,
  paused,
  successful,
  failed,
  unknown,
}

class SystemDownloadProgress {
  final SystemDownloadStatus status;
  final int downloadedBytes;
  final int? totalBytes;
  final int? reason;

  const SystemDownloadProgress({
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    this.reason,
  });

  bool get isFinished =>
      status == SystemDownloadStatus.successful ||
      status == SystemDownloadStatus.failed;
}

class AppUpdateDownloadController {
  bool _isCancelled = false;
  void Function()? _cancelHandler;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final handler = _cancelHandler;
    _cancelHandler = null;
    handler?.call();
  }

  void reset() {
    _isCancelled = false;
    _cancelHandler = null;
  }

  void _setCancelHandler(void Function()? handler) {
    _cancelHandler = handler;
    if (_isCancelled && handler != null) {
      _cancelHandler = null;
      handler();
    }
  }
}

typedef AppUpdateTempDirectoryProvider = Future<Directory> Function();
typedef AppUpdateOpenInstaller = Future<OpenResult> Function(String path);

class AppUpdateService {
  static const String downloadCancelledMessage = 'download_cancelled';

  static const MethodChannel _systemDownloadChannel = MethodChannel(
    'com.mutx163.qingyu/system_download',
  );

  final List<UpdateLogEntry> logs = [];
  final AppUpdateTempDirectoryProvider _temporaryDirectoryProvider;
  final AppUpdateOpenInstaller _openInstaller;

  AppUpdateService({
    AppUpdateTempDirectoryProvider? temporaryDirectoryProvider,
    AppUpdateOpenInstaller? openInstaller,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _openInstaller = openInstaller ?? OpenFilex.open;

  void _log(String message) {
    final now = DateTime.now();
    final entry = UpdateLogEntry(now, message);
    logs.insert(0, entry);
    if (logs.length > 50) logs.removeLast();
    appDebugLog('AppUpdateService', '${formatLogTimestamp(now)} $message');
  }

  Future<int?> enqueueSystemDownload({
    required String url,
    String? fileName,
    String? title,
    String? description,
  }) {
    return _systemDownloadChannel.invokeMethod<int>('enqueueSystemDownload', {
      'url': url,
      'fileName': fileName,
      'title': title,
      'description': description,
    });
  }

  Future<SystemDownloadProgress?> querySystemDownloadProgress(
    int downloadId,
  ) async {
    final payload = await _systemDownloadChannel
        .invokeMethod<Map<Object?, Object?>>('getSystemDownloadProgress', {
          'downloadId': downloadId,
        });
    if (payload == null) {
      return null;
    }

    final status = switch (payload['status'] as String?) {
      'pending' => SystemDownloadStatus.pending,
      'running' => SystemDownloadStatus.running,
      'paused' => SystemDownloadStatus.paused,
      'successful' => SystemDownloadStatus.successful,
      'failed' => SystemDownloadStatus.failed,
      _ => SystemDownloadStatus.unknown,
    };
    final downloadedBytes = (payload['downloadedBytes'] as num?)?.toInt() ?? 0;
    final rawTotalBytes = (payload['totalBytes'] as num?)?.toInt() ?? -1;
    return SystemDownloadProgress(
      status: status,
      downloadedBytes: downloadedBytes,
      totalBytes: rawTotalBytes > 0 ? rawTotalBytes : null,
      reason: (payload['reason'] as num?)?.toInt(),
    );
  }

  Stream<SystemDownloadProgress> watchSystemDownloadProgress(
    int downloadId, {
    Duration interval = const Duration(milliseconds: 350),
  }) async* {
    while (true) {
      final progress = await querySystemDownloadProgress(downloadId);
      if (progress == null) {
        return;
      }
      yield progress;
      if (progress.isFinished) {
        return;
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<String?> downloadAndInstallUpdate(
    String url,
    void Function(int downloadedBytes, int? totalBytes) onProgress,
    AppUpdateDownloadController? controller, {
    String? expectedApkSha256,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      _log('rejected invalid update download url: $url');
      return 'update_download_url_untrusted';
    }

    final normalizedSha256 = expectedApkSha256?.trim() ?? '';
    if (normalizedSha256.isEmpty) {
      _log('update_sha256_unverified_install_refused');
      return 'update_sha256_unverified_install_refused';
    }

    _log('starting update download: $url');
    HttpClient? client;
    IOSink? sink;
    File? file;
    try {
      final tempDir = await _temporaryDirectoryProvider();
      await _cleanupManagedInstallerFiles(tempDir);
      final savePath = '${tempDir.path}/mikcb_update.apk';
      file = File(savePath);
      await _deleteFileIfExists(file);

      client = HttpClient();
      controller?._setCancelHandler(() => client?.close(force: true));
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        _log('update download failed, HTTP ${response.statusCode}');
        return encodeServiceMessage('update_download_http_failed', {
          'statusCode': response.statusCode,
        });
      }

      final total = response.contentLength;
      _log(
        'update download response OK, size '
        '${total > 0 ? '${(total / 1024 / 1024).toStringAsFixed(1)} MB' : 'unknown'}',
      );
      var downloaded = 0;
      sink = file.openWrite();

      await for (final chunk in response) {
        if (controller?.isCancelled == true) {
          _log('update download cancelled by user');
          return downloadCancelledMessage;
        }
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress(downloaded, total <= 0 ? null : total);
      }

      await sink.close();
      sink = null;

      if (controller?.isCancelled == true) {
        _log('update download cancelled by user');
        return downloadCancelledMessage;
      }

      _log(
        'update_download_completed: '
        '${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB',
      );

      final actual = await _computeFileSha256(file);
      if (actual == null) {
        _log('update_hash_compute_failed_rejected_cleaned');
        await _deleteFileIfExists(file);
        return 'update_download_hash_mismatch';
      }
      if (!_constantTimeEquals(actual, normalizedSha256)) {
        _log('update_sha256_mismatch_file_deleted');
        await _deleteFileIfExists(file);
        return 'update_download_hash_mismatch';
      }
      _log('update_sha256_verified');

      _log('update_installer_opening');
      final result = await _openInstaller(savePath);
      if (result.type != ResultType.done) {
        _log('failed to open installer: ${result.message}');
        return encodeServiceMessage('update_open_installer_failed', {
          'detail': result.message,
        });
      }
      _log('installer opened');
      return null;
    } catch (error) {
      if (controller?.isCancelled == true) {
        _log('update download cancelled by user');
        return downloadCancelledMessage;
      }
      _log('update download or install failed: $error');
      return encodeServiceMessage('update_download_install_error', {
        'detail': '$error',
      });
    } finally {
      controller?._setCancelHandler(null);
      try {
        await sink?.close();
      } catch (_) {
        // The sink was already closed on the normal path.
      }
      client?.close(force: true);
      if (controller?.isCancelled == true && file != null) {
        await _deleteFileIfExists(file);
      }
    }
  }

  Future<void> _cleanupManagedInstallerFiles(Directory tempDir) async {
    if (!tempDir.existsSync()) {
      return;
    }
    await for (final entity in tempDir.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      final normalized = name.toLowerCase();
      if (!normalized.startsWith('mikcb_update') ||
          !normalized.endsWith('.apk')) {
        continue;
      }
      await _deleteFileIfExists(entity);
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<String?> _computeFileSha256(File file) async {
    try {
      final stream = file.openRead();
      final digest = await sha256.bind(stream).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
