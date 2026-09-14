import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/miui_live_activities_service.dart';
import 'package:university_timetable/services/storage_service.dart';

/// 反馈回路：流体云「课程已结束却仍显示上一节课」。
///
/// Dart 侧选课与快照的时间口径必须一致：
/// - 前台直发载荷：按当前作息表实时解析（LiveActivityLogic.resolveRealTime）；
/// - 原生快照：若直接发持久化的 course.startTime/endTime 字符串，
///   一旦作息表与导入时不同（改过作息 / 课程独立方案），原生侧就会用旧时钟
///   判定「上一节课还没结束」，流体云于是持续显示上一节课。
///
/// 本测试断言快照里的课程时间必须是**当前作息表解析值**，而非持久化字符串。
///
/// 前置条件必须走 `updateTimeScheme`（改当前生效的时间模板）：节次表归模板
/// 所有，往 `updateTimetableSettings` 里传 sections 会被 `_normalizeSettingsWithTimeScheme`
/// 归一化回模板值（设置页也是先把 sections 钉回当前值再提交），拿它造前置
/// 只会得到一个没被改动的作息表，断言注定失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    StorageService().resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  test('live snapshot carries scheme-resolved course clocks, not persisted strings', () async {
    final fake = TestMiuiLiveActivitiesService();
    final provider = TimetableProvider(
      autoInitialize: false,
      enableLiveActivitySync: true,
      liveActivitiesService: fake,
    );
    await provider.initialize();

    // 课程按导入时的旧作息表落库：第 1-2 节 08:00-09:40。
    await provider.addCourse(
      Course(
        id: 'stale-clock-course',
        name: '高等数学',
        teacher: '张老师',
        location: 'A101',
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        startTime: '08:00',
        endTime: '09:40',
      ),
    );
    expect(provider.courses.single.startTime, '08:00');

    // 之后当前作息表被改成第 1-2 节 07:50-09:30。
    final scheme = provider.timeSchemes.firstWhere(
      (item) => item.id == provider.settings.activeTimeSchemeId,
    );
    final message = await provider.updateTimeScheme(
      schemeId: scheme.id,
      name: scheme.name,
      sections: const [
        SectionTime(startTime: '07:50', endTime: '08:35'),
        SectionTime(startTime: '08:45', endTime: '09:30'),
      ],
    );
    expect(message, isNull);
    // 改作息表必须把内存课程的钟点一并重算，否则课表页与上课闹钟也会用旧时钟。
    expect(provider.courses.single.startTime, '07:50');

    await provider.updateLiveActivityForTesting();

    expect(fake.syncScheduleSnapshotCallCount, greaterThanOrEqualTo(1));
    final synced = fake.lastSyncedCourses;
    expect(synced, isNotNull);
    expect(synced!.length, 1);
    // 必须按当前作息表解析：07:50-09:30。
    // 若发出 08:00-09:40，原生侧会认为课程 09:40 才结束，期间流体云一直显示它。
    expect(synced.single.startTime, '07:50');
    expect(synced.single.endTime, '09:30');
  });
}
