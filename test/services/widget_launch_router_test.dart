import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/miui_live_activities_service.dart';
import 'package:university_timetable/services/home_widget_binding_service.dart';
import 'package:university_timetable/services/partner_timetable_service.dart';
import 'package:university_timetable/services/storage_service.dart';
import 'package:university_timetable/services/widget_launch_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mutx163.qingyu/home_widget');
  const liveChannel = MethodChannel('com.mutx163.qingyu/miui_live');
  const examChannel = MethodChannel('com.mutx163.qingyu/exam_reminder');
  PendingHomeWidgetLaunch? pendingLaunch;
  final bindings = <int, String?>{};

  Future<Object?>? fakeHandler(MethodCall call) async {
    switch (call.method) {
      case 'getPendingWidgetLaunch':
        return pendingLaunch == null
            ? null
            : {
                'appWidgetId': pendingLaunch!.appWidgetId,
                'side': pendingLaunch!.side,
              };
      case 'getWidgetBinding':
        return bindings[(call.arguments as Map)['appWidgetId'] as int];
    }
    throw MissingPluginException();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService().resetForTesting();
    pendingLaunch = null;
    bindings.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, fakeHandler);
    // 切换成功路径会触发 switchProfile 的岛/考试提醒副作用，统一静音。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(examChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(examChannel, null);
  });

  Future<TimetableProvider> createProvider() async {
    final provider = TimetableProvider(
      autoInitialize: false,
      enableLiveActivitySync: false,
      liveActivitiesService: TestMiuiLiveActivitiesService(),
    );
    await provider.initialize();
    return provider;
  }

  Future<TimetableProvider> createProviderWithPartner() async {
    final provider = await createProvider();
    final backup = provider.dataTransferService.buildBackupJson(
      profileName: 'TA的课表',
      courses: [
        Course(
          id: 'c1',
          name: '高数',
          teacher: '张老师',
          location: 'A101',
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          startTime: '08:00',
          endTime: '09:40',
        ),
      ],
      settings: TimetableSettings.defaults(),
      currentWeek: 1,
    );
    await provider.importPartnerTimetable(backup);
    return provider;
  }

  test('无 pending 点击 → none（普通打开）', () async {
    final provider = await createProvider();
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);
    expect(outcome, WidgetLaunchOutcome.none);
    expect(provider.activeProfileId, isNotNull);
  });

  test('绑定的普通课表 → switchProfile 直达', () async {
    final provider = await createProvider();
    final other = await provider.createProfile(name: '秋季课表');

    pendingLaunch = const PendingHomeWidgetLaunch(appWidgetId: 33, side: null);
    bindings[33] = other.id;
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.switchedProfile);
    expect(provider.activeProfileId, other.id);
  });

  test('绑定 TA 课表但已解绑 → bindingMissing，不切课表', () async {
    final provider = await createProvider();
    final before = provider.activeProfileId;

    pendingLaunch = const PendingHomeWidgetLaunch(appWidgetId: 34, side: null);
    bindings[34] = PartnerTimetableService.partnerProfileId;
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.bindingMissing);
    expect(provider.activeProfileId, before);
  });

  test('未登记卡片 → none，保持当前课表', () async {
    final provider = await createProvider();
    final before = provider.activeProfileId;

    pendingLaunch = const PendingHomeWidgetLaunch(appWidgetId: 35, side: null);
    bindings[35] = null;
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.none);
    expect(provider.activeProfileId, before);
  });

  test('卡片右半 → 切到 TA 课表（原主界面展示），且不读取普通绑定', () async {
    final provider = await createProviderWithPartner();
    final before = provider.activeProfileId;

    pendingLaunch = const PendingHomeWidgetLaunch(
      appWidgetId: 38,
      side: 'right',
    );
    bindings[38] = 'must-not-be-read';
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.switchedProfile);
    expect(
      provider.activeProfileId,
      PartnerTimetableService.partnerProfileId,
    );
    // TA 课表真的成为当前课表（在原主界面展示）。
    expect(provider.activeProfile?.isPartnerImported, isTrue);
    expect(provider.activeProfileId, isNot(before));
  });

  test('卡片右半但未绑定 TA 课表 → bindingMissing，普通打开', () async {
    final provider = await createProvider();
    final before = provider.activeProfileId;

    pendingLaunch = const PendingHomeWidgetLaunch(
      appWidgetId: 41,
      side: 'right',
    );
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.bindingMissing);
    expect(provider.activeProfileId, before);
  });

  test('卡片左半（当前是我的课表）→ none，普通打开', () async {
    final provider = await createProviderWithPartner();
    final before = provider.activeProfileId;

    pendingLaunch = const PendingHomeWidgetLaunch(
      appWidgetId: 39,
      side: 'left',
    );
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.none);
    expect(provider.activeProfileId, before);
  });

  test('卡片左半（当前停在 TA 课表）→ 切回我最近使用的课表', () async {
    final provider = await createProviderWithPartner();
    final myProfileId = provider.activeProfileId!;

    // 先切到 TA（模拟点过右半），再点左半。
    pendingLaunch = const PendingHomeWidgetLaunch(
      appWidgetId: 42,
      side: 'right',
    );
    await WidgetLaunchRouter.handleWith(provider: provider);
    expect(
      provider.activeProfileId,
      PartnerTimetableService.partnerProfileId,
    );

    pendingLaunch = const PendingHomeWidgetLaunch(
      appWidgetId: 40,
      side: 'left',
    );
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.switchedProfile);
    expect(provider.activeProfileId, myProfileId);
    expect(provider.activeProfile?.isPartnerImported, isFalse);
  });

  test('绑定的普通课表已被删除 → switchProfile 守卫静默不动，仍算 switched', () async {
    final provider = await createProvider();
    final before = provider.activeProfileId;
    final other = await provider.createProfile(name: '被删课表');

    pendingLaunch = const PendingHomeWidgetLaunch(appWidgetId: 36, side: null);
    bindings[36] = other.id;
    await provider.deleteProfile(other.id);
    final outcome = await WidgetLaunchRouter.handleWith(provider: provider);

    expect(outcome, WidgetLaunchOutcome.switchedProfile);
    expect(provider.activeProfileId, before);
  });
}
