import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_http_client.dart';
import 'app_update_service.dart';
import 'withu_couple_config.dart';

class WithuAppUpdateService {
  static const String ignoredVersionPrefsKey =
      'withu_update_ignored_version_v1';
  static const String _selectedBaseUrlPrefsKey =
      'withu_update_selected_base_url_v1';
  static const Duration _defaultRequestTimeout = Duration(seconds: 4);
  static const Duration _probeTimeout = Duration(seconds: 2);

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
    bool respectIgnoredVersion = true,
  }) async {
    if (currentVersion.trim().isEmpty) {
      return null;
    }

    try {
      final config = await _resolveUpdateConfig();
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
      if (respectIgnoredVersion &&
          !release.forceUpdate &&
          await isVersionIgnored(release.version)) {
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
      await _clearSelectedBaseUrl();
      return null;
    }
  }

  Future<WithuCoupleConfig> _resolveUpdateConfig() async {
    final config = await _configStore.load();
    if (!WithuCoupleConfig.isBuiltInBaseUrl(config.baseUrl)) {
      return config;
    }
    final cached = await _loadSelectedBaseUrl();
    if (cached != null && WithuCoupleConfig.isBuiltInBaseUrl(cached)) {
      return config.copyWith(baseUrl: cached);
    }
    final winner = await _probeFastestBaseUrl();
    if (winner != null) {
      await _saveSelectedBaseUrl(winner);
      return config.copyWith(baseUrl: winner);
    }
    return config;
  }

  Future<String?> _probeFastestBaseUrl() async {
    final latencies = await Future.wait(
      WithuCoupleConfig.builtInBaseUrls.map(_probeLatency),
    );
    String? best;
    Duration? bestLatency;
    for (var i = 0; i < WithuCoupleConfig.builtInBaseUrls.length; i++) {
      final latency = latencies[i];
      if (latency != null && (bestLatency == null || latency < bestLatency)) {
        best = WithuCoupleConfig.builtInBaseUrls[i];
        bestLatency = latency;
      }
    }
    return best;
  }

  Future<Duration?> _probeLatency(String url) async {
    try {
      final uri = Uri.parse(url);
      final stopwatch = Stopwatch()..start();
      await _client.head(uri).timeout(_probeTimeout);
      stopwatch.stop();
      return stopwatch.elapsed;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadSelectedBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedBaseUrlPrefsKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSelectedBaseUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedBaseUrlPrefsKey, url);
    } catch (_) {
      // Selection cache is best-effort.
    }
  }

  Future<void> _clearSelectedBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_selectedBaseUrlPrefsKey);
    } catch (_) {
      // Best-effort.
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
    final allowHttp =
        usesLocalHost || WithuCoupleConfig.isBuiltInHost(apiUri.host);
    if (version.isEmpty ||
        uri == null ||
        (uri.scheme != 'https' && !(allowHttp && uri.scheme == 'http')) ||
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
    final remoteVersion = _parseVersion(remote);
    final currentVersion = _parseVersion(current);
    return remoteVersion != null &&
        currentVersion != null &&
        remoteVersion > currentVersion;
  }

  static bool _isLocalUpdateHost(String host) {
    const localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
    return localHosts.contains(host.toLowerCase());
  }

  static Version? _parseVersion(String raw) {
    final normalized = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    try {
      return Version.parse(normalized);
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
