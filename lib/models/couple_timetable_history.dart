import 'package:flutter/foundation.dart';

enum CoupleTimetableRole { mine, hers }

/// Metadata for one cloud timetable history entry.
@immutable
class CoupleTimetableHistoryEntry {
  const CoupleTimetableHistoryEntry({
    required this.id,
    required this.role,
    required this.semesterAnchor,
    required this.name,
    required this.courseCount,
    required this.savedAt,
    required this.snapshot,
    this.changeType = 'manual',
  });

  final String id;
  final CoupleTimetableRole role;
  final DateTime? semesterAnchor;
  final String name;
  final int courseCount;
  final DateTime savedAt;
  final String changeType;

  /// Cloud history is rollback metadata only; this remains for legacy JSON.
  final Map<String, dynamic> snapshot;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'semesterAnchor': semesterAnchor?.toIso8601String(),
    'name': name,
    'courseCount': courseCount,
    'savedAt': savedAt.toIso8601String(),
    'changeType': changeType,
    'snapshot': snapshot,
  };

  factory CoupleTimetableHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawSnapshot = json['snapshot'];
    return CoupleTimetableHistoryEntry(
      id: json['id'] as String? ?? '',
      role: (json['role'] as String?) == CoupleTimetableRole.hers.name
          ? CoupleTimetableRole.hers
          : CoupleTimetableRole.mine,
      semesterAnchor: DateTime.tryParse(
        json['semesterAnchor'] as String? ?? '',
      ),
      name: json['name'] as String? ?? '',
      courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      changeType: json['changeType'] as String? ?? 'manual',
      snapshot: rawSnapshot is Map
          ? Map<String, dynamic>.from(rawSnapshot)
          : const <String, dynamic>{},
    );
  }

  factory CoupleTimetableHistoryEntry.fromServerJson(
    Map<String, dynamic> json,
  ) {
    return CoupleTimetableHistoryEntry(
      id: (json['id'] as num?)?.toInt().toString() ?? '',
      role: CoupleTimetableRole.mine,
      semesterAnchor: _parseSemesterAnchor(json['semesterStartDate']),
      name: json['profileName'] as String? ?? '',
      courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
      savedAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      changeType: json['changeType'] as String? ?? 'manual',
      snapshot: const <String, dynamic>{},
    );
  }

  /// 服务端回传的开学日期是**毫秒时间戳**（与 `TimetableSettings.toJson`
  /// 写出的 `millisecondsSinceEpoch` 同口径，管理台的 `withu_tt_millis_date`
  /// 也按毫秒解析），但后台允许手工粘贴任意 JSON，因此日期字符串也要认。
  /// 只走 [DateTime.tryParse] 的话，毫秒串一律解析失败，开学日期恒为空。
  static DateTime? _parseSemesterAnchor(Object? raw) {
    if (raw is num) {
      return _fromMillis(raw.toInt());
    }
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    final millis = int.tryParse(trimmed);
    if (millis != null) {
      return _fromMillis(millis);
    }
    return DateTime.tryParse(trimmed);
  }

  /// 0 与负数视为「未设置」，沿用管理台的 `$millis <= 0` 判定，
  /// 避免把空值渲染成 1970-01-01。
  static DateTime? _fromMillis(int? millis) {
    if (millis == null || millis <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
