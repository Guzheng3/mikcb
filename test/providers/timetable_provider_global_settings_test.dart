import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/data/timetable_repository.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    StorageService().resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  Future<TimetableProvider> createProvider() async {
    final provider = TimetableProvider(
      autoInitialize: false,
      enableLiveActivitySync: false,
    );
    await provider.initialize();
    return provider;
  }

  test('without global settings the effective settings equal own settings',
      () async {
    final provider = await createProvider();
    expect(provider.globalSettings, isNull);
    expect(provider.settings.courseCardFontSize, 9);
  });

  test('global settings apply to timetable fields left at defaults', () async {
    final provider = await createProvider();
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(
        courseCardFontSize: 18,
        sectionHeight: 80,
        appThemeMode: AppThemeMode.dark,
      ),
    );

    expect(provider.globalSettings, isNotNull);
    expect(provider.settings.courseCardFontSize, 18);
    expect(provider.settings.sectionHeight, 80);
    expect(provider.settings.appThemeMode, AppThemeMode.dark);
    // 未在全局里配置过的字段保持自身默认。
    expect(provider.settings.courseCardShowName, isTrue);
  });

  test('timetable own settings override global settings per field', () async {
    final provider = await createProvider();
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(courseCardFontSize: 18),
    );

    // 当前课表把字号改成 20 —— 自身配置优先。
    await provider.updateTimetableSettings(
      provider.settings.copyWith(courseCardFontSize: 20),
    );
    expect(provider.settings.courseCardFontSize, 20);
    expect(provider.globalSettings!.courseCardFontSize, 18);

    // 新建的课表没改过字号 —— 跟随全局。
    final other = await provider.createProfile(name: '第二课表');
    await provider.switchProfile(other.id);
    expect(provider.settings.courseCardFontSize, 18);
  });

  test('profile-owned fields (semester/sections) never inherit global',
      () async {
    final provider = await createProvider();
    final customSections = [
      const SectionTime(startTime: '09:00', endTime: '09:45'),
      const SectionTime(startTime: '10:00', endTime: '10:45'),
    ];
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(
        semesterWeekCount: 8,
        semesterStartDate: DateTime(2026, 3, 2),
        sections: customSections,
      ),
    );

    expect(provider.settings.semesterWeekCount, 20);
    expect(provider.settings.semesterStartDate, isNull);
    expect(provider.settings.sections.length, 10);
  });

  test('editing one field does not pin inherited fields into the timetable',
      () async {
    final provider = await createProvider();
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(courseCardFontSize: 18),
    );

    // 只改自动适配行高这一个字段。
    await provider.updateTimetableSettings(
      provider.settings.copyWith(timetableAutoFitSectionHeight: true),
    );
    expect(provider.settings.timetableAutoFitSectionHeight, isTrue);

    // 未改动的字号仍然继承全局：全局再变，课表跟着变。
    await provider.updateGlobalTimetableSettings(
      provider.globalSettings!.copyWith(courseCardFontSize: 22),
    );
    expect(provider.settings.courseCardFontSize, 22);
    expect(provider.settings.timetableAutoFitSectionHeight, isTrue);

    // 清除全局后：改过的字段保留在课表自身，其余回到课表默认。
    await provider.clearGlobalTimetableSettings();
    expect(provider.globalSettings, isNull);
    expect(provider.settings.timetableAutoFitSectionHeight, isTrue);
    expect(provider.settings.courseCardFontSize, 9);
  });

  test('updateSettings (batch/theme path) also only pins changed fields',
      () async {
    final provider = await createProvider();
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(
        themeSeedColor: '#FF0000',
        courseCardFontSize: 15,
      ),
    );

    // 批量路径（主题导入等）改字号。
    await provider.updateSettings(
      provider.settings.copyWith(courseCardFontSize: 21),
    );
    expect(provider.settings.courseCardFontSize, 21);

    // 种子色仍是继承态：全局改，课表跟。
    await provider.updateGlobalTimetableSettings(
      provider.globalSettings!.copyWith(themeSeedColor: '#00FF00'),
    );
    expect(provider.settings.themeSeedColor, '#00FF00');
  });

  test('global settings persist across provider instances', () async {
    final provider = await createProvider();
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(courseCardFontSize: 24),
    );

    final reloaded = await createProvider();
    expect(reloaded.globalSettings, isNotNull);
    expect(reloaded.globalSettings!.courseCardFontSize, 24);
    expect(reloaded.settings.courseCardFontSize, 24);
  });

  test('clearing global settings persists and notifies', () async {
    final provider = await createProvider();
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(courseCardFontSize: 24),
    );
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.clearGlobalTimetableSettings();
    expect(notifications, greaterThanOrEqualTo(1));
    expect(provider.settings.courseCardFontSize, 9);

    final reloaded = await createProvider();
    expect(reloaded.globalSettings, isNull);
  });

  test('global settings follow profile switches', () async {
    final provider = await createProvider();
    final firstProfileId = provider.activeProfile!.id;
    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(timetableHideWeekends: true),
    );

    // 第一份课表自身把周末改回来（默认 false = 显示周末）。
    await provider.updateTimetableSettings(
      provider.settings.copyWith(timetableHideWeekends: false),
    );
    expect(provider.settings.timetableHideWeekends, isFalse);

    // 第二份课表未配置：跟随全局隐藏周末。
    final other = await provider.createProfile(name: '第二课表');
    expect(provider.settings.timetableHideWeekends, isTrue);

    // 切回第一份：自身配置仍然生效。
    await provider.switchProfile(firstProfileId);
    expect(provider.settings.timetableHideWeekends, isFalse);

    // 再切回第二份：仍然跟随全局。
    await provider.switchProfile(other.id);
    expect(provider.settings.timetableHideWeekends, isTrue);
  });

  test('legacy profiles without override-key records keep customized fields',
      () async {
    // 模拟升级前的历史课表：settingsOverrideKeys 为空（旧数据根本没有这个
    // 记账），但字号等字段已在设置页改过 —— 靠「与内置默认不同」的
    // 惰性判定识别为课表自身配置，不因全局设置的出现而丢失。
    final legacySettings = TimetableSettings.defaults().copyWith(
      courseCardFontSize: 14,
    );
    final legacyProfile = TimetableProfile(
      id: 'legacy-profile',
      name: '历史课表',
      courses: const [],
      settings: legacySettings,
      currentWeek: 1,
      createdAt: DateTime(2026, 2, 23),
      lastUsedAt: DateTime(2026, 2, 23),
    );
    final repository = TimetableRepository(StorageService());
    await repository.saveProfiles([legacyProfile]);
    await repository.setActiveProfileId(legacyProfile.id);

    final provider = await createProvider();
    expect(provider.activeProfile!.id, 'legacy-profile');
    expect(provider.settings.courseCardFontSize, 14);

    await provider.updateGlobalTimetableSettings(
      TimetableSettings.defaults().copyWith(
        courseCardFontSize: 20,
        sectionHeight: 88,
      ),
    );
    // 历史课表改过的字号保持自身值，从未动过的字段跟随全局。
    expect(provider.settings.courseCardFontSize, 14);
    expect(provider.settings.sectionHeight, 88);
  });
}
