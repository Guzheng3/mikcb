import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_http_client.dart';
import 'app_update_service.dart';
import 'withu_couple_config.dart';

class WithuAppUpdateService {
  static const String ignoredVersionPrefsKey =
      'withu_update_ignored_version_v1';
  static const Duration _defaultRequestTimeout = Duration(seconds: 4);

  WithuAppUpdateService({
    http.Client? client,
    WithuCoupleConfigStore? configStore,
    Duration? requestTimeout,
  }) : _client = client ?? createAppHttpClient(),
       _configStore = configStore ?? const WithuCoupleConfigStore(),
       _requestTimeout = requestTimeout ?? _defaultRequestTimeout {
    _ownsClient = client == null && !isSharedAppHttpClient(_client);
  }

  final http.Client _client;
  final WithuCoupleConfigStore _configStore;
  final Duration _requestTimeout;
  late final bool _ownsClient;

  Future<AppUpdateCheckResult?> checkForUpdates({
    required String currentVersion,
  }) async {
    if (currentVersion.trim().isEmpty) {
      return null;
    }

    try {
      final config = await _configStore.load();
      final response = await _client
          .get(config.appUpdateApiUri)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return null;
      }
      final payload = Map<String, dynamic>.from(decoded);
      if (payload['success'] != true || payload['has_update'] != true) {
        return _noUpdate(currentVersion);
      }

      final rawRelease = payload['release'];
      if (rawRelease is! Map) {
        return null;
      }
      final release = _releaseFromJson(
        Map<String, dynamic>.from(rawRelease),
        config,
      );
      if (release == null || !isRemoteNewer(release.version, currentVersion)) {
        return _noUpdate(currentVersion);
      }
      if (!release.forceUpdate && await isVersionIgnored(release.version)) {
        return _noUpdate(currentVersion);
      }

      return AppUpdateCheckResult(
        hasRelease: true,
        hasUpdate: true,
        currentVersion: currentVersion,
        latestRelease: release,
        message: 'withu_update_available',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> ignoreNonForcedVersion(String version) async {
    final normalizedVersion = version.trim();
    if (normalizedVersion.isEmpty) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ignoredVersionPrefsKey, normalizedVersion);
    } catch (_) {
      // Update prompts remain the safe fallback if preferences are unavailable.
    }
  }

  Future<bool> isVersionIgnored(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(ignoredVersionPrefsKey)?.trim() == version.trim();
    } catch (_) {
      return false;
    }
  }

  AppUpdateCheckResult _noUpdate(String currentVersion) {
    return AppUpdateCheckResult(
      hasRelease: false,
      hasUpdate: false,
      currentVersion: currentVersion,
      message: 'withu_already_latest',
    );
  }

  AppReleaseInfo? _releaseFromJson(
    Map<String, dynamic> json,
    WithuCoupleConfig config,
  ) {
    final version = (json['version'] as String?)?.trim() ?? '';
    final title = (json['title'] as String?)?.trim() ?? '';
    final body = (json['body'] as String?)?.trim() ?? '';
    final downloadUrl = (json['download_url'] as String?)?.trim() ?? '';
    final sha256 = (json['sha256'] as String?)?.trim() ?? '';
    final updatedAt = DateTime.tryParse((json['updated_at'] as String?) ?? '');

    final uri = Uri.tryParse(downloadUrl);
    final apiUri = config.appUpdateApiUri;
    final usesLocalHost = _isLocalUpdateHost(apiUri.host);
    if (version.isEmpty ||
        uri == null ||
        (uri.scheme != 'https' && !(usesLocalHost && uri.scheme == 'http')) ||
        uri.host != apiUri.host ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      return null;
    }

    return AppReleaseInfo(
      version: version,
      title: title.isEmpty ? version : title,
      body: body,
      releaseUrl: config.baseUrl,
      downloadUrl: downloadUrl,
      updatedAt: updatedAt,
      isPrerelease: false,
      forceUpdate: json['force_update'] == true,
      expectedApkSha256: sha256.toLowerCase(),
    );
  }

  static bool isRemoteNewer(String remote, String current) {
    return _compareVersions(remote, current) > 0;
  }

  static bool _isLocalUpdateHost(String host) {
    const localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
    return localHosts.contains(host.toLowerCase());
  }

  static int _compareVersions(String remote, String current) {
    final remoteVersion = _parseVersion(remote);
    final currentVersion = _parseVersion(current);
    final length =
        remoteVersion.mainParts.length > currentVersion.mainParts.length
        ? remoteVersion.mainParts.length
        : currentVersion.mainParts.length;

    for (var index = 0; index < length; index++) {
      final remotePart = index < remoteVersion.mainParts.length
          ? remoteVersion.mainParts[index]
          : 0;
      final currentPart = index < currentVersion.mainParts.length
          ? currentVersion.mainParts[index]
          : 0;
      if (remotePart != currentPart) {
        return remotePart.compareTo(currentPart);
      }
    }

    final remotePre = remoteVersion.prerelease;
    final currentPre = currentVersion.prerelease;
    if (remotePre == null && currentPre == null) {
      return 0;
    }
    if (remotePre == null) {
      return 1;
    }
    if (currentPre == null) {
      return -1;
    }
    return remotePre.compareTo(currentPre);
  }

  static ({List<int> mainParts, String? prerelease}) _parseVersion(String raw) {
    final normalized = raw
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first;
    final dashIndex = normalized.indexOf('-');
    final mainText = dashIndex < 0
        ? normalized
        : normalized.substring(0, dashIndex);
    final prerelease = dashIndex < 0
        ? null
        : normalized.substring(dashIndex + 1).trim();
    final mainParts = mainText
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
    if (mainParts.isEmpty) {
      mainParts.add(0);
    }
    return (
      mainParts: mainParts,
      prerelease: prerelease == null || prerelease.isEmpty ? null : prerelease,
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
