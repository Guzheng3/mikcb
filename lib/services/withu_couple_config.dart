import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WithuCoupleConfig {
  static const String prefsKey = 'withu_couple_config_v1';
  static const String defaultBaseUrl = '';

  final String baseUrl;
  final DateTime? lastPulledAt;
  final String? lastRemoteContentHash;

  const WithuCoupleConfig({
    this.baseUrl = defaultBaseUrl,
    this.lastPulledAt,
    this.lastRemoteContentHash,
  });

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
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
  }

  WithuCoupleConfig copyWith({
    String? baseUrl,
    DateTime? lastPulledAt,
    String? lastRemoteContentHash,
    bool clearLastPulledAt = false,
    bool clearLastRemoteContentHash = false,
  }) {
    return WithuCoupleConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      lastPulledAt: clearLastPulledAt
          ? null
          : (lastPulledAt ?? this.lastPulledAt),
      lastRemoteContentHash: clearLastRemoteContentHash
          ? null
          : (lastRemoteContentHash ?? this.lastRemoteContentHash),
    );
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'lastPulledAt': lastPulledAt?.toIso8601String(),
    'lastRemoteContentHash': lastRemoteContentHash,
  };

  factory WithuCoupleConfig.fromJson(Map<String, dynamic> json) {
    return WithuCoupleConfig(
      baseUrl: json['baseUrl'] as String? ?? defaultBaseUrl,
      lastPulledAt: DateTime.tryParse(json['lastPulledAt'] as String? ?? ''),
      lastRemoteContentHash: json['lastRemoteContentHash'] as String?,
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
