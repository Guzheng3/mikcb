import 'dart:convert';

import 'package:http/http.dart' as http;
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

  /// [remote] 比 [current] 高时返回 true。
  ///
  /// 本工程的对外版本号是四段（`5.2.0.5`），pubspec 里则写作 `5.2.0-0+135`；
  /// `docs/RELEASE.md` 约定二者按 `1.1.10-6+36` ≡ `1.1.10.6` 比较。pub_semver 只接受
  /// 三段号（`Version.parse('5.2.0.5')` 直接抛异常），四段号会因此永远比不出高低、
  /// 云端更新永远回「已是最新」，所以这里自行解析比较。
  static bool isRemoteNewer(String remote, String current) {
    return _compareVersions(remote, current) > 0;
  }

  static int _compareVersions(String left, String right) {
    final leftVersion = _parseVersion(left);
    final rightVersion = _parseVersion(right);
    final maxLength =
        leftVersion.mainParts.length > rightVersion.mainParts.length
        ? leftVersion.mainParts.length
        : rightVersion.mainParts.length;

    for (var index = 0; index < maxLength; index++) {
      final leftValue = index < leftVersion.mainParts.length
          ? leftVersion.mainParts[index]
          : 0;
      final rightValue = index < rightVersion.mainParts.length
          ? rightVersion.mainParts[index]
          : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    final leftPrerelease = leftVersion.prerelease;
    final rightPrerelease = rightVersion.prerelease;
    if (leftPrerelease == null && rightPrerelease == null) {
      return 0;
    }
    if (leftPrerelease == null) {
      return 1;
    }
    if (rightPrerelease == null) {
      return -1;
    }
    return _comparePrerelease(leftPrerelease, rightPrerelease);
  }

  /// 数字段进 [mainParts]，比较时短的一方按 0 补齐；
  /// `-` 后面的纯数字段按第四段编号并入 [mainParts]（`1.1.10-6+36` ≡ `1.1.10.6`），
  /// 非纯数字段（如 `rc1`、`rc.10`）保留为预发布标识，排在正式号之后。
  static _ParsedVersion _parseVersion(String raw) {
    final normalized = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final withoutBuild = normalized.split('+').first;
    final dashIndex = withoutBuild.indexOf('-');
    final hasPrerelease = dashIndex != -1;
    final base = hasPrerelease
        ? withoutBuild.substring(0, dashIndex)
        : withoutBuild;
    final explicitPrerelease = hasPrerelease
        ? withoutBuild.substring(dashIndex + 1).trim()
        : null;
    final baseParts = base
        .split('.')
        .map((item) => int.tryParse(item.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    if (explicitPrerelease != null) {
      // "29-debug" 这类数字前缀也当作第四段编号，与旧版更新检查行为一致。
      final numericPrerelease = _numericPrefixParts(explicitPrerelease);
      if (numericPrerelease != null) {
        return _ParsedVersion(
          mainParts: [...baseParts, ...numericPrerelease],
          prerelease: null,
        );
      }
    }

    return _ParsedVersion(
      mainParts: baseParts,
      prerelease: explicitPrerelease == null || explicitPrerelease.isEmpty
          ? null
          : explicitPrerelease,
    );
  }

  /// 取预发布段的数字前缀，如 `6.1` → [6, 1]、`29-debug` → [29]；
  /// 首段就不含数字（如 `rc.10`）时返回 null，表示它整体是文字标识。
  static List<int>? _numericPrefixParts(String raw) {
    final values = <int>[];
    for (final part in raw.split('.')) {
      final value = int.tryParse(part);
      if (value != null) {
        values.add(value);
        continue;
      }
      final match = RegExp(r'^\d+').firstMatch(part);
      if (match != null) {
        values.add(int.parse(match.group(0)!));
      }
      break;
    }
    return values.isEmpty ? null : values;
  }

  static int _comparePrerelease(String left, String right) {
    final leftParts = left.split('.');
    final rightParts = right.split('.');
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var index = 0; index < maxLength; index++) {
      final leftValue = index < leftParts.length ? leftParts[index] : '';
      final rightValue = index < rightParts.length ? rightParts[index] : '';
      if (leftValue == rightValue) {
        continue;
      }
      final leftNumber = int.tryParse(leftValue);
      final rightNumber = int.tryParse(rightValue);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      return leftValue.compareTo(rightValue);
    }
    return 0;
  }

  static bool _isLocalUpdateHost(String host) {
    const localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
    return localHosts.contains(host.toLowerCase());
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _ParsedVersion {
  final List<int> mainParts;
  final String? prerelease;

  const _ParsedVersion({required this.mainParts, required this.prerelease});
}
