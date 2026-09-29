import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/models/timetable_settings.dart';

void main() {
  test('defaults include semester week count and preserve it in json', () {
    final settings = TimetableSettings.defaults();

    expect(settings.semesterWeekCount, 20);
    expect(settings.timetableShowCurrentWeekCourses, isTrue);
    expect(settings.timetableShowNonCurrentWeekCourses, isFalse);
    expect(settings.showConflictBadgeOnTimetable, isTrue);
    expect(settings.timetableConflictCourseOpacity, 0.70);
    expect(settings.timetableVerticalScrollEffectEnabled, isFalse);
    expect(settings.liveHidePrefixText, isTrue);
    expect(settings.courseCardShowName, isTrue);
    expect(settings.courseCardShowTeacher, isTrue);
    expect(settings.courseCardShowLocation, isTrue);
    expect(settings.courseCardShowTime, isFalse);
    expect(settings.courseCardShowTimeLabels, isTrue);
    expect(settings.courseCardShowWeeks, isTrue);
    expect(settings.courseCardShowDescription, isFalse);
    expect(settings.timetableAutoFitSectionHeight, isTrue);
    expect(settings.widgetBackgroundStyle, WidgetBackgroundStyle.solid);
    expect(settings.widgetShowLocation, isTrue);
    expect(settings.widgetShowCountdown, isTrue);
    expect(settings.widgetHideCompletedCourses, isFalse);
    expect(settings.widgetHeightAdjustment, -11);
    expect(settings.widgetCornerRadius, 22);
    expect(settings.appThemeMode, AppThemeMode.system);
    expect(settings.homeTitleStyle, HomeTitleStyle.classic);
    expect(
      settings.timetableBackToCurrentWeekButtonStyle,
      BackToCurrentWeekButtonStyle.floating,
    );
    expect(settings.timetableFloatingBackToCurrentWeekButtonOpacity, 0.96);
    expect(
      settings.timetableSectionTimeDisplayMode,
      SectionTimeDisplayMode.startAndEnd,
    );
    expect(settings.timetableHideWeekends, isFalse);
    expect(settings.enableHaptics, isFalse);
    expect(
      settings.liveDuringClassTimeDisplayMode,
      LiveDuringClassTimeDisplayMode.nearest,
    );
    expect(settings.liveCountdownTextStyle, LiveCountdownTextStyle.smart);
    expect(settings.liveEnableMiuiIslandLabelImage, isFalse);
    expect(settings.liveHideFromRecents, isFalse);
    expect(settings.liveEnableLocalDiagnostics, isFalse);
    expect(settings.liveTimeCorrectionSeconds, 0);
    expect(
      settings.liveBeforeClassQuickAction,
      LiveBeforeClassQuickAction.none,
    );
    expect(settings.liveBeforeClassQuickActionAutoMinutes, 0);
    expect(settings.liveShowStageText, isTrue);
    expect(settings.liveMiuiIslandLabelStyle, MiuiIslandLabelStyle.textOnly);
    expect(
      settings.liveMiuiIslandLabelContent,
      MiuiIslandLabelContent.courseName,
    );
    expect(settings.liveMiuiIslandLabelFontColor, '#FFFFFF');
    expect(
      settings.liveMiuiIslandLabelFontWeight,
      MiuiIslandLabelFontWeight.bold,
    );
    expect(settings.liveMiuiIslandLabelFontSize, 14);
    expect(settings.liveMiuiIslandLabelOffsetX, 0);
    expect(settings.liveMiuiIslandLabelOffsetY, 0);
    expect(
      settings.liveMiuiIslandExpandedIconMode,
      MiuiIslandExpandedIconMode.appIcon,
    );
    expect(settings.liveMiuiIslandExpandedIconPath, isNull);
    expect(settings.appUpdateDownloadSource, 'mirror');
    expect(settings.appUpdateMirrorPreset, 'ghfast');
    expect(settings.appUpdateMirrorUrlPrefix, defaultAppUpdateMirrorUrlPrefix);
    expect(settings.courseCardVerticalAlign, CourseCardVerticalAlign.center);
    expect(
      settings.courseCardHorizontalAlign,
      CourseCardHorizontalAlign.center,
    );
    expect(settings.courseCardFontSize, 11.5);
    expect(
      settings.timetableTimeColumnWidthMode,
      TimetableTimeColumnWidthMode.narrow,
    );
    expect(settings.timetableCourseCardGap, 1.25);
    expect(
      settings.timetableCourseSpacingMode,
      TimetableCourseSpacingMode.narrow,
    );

    final restored = TimetableSettings.fromJson(settings.toJson());
    expect(restored.semesterWeekCount, 20);
    expect(restored.timetableShowCurrentWeekCourses, isTrue);
    expect(restored.timetableShowNonCurrentWeekCourses, isFalse);
    expect(restored.showConflictBadgeOnTimetable, isTrue);
    expect(restored.timetableConflictCourseOpacity, 0.70);
    expect(restored.timetableVerticalScrollEffectEnabled, isFalse);
    expect(restored.liveHidePrefixText, isTrue);
    expect(restored.courseCardShowName, isTrue);
    expect(restored.courseCardShowTeacher, isTrue);
    expect(restored.courseCardShowLocation, isTrue);
    expect(restored.courseCardShowTime, isFalse);
    expect(restored.courseCardShowTimeLabels, isTrue);
    expect(restored.courseCardShowWeeks, isTrue);
    expect(restored.courseCardShowDescription, isFalse);
    expect(restored.timetableAutoFitSectionHeight, isTrue);
    expect(restored.widgetBackgroundStyle, WidgetBackgroundStyle.solid);
    expect(restored.widgetShowLocation, isTrue);
    expect(restored.widgetShowCountdown, isTrue);
    expect(restored.widgetHideCompletedCourses, isFalse);
    expect(restored.widgetHeightAdjustment, -11);
    expect(restored.widgetCornerRadius, 22);
    expect(restored.appThemeMode, AppThemeMode.system);
    expect(restored.homeTitleStyle, HomeTitleStyle.classic);
    expect(
      restored.timetableBackToCurrentWeekButtonStyle,
      BackToCurrentWeekButtonStyle.floating,
    );
    expect(restored.timetableFloatingBackToCurrentWeekButtonOpacity, 0.96);
    expect(
      restored.timetableSectionTimeDisplayMode,
      SectionTimeDisplayMode.startAndEnd,
    );
    expect(restored.timetableHideWeekends, isFalse);
    expect(restored.enableHaptics, isFalse);
    expect(
      restored.liveDuringClassTimeDisplayMode,
      LiveDuringClassTimeDisplayMode.nearest,
    );
    expect(restored.liveCountdownTextStyle, LiveCountdownTextStyle.smart);
    expect(restored.liveEnableMiuiIslandLabelImage, isFalse);
    expect(restored.liveHideFromRecents, isFalse);
    expect(restored.liveEnableLocalDiagnostics, isFalse);
    expect(restored.liveTimeCorrectionSeconds, 0);
    expect(
      restored.liveBeforeClassQuickAction,
      LiveBeforeClassQuickAction.none,
    );
    expect(restored.liveShowStageText, isTrue);
    expect(restored.liveMiuiIslandLabelStyle, MiuiIslandLabelStyle.textOnly);
    expect(
      restored.liveMiuiIslandLabelContent,
      MiuiIslandLabelContent.courseName,
    );
    expect(restored.liveMiuiIslandLabelFontColor, '#FFFFFF');
    expect(
      restored.liveMiuiIslandLabelFontWeight,
      MiuiIslandLabelFontWeight.bold,
    );
    expect(restored.liveMiuiIslandLabelFontSize, 14);
    expect(restored.liveMiuiIslandLabelOffsetX, 0);
    expect(restored.liveMiuiIslandLabelOffsetY, 0);
    expect(
      restored.liveMiuiIslandExpandedIconMode,
      MiuiIslandExpandedIconMode.appIcon,
    );
    expect(restored.liveMiuiIslandExpandedIconPath, isNull);
    expect(restored.appUpdateDownloadSource, 'mirror');
    expect(restored.appUpdateMirrorPreset, 'ghfast');
    expect(restored.appUpdateMirrorUrlPrefix, defaultAppUpdateMirrorUrlPrefix);
    expect(restored.courseCardVerticalAlign, CourseCardVerticalAlign.center);
    expect(
      restored.courseCardHorizontalAlign,
      CourseCardHorizontalAlign.center,
    );
    expect(restored.courseCardFontSize, 11.5);
    expect(
      restored.timetableTimeColumnWidthMode,
      TimetableTimeColumnWidthMode.narrow,
    );
    expect(restored.timetableCourseCardGap, 1.25);
    expect(
      restored.timetableCourseSpacingMode,
      TimetableCourseSpacingMode.narrow,
    );
  });

  test('available weeks follow configured semester week count', () {
    final settings = TimetableSettings.defaults().copyWith(
      semesterWeekCount: 24,
    );

    expect(settings.availableWeeks, List.generate(24, (index) => index + 1));
  });

  test('settings preserve active time scheme id', () {
    final settings = TimetableSettings.defaults().copyWith(
      activeTimeSchemeId: 'scheme-1',
      timetableShowNonCurrentWeekCourses: true,
      showConflictBadgeOnTimetable: false,
      timetableConflictCourseOpacity: 0.55,
      timetableAutoFitSectionHeight: true,
      courseCardShowTime: true,
      courseCardShowTimeLabels: false,
      courseCardShowWeeks: true,
      widgetBackgroundStyle: WidgetBackgroundStyle.gradient,
      widgetShowLocation: false,
      widgetShowCountdown: false,
      widgetHideCompletedCourses: true,
      widgetHeightAdjustment: 12,
      widgetCornerRadius: 18,
      appThemeMode: AppThemeMode.dark,
      homeTitleStyle: HomeTitleStyle.brand,
      timetableBackToCurrentWeekButtonStyle:
          BackToCurrentWeekButtonStyle.floating,
      timetableFloatingBackToCurrentWeekButtonOpacity: 0.7,
      courseCardVerticalAlign: CourseCardVerticalAlign.spaceEvenly,
      courseCardHorizontalAlign: CourseCardHorizontalAlign.right,
      courseCardFontSize: 10.5,
      timetableTimeColumnWidthMode: TimetableTimeColumnWidthMode.wide,
      timetableCourseCardGap: 2.4,
      timetableCourseSpacingMode: TimetableCourseSpacingMode.wide,
      timetableSectionTimeDisplayMode: SectionTimeDisplayMode.startAndEnd,
      timetableHideWeekends: true,
      enableHaptics: false,
      liveDuringClassTimeDisplayMode: LiveDuringClassTimeDisplayMode.total,
      liveCountdownTextStyle: LiveCountdownTextStyle.minuteOnlyMin,
      liveEnableMiuiIslandLabelImage: true,
      liveHideFromRecents: true,
      liveEnableLocalDiagnostics: true,
      liveTimeCorrectionSeconds: -7,
      liveBeforeClassQuickAction: LiveBeforeClassQuickAction.doNotDisturb,
      liveBeforeClassQuickActionAutoMinutes: 15,
      liveShowStageText: false,
      liveMiuiIslandLabelStyle: MiuiIslandLabelStyle.iconAndText,
      liveMiuiIslandLabelContent: MiuiIslandLabelContent.courseNameAndLocation,
      liveMiuiIslandLabelFontColor: '#FDE68A',
      liveMiuiIslandLabelFontWeight: MiuiIslandLabelFontWeight.medium,
      liveMiuiIslandLabelFontSize: 18,
      liveMiuiIslandLabelOffsetX: 6,
      liveMiuiIslandLabelOffsetY: -3,
      liveMiuiIslandExpandedIconMode: MiuiIslandExpandedIconMode.customImage,
      liveMiuiIslandExpandedIconPath: '/tmp/expanded.png',
      appUpdateDownloadSource: AppUpdateDownloadSource.original.value,
      appUpdateMirrorPreset: AppUpdateMirrorPreset.custom.value,
      appUpdateMirrorUrlPrefix: 'https://mirror.example.com/',
    );

    final restored = TimetableSettings.fromJson(settings.toJson());

    expect(restored.activeTimeSchemeId, 'scheme-1');
    expect(restored.timetableShowCurrentWeekCourses, isTrue);
    expect(restored.timetableShowNonCurrentWeekCourses, isTrue);
    expect(restored.showConflictBadgeOnTimetable, isFalse);
    expect(restored.timetableConflictCourseOpacity, 0.55);
    expect(restored.timetableAutoFitSectionHeight, isTrue);
    expect(restored.courseCardShowTime, isTrue);
    expect(restored.courseCardShowTimeLabels, isFalse);
    expect(restored.courseCardShowWeeks, isTrue);
    expect(restored.widgetBackgroundStyle, WidgetBackgroundStyle.gradient);
    expect(restored.widgetShowLocation, isFalse);
    expect(restored.widgetShowCountdown, isFalse);
    expect(restored.widgetHideCompletedCourses, isTrue);
    expect(restored.widgetHeightAdjustment, 12);
    expect(restored.widgetCornerRadius, 18);
    expect(restored.appThemeMode, AppThemeMode.dark);
    expect(restored.homeTitleStyle, HomeTitleStyle.brand);
    expect(
      restored.timetableBackToCurrentWeekButtonStyle,
      BackToCurrentWeekButtonStyle.floating,
    );
    expect(restored.timetableFloatingBackToCurrentWeekButtonOpacity, 0.7);
    expect(
      restored.timetableSectionTimeDisplayMode,
      SectionTimeDisplayMode.startAndEnd,
    );
    expect(restored.timetableHideWeekends, isTrue);
    expect(restored.enableHaptics, isFalse);
    expect(
      restored.liveDuringClassTimeDisplayMode,
      LiveDuringClassTimeDisplayMode.total,
    );
    expect(
      restored.liveCountdownTextStyle,
      LiveCountdownTextStyle.minuteOnlyMin,
    );
    expect(restored.liveEnableMiuiIslandLabelImage, isTrue);
    expect(restored.liveHideFromRecents, isTrue);
    expect(restored.liveEnableLocalDiagnostics, isTrue);
    expect(restored.liveTimeCorrectionSeconds, -7);
    expect(
      restored.liveBeforeClassQuickAction,
      LiveBeforeClassQuickAction.doNotDisturb,
    );
    expect(restored.liveBeforeClassQuickActionAutoMinutes, 15);
    expect(restored.liveShowStageText, isFalse);
    expect(restored.liveMiuiIslandLabelStyle, MiuiIslandLabelStyle.iconAndText);
    expect(
      restored.liveMiuiIslandLabelContent,
      MiuiIslandLabelContent.courseNameAndLocation,
    );
    expect(restored.liveMiuiIslandLabelFontColor, '#FDE68A');
    expect(
      restored.liveMiuiIslandLabelFontWeight,
      MiuiIslandLabelFontWeight.medium,
    );
    expect(restored.liveMiuiIslandLabelFontSize, 18);
    expect(restored.liveMiuiIslandLabelOffsetX, 6);
    expect(restored.liveMiuiIslandLabelOffsetY, -3);
    expect(
      restored.liveMiuiIslandExpandedIconMode,
      MiuiIslandExpandedIconMode.customImage,
    );
    expect(restored.liveMiuiIslandExpandedIconPath, '/tmp/expanded.png');
    expect(
      restored.appUpdateDownloadSource,
      AppUpdateDownloadSource.original.value,
    );
    expect(restored.appUpdateMirrorPreset, AppUpdateMirrorPreset.custom.value);
    expect(restored.appUpdateMirrorUrlPrefix, 'https://mirror.example.com/');
    expect(
      restored.courseCardVerticalAlign,
      CourseCardVerticalAlign.spaceEvenly,
    );
    expect(restored.courseCardHorizontalAlign, CourseCardHorizontalAlign.right);
    expect(restored.courseCardFontSize, 10.5);
    expect(restored.timetableCourseCardGap, 2.4);
    expect(
      restored.timetableTimeColumnWidthMode,
      TimetableTimeColumnWidthMode.wide,
    );
    expect(
      restored.timetableCourseSpacingMode,
      TimetableCourseSpacingMode.wide,
    );
  });

  test('during and end live display settings always follow before class', () {
    // 课中/下课没有独立配置：整套 liveDuringEnd* 字段与其序列化已删除，
    // duringEndDisplaySettings 恒等于课前那一份。
    final settings = TimetableSettings.defaults().copyWith(
      liveShowCourseName: false,
      liveShowLocation: false,
      liveCountdownTextStyle: LiveCountdownTextStyle.secondOnlyShort,
      liveUseShortName: true,
      liveMiuiIslandLabelFontSize: 17,
    );

    final restored = TimetableSettings.fromJson(settings.toJson());
    final beforeClass = restored.beforeClassDisplaySettings;
    final duringEnd = restored.duringEndDisplaySettings;

    // 课前侧按设置取值，课中/下课逐项跟随（往返后依然如此）。
    expect(beforeClass.showCourseName, isFalse);
    expect(beforeClass.useShortName, isTrue);
    expect(beforeClass.miuiIslandLabelFontSize, 17);
    expect(duringEnd.showCourseName, beforeClass.showCourseName);
    expect(duringEnd.showLocation, beforeClass.showLocation);
    expect(duringEnd.showCountdown, beforeClass.showCountdown);
    expect(duringEnd.showStageText, beforeClass.showStageText);
    expect(duringEnd.useShortName, beforeClass.useShortName);
    expect(duringEnd.hidePrefixText, beforeClass.hidePrefixText);
    expect(duringEnd.countdownTextStyle, beforeClass.countdownTextStyle);
    expect(
      duringEnd.duringClassTimeDisplayMode,
      beforeClass.duringClassTimeDisplayMode,
    );
    expect(
      duringEnd.enableMiuiIslandLabelImage,
      beforeClass.enableMiuiIslandLabelImage,
    );
    expect(duringEnd.miuiIslandLabelStyle, beforeClass.miuiIslandLabelStyle);
    expect(
      duringEnd.miuiIslandLabelContent,
      beforeClass.miuiIslandLabelContent,
    );
    expect(
      duringEnd.miuiIslandLabelFontColor,
      beforeClass.miuiIslandLabelFontColor,
    );
    expect(
      duringEnd.miuiIslandLabelFontWeight,
      beforeClass.miuiIslandLabelFontWeight,
    );
    expect(
      duringEnd.miuiIslandLabelFontSize,
      beforeClass.miuiIslandLabelFontSize,
    );
    expect(
      duringEnd.miuiIslandLabelOffsetX,
      beforeClass.miuiIslandLabelOffsetX,
    );
    expect(
      duringEnd.miuiIslandLabelOffsetY,
      beforeClass.miuiIslandLabelOffsetY,
    );
    expect(
      duringEnd.miuiIslandExpandedIconMode,
      beforeClass.miuiIslandExpandedIconMode,
    );
    expect(
      duringEnd.miuiIslandExpandedIconPath,
      beforeClass.miuiIslandExpandedIconPath,
    );
  });

  test('legacy during/end keys are ignored except the time display mode', () {
    // 旧存档：follow 关掉、且各 liveDuringEnd* 字段另有取值。
    // 这些键已不再被读取，课中/下课一律沿用课前；唯一的例外是
    // liveDuringEndTimeDisplayMode —— 它曾是「课中时间样式」唯一的 UI，
    // 因此迁移进课前的 liveDuringClassTimeDisplayMode，避免静默回默认。
    final restored = TimetableSettings.fromJson({
      'liveShowCourseName': true,
      'liveDuringClassTimeDisplayMode':
          LiveDuringClassTimeDisplayMode.nearest.value,
      'liveDuringEndFollowBeforeClass': false,
      'liveDuringEndShowCourseName': false,
      'liveDuringEndShowLocation': false,
      'liveDuringEndUseShortName': false,
      'liveDuringEndTimeDisplayMode':
          LiveDuringClassTimeDisplayMode.total.value,
      'liveDuringEndMiuiIslandLabelFontSize': 17,
      'liveDuringEndMiuiIslandExpandedIconPath': '/tmp/during-end.png',
    });

    final beforeClass = restored.beforeClassDisplaySettings;
    final duringEnd = restored.duringEndDisplaySettings;

    expect(beforeClass.showCourseName, isTrue);
    expect(beforeClass.showLocation, isTrue);
    expect(duringEnd.showCourseName, beforeClass.showCourseName);
    expect(duringEnd.showLocation, beforeClass.showLocation);
    expect(duringEnd.useShortName, beforeClass.useShortName);
    expect(
      duringEnd.miuiIslandLabelFontSize,
      beforeClass.miuiIslandLabelFontSize,
    );
    expect(
      duringEnd.miuiIslandExpandedIconPath,
      beforeClass.miuiIslandExpandedIconPath,
    );
    // 唯一被迁移的旧值。
    expect(
      restored.liveDuringClassTimeDisplayMode,
      LiveDuringClassTimeDisplayMode.total,
    );
    expect(
      duringEnd.duringClassTimeDisplayMode,
      LiveDuringClassTimeDisplayMode.total,
    );
  });

  test('legacy spacing mode migrates to numeric card gap', () {
    final restored = TimetableSettings.fromJson({
      ...TimetableSettings.defaults().toJson(),
      'timetableCourseCardGap': null,
      'timetableCourseSpacingMode': 'wide',
    });

    expect(restored.timetableCourseCardGap, 2.0);
  });

  test('mirror preset resolves built-in and custom prefixes', () {
    expect(
      resolveAppUpdateMirrorUrlPrefix(
        preset: AppUpdateMirrorPreset.ghfast,
        customUrlPrefix: 'https://custom.example.com/',
      ),
      defaultAppUpdateMirrorUrlPrefix,
    );
    expect(
      resolveAppUpdateMirrorUrlPrefix(
        preset: AppUpdateMirrorPreset.custom,
        customUrlPrefix: 'https://custom.example.com/',
      ),
      'https://custom.example.com/',
    );
  });

  test('legacy mirror-only settings infer preset from saved prefix', () {
    final restored = TimetableSettings.fromJson({
      ...TimetableSettings.defaults().toJson(),
      'appUpdateMirrorPreset': null,
      'appUpdateMirrorUrlPrefix': 'https://mirror.example.com/',
    });

    expect(restored.appUpdateMirrorPreset, AppUpdateMirrorPreset.custom.value);
    expect(restored.appUpdateMirrorUrlPrefix, 'https://mirror.example.com/');
  });

  test('home page background settings roundtrip in json', () {
    final defaults = TimetableSettings.defaults();
    expect(defaults.homePageBackdropBlurSigma, 0.0);
    expect(defaults.homePageBackdropFrostAlpha, 0.0);

    final settings = TimetableSettings.defaults().copyWith(
      homePageBackgroundFill: HomePageBackgroundFill.image,
      homePageBackgroundImagePath: '/tmp/home_bg.png',
      homePageWallpaperPath: '/tmp/wallpaper.png',
      homePageBackdropBlurSigma: 12,
      homePageBackdropFrostAlpha: 0.4,
      homePageBackgroundScope:
          HomePageBackgroundScope.timetable | HomePageBackgroundScope.header,
    );

    final restored = TimetableSettings.fromJson(settings.toJson());
    expect(restored.homePageBackgroundFill, HomePageBackgroundFill.image);
    expect(restored.homePageBackgroundImagePath, '/tmp/home_bg.png');
    expect(restored.homePageWallpaperPath, '/tmp/wallpaper.png');
    expect(restored.homePageBackdropBlurSigma, 12.0);
    expect(restored.homePageBackdropFrostAlpha, 0.4);
    expect(
      HomePageBackgroundScope.includes(
        restored.homePageBackgroundScope,
        HomePageBackgroundScope.timetable,
      ),
      isTrue,
    );
    expect(
      HomePageBackgroundScope.includes(
        restored.homePageBackgroundScope,
        HomePageBackgroundScope.header,
      ),
      isTrue,
    );
    expect(
      HomePageBackgroundScope.includes(
        restored.homePageBackgroundScope,
        HomePageBackgroundScope.weekdayBar,
      ),
      isFalse,
    );
  });

  group('home top menu legacy settings', () {
    test('legacy menu style and grid order keys are ignored on import', () {
      // 八宫格形态与按钮排列自定义已移除；旧版本备份 JSON 里的这两个
      // 字段被 fromJson 直接忽略，不参与归一化也不再回写。
      final json = TimetableSettings.defaults().toJson()
        ..['homeMenuStyle'] = 'grid'
        ..['homeGridMenuActions'] = ['tasks', 'overview'];

      final restored = TimetableSettings.fromJson(json);
      final serialized = restored.toJson();
      expect(serialized.containsKey('homeMenuStyle'), isFalse);
      expect(serialized.containsKey('homeGridMenuActions'), isFalse);
    });
  });

  group('glass dock module tabs and extra button', () {
    test('defaults show all three tabs and add-course button action', () {
      final settings = TimetableSettings.defaults();

      expect(settings.glassDockShowDayTab, isTrue);
      expect(settings.glassDockShowWeekTab, isTrue);
      expect(settings.glassDockShowSettingsTab, isTrue);
      expect(settings.glassDockButtonEntryId, 'addCourse');
      expect(settings.glassDockShowAddButton, isFalse);
    });

    test('week tab toggle and button entry roundtrip in json', () {
      final settings = TimetableSettings.defaults().copyWith(
        glassDockShowWeekTab: false,
        glassDockButtonEntryId: 'exams',
        glassDockShowAddButton: false,
        glassDockButtonIconName: 'star',
      );

      final restored = TimetableSettings.fromJson(settings.toJson());
      expect(restored.glassDockShowWeekTab, isFalse);
      expect(restored.glassDockShowDayTab, isTrue);
      expect(restored.glassDockButtonEntryId, 'exams');
      expect(restored.glassDockShowAddButton, isFalse);
      expect(restored.glassDockButtonIconName, 'star');
    });

    test('missing json keys fall back to shipped defaults', () {
      final restored = TimetableSettings.fromJson(
        TimetableSettings.defaults().toJson()..remove('glassDockShowWeekTab'),
      );
      expect(restored.glassDockShowWeekTab, isTrue);

      final restored2 = TimetableSettings.fromJson(
        TimetableSettings.defaults().toJson()..remove('glassDockButtonEntryId'),
      );
      expect(restored2.glassDockButtonEntryId, 'addCourse');

      final restored3 = TimetableSettings.fromJson(
        TimetableSettings.defaults().toJson()..remove('glassDockShowAddButton'),
      );
      expect(restored3.glassDockShowAddButton, isFalse);
    });
  });

  group('linked course-card text colors self-heal', () {
    // 回归：联动开但详情色与标题色不同的脏状态（旧版本数据 / 主题备份）会
    // 让卡面画出「白标题 + 黑简介」的混色卡；加载与写入路径都要回填。
    Map<String, dynamic> dirtyJson({required bool? link}) => {
      'sections': <dynamic>[],
      'courseCardTitleColorLight': '#FFFFFF',
      'courseCardTitleColorDark': '#EEEEEE',
      'courseCardDetailColorLight': '#000000',
      'courseCardDetailColorDark': '#111111',
      'linkCourseCardColors': ?link,
    };

    test('fromJson heals divergent detail colors while linked', () {
      final settings = TimetableSettings.fromJson(dirtyJson(link: true));
      expect(
        settings.courseCardDetailColorLight,
        settings.courseCardTitleColorLight,
      );
      expect(
        settings.courseCardDetailColorDark,
        settings.courseCardTitleColorDark,
      );
    });

    test(
      'fromJson defaults to linked and heals legacy data without the key',
      () {
        final settings = TimetableSettings.fromJson(dirtyJson(link: null));
        expect(settings.linkCourseCardColors, isTrue);
        expect(
          settings.courseCardDetailColorLight,
          settings.courseCardTitleColorLight,
        );
        expect(
          settings.courseCardDetailColorDark,
          settings.courseCardTitleColorDark,
        );
      },
    );

    test('fromJson keeps explicit detail colors in independent mode', () {
      final settings = TimetableSettings.fromJson(dirtyJson(link: false));
      expect(settings.courseCardTitleColorLight, '#FFFFFF');
      expect(settings.courseCardDetailColorLight, '#000000');
      expect(settings.courseCardDetailColorDark, '#111111');
    });

    test('healed state persists through a json round trip', () {
      final settings = TimetableSettings.fromJson(dirtyJson(link: true));
      final restored = TimetableSettings.fromJson(settings.toJson());
      expect(
        restored.courseCardDetailColorLight,
        restored.courseCardTitleColorLight,
      );
      expect(
        restored.courseCardDetailColorDark,
        restored.courseCardTitleColorDark,
      );
    });

    test('copyWith heals a divergent state even without changes', () {
      // 直达构造函数注入的脏状态（绕过 copyWith）在下一次写入时被回填。
      const dirty = TimetableSettings(
        sections: [],
        courseCardDetailColorLight: '#000000',
        courseCardDetailColorDark: '#111111',
      );
      expect(dirty.linkCourseCardColors, isTrue);
      final healed = dirty.copyWith();
      expect(
        healed.courseCardDetailColorLight,
        healed.courseCardTitleColorLight,
      );
      expect(healed.courseCardDetailColorDark, healed.courseCardTitleColorDark);
    });

    test(
      'copyWith syncs the detail color when the title changes while linked',
      () {
        final changed = TimetableSettings.defaults().copyWith(
          courseCardTitleColorLight: '#0D47A1',
        );
        expect(changed.courseCardTitleColorLight, '#0D47A1');
        expect(changed.courseCardDetailColorLight, '#0D47A1');
      },
    );

    test('copyWith keeps user-picked detail colors in independent mode', () {
      final base = TimetableSettings.defaults().copyWith(
        linkCourseCardColors: false,
      );
      final changed = base.copyWith(courseCardDetailColorLight: '#123456');
      expect(changed.courseCardDetailColorLight, '#123456');
      expect(changed.courseCardTitleColorLight, '#FFFFFF');
    });

    test('liveBeforeClassQuickAction both value round-trips', () {
      final settings = TimetableSettings.defaults().copyWith(
        liveBeforeClassQuickAction: LiveBeforeClassQuickAction.both,
        liveBeforeClassQuickActionAutoMinutes: 10,
      );
      expect(settings.liveBeforeClassQuickAction.value, 'both');
      final restored = TimetableSettings.fromJson(settings.toJson());
      expect(
        restored.liveBeforeClassQuickAction,
        LiveBeforeClassQuickAction.both,
      );
      expect(restored.liveBeforeClassQuickActionAutoMinutes, 10);
      // 未知取值回落到 none，旧版本配置不受影响
      expect(
        TimetableSettings.fromJson(const {
          'liveBeforeClassQuickAction': 'unknown_action',
        }).liveBeforeClassQuickAction,
        LiveBeforeClassQuickAction.none,
      );
    });
  });

  group('情侣详情卡片开关', () {
    test('默认开启，copyWith 与 JSON 往返保持', () {
      final defaults = TimetableSettings.defaults();
      expect(defaults.coupleTimetableDetailCardEnabled, isTrue);

      final off = defaults.copyWith(coupleTimetableDetailCardEnabled: false);
      expect(off.coupleTimetableDetailCardEnabled, isFalse);

      final restored = TimetableSettings.fromJson(off.toJson());
      expect(restored.coupleTimetableDetailCardEnabled, isFalse);

      // 旧配置缺 key 时回落到默认开启。
      expect(
        TimetableSettings.fromJson(const {}).coupleTimetableDetailCardEnabled,
        isTrue,
      );
    });
  });
}
