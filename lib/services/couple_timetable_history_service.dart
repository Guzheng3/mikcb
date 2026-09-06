import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/couple_timetable_history.dart';

/// 情侣历史课表存取：按「角色 + 学期开学日」去重的往期课表快照。
///
/// 写入统一走 [upsert]——同角色同学期只保留一条，新快照覆盖旧快照；
/// 读取用 [entriesFor]，按学期开学日降序返回。
class CoupleTimetableHistoryService {
  const CoupleTimetableHistoryService();

  static const String _prefsKey = 'couple_timetable_history_v1';

  Future<List<CoupleTimetableHistoryEntry>> entriesFor(
    CoupleTimetableRole role,
  ) async {
    final all = await _loadAll();
    final entries =
        all.where((entry) => entry.role == role).toList()
          ..sort((a, b) {
            final aAnchor = a.semesterAnchor;
            final bAnchor = b.semesterAnchor;
            if (aAnchor != null && bAnchor != null) {
              return bAnchor.compareTo(aAnchor);
            }
            return b.savedAt.compareTo(a.savedAt);
          });
    return entries;
  }

  /// 写入一条快照：同角色同学期的既有记录被覆盖（同一学期的课表只显示
  /// 一个）。
  Future<void> upsert({
    required CoupleTimetableRole role,
    required DateTime? semesterAnchor,
    required String name,
    required List<Map<String, dynamic>> courseJsonList,
    required int currentWeek,
  }) async {
    final all = List<CoupleTimetableHistoryEntry>.of(await _loadAll());
    final anchorKey = semesterAnchor?.toIso8601String();
    all.removeWhere(
      (entry) =>
          entry.role == role &&
          entry.semesterAnchor?.toIso8601String() == anchorKey,
    );
    final entry = CoupleTimetableHistoryEntry(
      // 同角色同学期只保留一条，id 用 role+anchor 派生即可稳定复用。
      id: '${role.name}-${anchorKey ?? 'none'}',
      role: role,
      semesterAnchor: semesterAnchor,
      name: name,
      courseCount: courseJsonList.length,
      savedAt: DateTime.now(),
      snapshot: {
        'name': name,
        'currentWeek': currentWeek,
        'semesterStartDate': semesterAnchor?.toIso8601String(),
        'courses': courseJsonList,
      },
    );
    all.add(entry);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(all.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<List<CoupleTimetableHistoryEntry>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (item) => CoupleTimetableHistoryEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
