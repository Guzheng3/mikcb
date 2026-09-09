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
      semesterAnchor: DateTime.tryParse(
        json['semesterStartDate'] as String? ?? '',
      ),
      name: json['profileName'] as String? ?? '',
      courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
      savedAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      changeType: json['changeType'] as String? ?? 'manual',
      snapshot: const <String, dynamic>{},
    );
  }
}
