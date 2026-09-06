import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/couple_timetable_history.dart';
import 'package:university_timetable/services/couple_timetable_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('same role and semester keeps only the latest snapshot', () async {
    const service = CoupleTimetableHistoryService();
    const anchor = '2026-03-02';

    await service.upsert(
      role: CoupleTimetableRole.mine,
      semesterAnchor: DateTime.parse(anchor),
      name: '旧版',
      courseJsonList: [const {'name': '旧课'}],
      currentWeek: 1,
    );
    await service.upsert(
      role: CoupleTimetableRole.mine,
      semesterAnchor: DateTime.parse(anchor),
      name: '新版',
      courseJsonList: [
        const {'name': '旧课'},
        const {'name': '新课'},
      ],
      currentWeek: 3,
    );

    final entries = await service.entriesFor(CoupleTimetableRole.mine);
    expect(entries, hasLength(1));
    expect(entries.single.name, '新版');
    expect(entries.single.courseCount, 2);
  });

  test('different semesters accumulate and sort by anchor descending', () async {
    const service = CoupleTimetableHistoryService();

    await service.upsert(
      role: CoupleTimetableRole.mine,
      semesterAnchor: DateTime(2026, 3, 2),
      name: '春季学期',
      courseJsonList: const [{}],
      currentWeek: 1,
    );
    await service.upsert(
      role: CoupleTimetableRole.mine,
      semesterAnchor: DateTime(2025, 9, 8),
      name: '秋季学期',
      courseJsonList: const [{}],
      currentWeek: 1,
    );
    await service.upsert(
      role: CoupleTimetableRole.mine,
      semesterAnchor: DateTime(2026, 9, 7),
      name: '秋季学期二',
      courseJsonList: const [{}],
      currentWeek: 1,
    );

    final entries = await service.entriesFor(CoupleTimetableRole.mine);
    expect(entries.map((entry) => entry.name).toList(), [
      '秋季学期二',
      '春季学期',
      '秋季学期',
    ]);
  });

  test('roles are kept separate', () async {
    const service = CoupleTimetableHistoryService();

    await service.upsert(
      role: CoupleTimetableRole.mine,
      semesterAnchor: DateTime(2026, 3, 2),
      name: '我的',
      courseJsonList: const [],
      currentWeek: 1,
    );
    await service.upsert(
      role: CoupleTimetableRole.hers,
      semesterAnchor: DateTime(2026, 3, 2),
      name: '她的',
      courseJsonList: const [],
      currentWeek: 1,
    );

    expect((await service.entriesFor(CoupleTimetableRole.mine)).single.name, '我的');
    expect((await service.entriesFor(CoupleTimetableRole.hers)).single.name, '她的');
  });
}
