import 'package:flutter/foundation.dart';

/// 情侣历史课表的角色：我的 / 对方的。
enum CoupleTimetableRole { mine, hers }

/// 一条历史课表快照。
///
/// 「往期」的粒度是学期：同一角色下，同一 [semesterAnchor]（学期开学日）
/// 只保留一条，新快照覆盖旧快照（写入侧负责 upsert，见
/// CoupleTimetableHistoryService）。恢复时按 [snapshot] 还原课程、
/// 当前周与学期开学日。
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
  });

  final String id;
  final CoupleTimetableRole role;

  /// 快照所属学期的开学日（去重键）；课表未配置开学日时为 null。
  final DateTime? semesterAnchor;

  /// 快照时的课表名（展示用）。
  final String name;
  final int courseCount;
  final DateTime savedAt;

  /// 可还原的课表数据：{name, currentWeek, semesterStartDate, courses}。
  final Map<String, dynamic> snapshot;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'semesterAnchor': semesterAnchor?.toIso8601String(),
    'name': name,
    'courseCount': courseCount,
    'savedAt': savedAt.toIso8601String(),
    'snapshot': snapshot,
  };

  factory CoupleTimetableHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawSnapshot = json['snapshot'];
    return CoupleTimetableHistoryEntry(
      id: json['id'] as String? ?? '',
      role:
          (json['role'] as String?) == CoupleTimetableRole.hers.name
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
      snapshot:
          rawSnapshot is Map
              ? Map<String, dynamic>.from(rawSnapshot)
              : const <String, dynamic>{},
    );
  }
}
