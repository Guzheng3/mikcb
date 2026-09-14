import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/class_reminder.dart';
import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/miui_live_activities_service.dart';
import 'package:university_timetable/services/partner_timetable_service.dart';
import 'package:university_timetable/services/storage_service.dart';

/// 反馈回路：桌面情侣卡片右半点进 TA 课表、返回桌面后，自己的超级岛与
/// 上课提醒都变成了对方的。
///
/// 卡片右半走 `WidgetLaunchRouter` → `switchProfile(partnerProfileId)`，
/// 「当前课表」因此真的变成 TA（这是 TA 课表可切换的既定行为，主界面照常
/// 展示 TA 的课）。但超级岛、原生课程快照与上课/考试提醒服务的是「用户
/// 自己的课」，必须按 `myTimetableProfile` 计算，与正在浏览哪份课表解耦，
/// 否则点一下对方的卡片就把自己的提醒换掉了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const examChannel = MethodChannel('vip.qinghan.withu/exam_reminder');

  setUp(() {
    StorageService().resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  Future<TimetableProvider> createProvider(
    TestMiuiLiveActivitiesService fake,
  ) async {
    final provider = TimetableProvider(
      autoInitialize: false,
      enableLiveActivitySync: true,
      liveActivitiesService: fake,
    );
    await provider.initialize();
    return provider;
  }

  /// 我的课表（含一节课）＋ 一张课程名刻意不同的 TA 课表，便于断言归属。
  Future<TimetableProvider> createProviderWithPartner(
    TestMiuiLiveActivitiesService fake, {
    required DateTime day,
  }) async {
    final provider = await createProvider(fake);
    await provider.addCourse(
      Course(
        id: 'mine-1',
        name: '我的高数',
        teacher: '张老师',
        location: 'A101',
        dayOfWeek: day.weekday,
        startSection: 1,
        endSection: 2,
        startTime: '08:00',
        endTime: '09:40',
      ),
    );
    // 假期标记会让选课随运行日期变成空，测试里关掉以保证确定性。
    await provider.updateSettings(
      provider.settings.copyWith(enableHolidayMarking: false),
    );
    await provider.importPartnerTimetable(
      provider.dataTransferService.buildBackupJson(
        profileName: 'TA的课表',
        courses: [
          Course(
            id: 'partner-1',
            name: 'TA的英语',
            teacher: '李老师',
            location: 'B202',
            dayOfWeek: day.weekday,
            startSection: 1,
            endSection: 2,
            startTime: '08:00',
            endTime: '09:40',
          ),
        ],
        settings: TimetableSettings.defaults(),
        currentWeek: 1,
      ),
    );
    return provider;
  }

  test('切到 TA 课表后，原生课程快照仍是「我的课表」', () async {
    final fake = TestMiuiLiveActivitiesService();
    final day = DateTime.now();
    final provider = await createProviderWithPartner(fake, day: day);

    await provider.switchProfile(PartnerTimetableService.partnerProfileId);
    // 前置成立：当前课表确实已经是 TA 的了。
    expect(provider.activeProfile?.isPartnerImported, isTrue);

    await provider.updateLiveActivityForTesting();

    expect(fake.syncScheduleSnapshotCallCount, greaterThanOrEqualTo(1));
    final names = fake.lastSyncedCourses
        ?.map((course) => course.name)
        .toList(growable: false);
    expect(names, isNotNull);
    expect(names, contains('我的高数'));
    expect(names, isNot(contains('TA的英语')));
  });

  test('切到 TA 课表后，超级岛选课仍取「我的课表」', () async {
    final fake = TestMiuiLiveActivitiesService();
    final day = DateTime.now();
    final provider = await createProviderWithPartner(fake, day: day);

    await provider.switchProfile(PartnerTimetableService.partnerProfileId);

    // 07:00 早于第 1 节（默认作息 08:00）的提前提醒窗口，走「即将上课」回退。
    final at = DateTime(day.year, day.month, day.day, 7);
    final selection = provider.getLiveActivityCourseSelection(
      now: at,
      allowUpcomingFallback: true,
    );

    expect(selection?.currentCourse.name, '我的高数');
  });

  test('切到 TA 课表后，单节课提醒仍按「我的课表」排程', () async {
    final fake = TestMiuiLiveActivitiesService();
    final day = DateTime.now();
    final provider = await createProviderWithPartner(fake, day: day);

    await provider.setClassReminder(
      ClassReminderEntry(
        courseId: 'mine-1',
        date: ClassReminderEntry.formatDate(day.add(const Duration(days: 1))),
        minuteOfDay: 8 * 60,
      ),
    );

    // 只收集「当前课表已经是 TA」时的重排结果：切换流程里的提醒重排是
    // fire-and-forget，按活跃档案判定归属，避免依赖时序。
    final whilePartnerActive = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(examChannel, (call) async {
          if (call.method == 'reconcile' &&
              provider.activeProfileId ==
                  PartnerTimetableService.partnerProfileId) {
            whilePartnerActive.add(
              Map<dynamic, dynamic>.from(call.arguments as Map),
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(examChannel, null),
    );

    await provider.switchProfile(PartnerTimetableService.partnerProfileId);
    await pumpEventQueue();

    expect(whilePartnerActive, isNotEmpty, reason: '切换课表后应重排提醒');
    final titles = whilePartnerActive
        .expand((payload) => payload['fires'] as List)
        .map((fire) => (fire as Map)['title'] as String)
        .toList();
    expect(titles, contains('我的高数'));
    expect(titles, isNot(contains('TA的英语')));
  });
}
