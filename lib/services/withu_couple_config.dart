import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WithuCoupleConfig {
  static const String prefsKey = 'withu_couple_config_v1';
  static const String defaultBaseUrl = 'https://gzr.xjy.xn--6qq986b3xl/';
  static const List<String> builtInBaseUrls = [
    'https://gzr.xjy.xn--6qq986b3xl/',
    'http://withu.qinghan.vip/',
  ];

  final String baseUrl;
  final DateTime? lastPulledAt;
  final String? lastRemoteContentHash;
  final String? lastMyTimetableHash;
  final DateTime? lastMyTimetableSyncedAt;

  const WithuCoupleConfig({
    this.baseUrl = defaultBaseUrl,
    this.lastPulledAt,
    this.lastRemoteContentHash,
    this.lastMyTimetableHash,
    this.lastMyTimetableSyncedAt,
  });

  static bool isBuiltInHost(String host) {
    final normalized = host.trim().toLowerCase();
    return builtInBaseUrls.any((url) {
      final uri = Uri.tryParse(url);
      return uri != null && uri.host.toLowerCase() == normalized;
    });
  }

  static bool isBuiltInBaseUrl(String url) {
    try {
      return isBuiltInHost(Uri.parse(url.trim()).host);
    } catch (_) {
      return false;
    }
  }

  Uri get apiUri {
    final value = baseUrl.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      throw const FormatException('withu_invalid_url');
    }
    final uri = Uri.parse(value);
    if (uri.host.trim().isEmpty) {
      throw const FormatException('withu_invalid_url');
    }

    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') {
      path = '';
    }
    if (path.isEmpty) {
      path = '/api/timetable.php';
    } else if (path != '/api/timetable.php') {
      path = '$path/api/timetable.php';
    }
    return _buildUri(uri, path);
  }

  Uri get appUpdateApiUri {
    final value = baseUrl.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      throw const FormatException('withu_invalid_url');
    }
    final uri = Uri.parse(value);
    if (uri.host.trim().isEmpty) {
      throw const FormatException('withu_invalid_url');
    }

    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') {
      path = '';
    }
    if (path.isEmpty) {
      path = '/api/app_update.php';
    } else if (path != '/api/app_update.php') {
      path = '$path/api/app_update.php';
    }
    return _buildUri(uri, path);
  }

  Uri _buildUri(Uri base, String path) {
    return Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
    );
  }

  WithuCoupleConfig copyWith({
    String? baseUrl,
    DateTime? lastPulledAt,
    String? lastRemoteContentHash,
    String? lastMyTimetableHash,
    DateTime? lastMyTimetableSyncedAt,
    bool clearLastPulledAt = false,
    bool clearLastRemoteContentHash = false,
    bool clearLastMyTimetableHash = false,
    bool clearLastMyTimetableSyncedAt = false,
  }) {
    return WithuCoupleConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      lastPulledAt: clearLastPulledAt
          ? null
          : (lastPulledAt ?? this.lastPulledAt),
      lastRemoteContentHash: clearLastRemoteContentHash
          ? null
          : (lastRemoteContentHash ?? this.lastRemoteContentHash),
      lastMyTimetableHash: clearLastMyTimetableHash
          ? null
          : (lastMyTimetableHash ?? this.lastMyTimetableHash),
      lastMyTimetableSyncedAt: clearLastMyTimetableSyncedAt
          ? null
          : (lastMyTimetableSyncedAt ?? this.lastMyTimetableSyncedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'lastPulledAt': lastPulledAt?.toIso8601String(),
    'lastRemoteContentHash': lastRemoteContentHash,
    'lastMyTimetableHash': lastMyTimetableHash,
    'lastMyTimetableSyncedAt': lastMyTimetableSyncedAt?.toIso8601String(),
  };

  factory WithuCoupleConfig.fromJson(Map<String, dynamic> json) {
    return WithuCoupleConfig(
      baseUrl: json['baseUrl'] as String? ?? defaultBaseUrl,
      lastPulledAt: DateTime.tryParse(json['lastPulledAt'] as String? ?? ''),
      lastRemoteContentHash: json['lastRemoteContentHash'] as String?,
      lastMyTimetableHash: json['lastMyTimetableHash'] as String?,
      lastMyTimetableSyncedAt: DateTime.tryParse(
        json['lastMyTimetableSyncedAt'] as String? ?? '',
      ),
    );
  }
}

class WithuCoupleConfigStore {
  const WithuCoupleConfigStore();

  Future<WithuCoupleConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(WithuCoupleConfig.prefsKey);
    if (raw == null || raw.isEmpty) {
      return const WithuCoupleConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const WithuCoupleConfig();
      }
      return WithuCoupleConfig.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const WithuCoupleConfig();
    }
  }

  Future<void> save(WithuCoupleConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      WithuCoupleConfig.prefsKey,
      jsonEncode(config.toJson()),
    );
  }
}
