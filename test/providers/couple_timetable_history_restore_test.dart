import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/models/couple_timetable_history.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/holiday_service.dart';
import 'package:university_timetable/services/storage_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 「我的历史课表」捕获 + 恢复链路：
/// 换学期（开学日变更）时旧课表进历史；恢复时当前课表被换下并进历史。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const homeWidgetChannel = MethodChannel('com.mutx163.qingyu/home_widget');
  const analyticsChannel = MethodChannel('com.mutx163.qingyu/umeng_analytics');
  const liveChannel = MethodChannel('com.mutx163.qingyu/miui_live');

  setUp(() {
    StorageService().resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidgetChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidgetChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, null);
  });

  TimetableProvider buildProvider() {
    final now = DateTime(2026, 4, 12);
    final course = Course(
      id: 'c1',
      name: '高数',
      teacher: '张老师',
      location: 'A101',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      startTime: '08:00',
      endTime: '09:40',
    );
    final settings = TimetableSettings.defaults().copyWith(
      semesterStartDate: DateTime(2026, 3, 2),
    );
    final profile = TimetableProfile(
      id: 'profile-1',
      name: '默认课表',
      courses: [course],
      settings: settings,
      currentWeek: 1,
      createdAt: now,
      lastUsedAt: now,
    );
    SharedPreferences.setMockInitialValues({
      'did_migrate_app_logs_default': true,
      'did_migrate_live_hide_prefix_default': true,
      'timetable_profiles': jsonEncode([profile.toJson()]),
      'active_timetable_profile_id': profile.id,
      'time_schemes': '[]',
      'withu_couple_config_v1': jsonEncode({
        'baseUrl': 'https://withu.example.com',
      }),
    });
    return TimetableProvider(
      autoInitialize: false,
      enableLiveActivitySync: false,
      holidayService: HolidayService(
        client: MockClient((request) async => http.Response('{"code":0,"data":[]}', 200)),
      ),
    );
  }

  test('semester change snapshots mine history and restore rolls back', () async {
    final provider = buildProvider();

    // 换到秋季学期：春季学期（含旧课表）进入历史。
    await provider.initialize();
    await provider.updateTimetableSettings(
      provider.settings.copyWith(semesterStartDate: DateTime(2026, 9, 7)),
    );

    final entries = await provider.coupleTimetableHistoryEntriesFor(
      CoupleTimetableRole.mine,
    );
    expect(entries, hasLength(1));
    expect(entries.single.semesterAnchor, DateTime(2026, 3, 2));
    expect(entries.single.name, '默认课表');
    expect(entries.single.courseCount, 1);

    // 恢复春季学期课表：开学日与课程还原，当前（秋季）课表被换下进历史。
    final restored = await provider.restoreCoupleTimetableHistory(
      entries.single,
    );
    expect(restored, isTrue);
    expect(provider.settings.semesterStartDate, DateTime(2026, 3, 2));
    expect(provider.courses.single.name, '高数');

    final afterRestore = await provider.coupleTimetableHistoryEntriesFor(
      CoupleTimetableRole.mine,
    );
    expect(afterRestore, hasLength(2));
    expect(
      afterRestore.map((entry) => entry.semesterAnchor),
      containsAll([DateTime(2026, 3, 2), DateTime(2026, 9, 7)]),
    );
  });
}
