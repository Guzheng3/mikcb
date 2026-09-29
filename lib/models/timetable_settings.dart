import 'dart:convert';
import 'package:university_timetable/ui/hyperos/frosted/frosted_appearance.dart';
import 'package:university_timetable/models/class_reminder.dart';

/// Bundled default wallpaper used when no user wallpaper is configured.
const String defaultHomePageWallpaperPath =
    'asset://assets/home_page_wallpaper/default.jpg';

enum AppUpdateDownloadSource { original, mirror }

enum AppUpdateMirrorPreset { ghfast, ghLlkk, ghProxyCom, ghproxyNet, custom }

enum WidgetBackgroundStyle { glass, solid, gradient }

enum AppThemeMode { system, light, dark }

enum AppFontMode {
  system,
  sansSerif,
  miSans,
  harmonyOS,
  oppoSans,
  pingFang,
  notoSans,
  serif,
  songti,
  monospace,
}

enum HomeTitleStyle { classic, brand }

enum HomePageBackgroundFill { color, image }

extension HomePageBackgroundFillX on HomePageBackgroundFill {
  String get value => name;

  static HomePageBackgroundFill fromValue(String? value) {
    return HomePageBackgroundFill.values.firstWhere(
      (item) => item.value == value,
      orElse: () => HomePageBackgroundFill.color,
    );
  }
}

/// Bit flags for home page background display regions.
abstract final class HomePageBackgroundScope {
  static const int timetable = 1;
  static const int weekdayBar = 2;
  static const int header = 4;
  static const int statusBar = 8;

  /// 默认铺满状态栏、顶栏、信息栏与课表区域（无壁纸时无感知）。
  static const int defaultValue = timetable | weekdayBar | header | statusBar;

  static bool includes(int scope, int region) => (scope & region) != 0;

  static int toggle(int scope, int region, {required bool enabled}) {
    return enabled ? (scope | region) : (scope & ~region);
  }
}

enum TimetableHomeViewMode { week, day }

/// 首页导航形态：经典形态保持原样；玻璃坞形态在底部提供液态玻璃
/// 药丸导航，滑动/点击即可切换周课表、日课表与设置。
enum HomeNavigationForm { classic, glassDock }

/// 首页右上角「更多」列表菜单的默认动作 id 排列。
///
/// id 是稳定主键（内置项沿用旧 HomeTopMenuAction.name，其余来自 UI
/// 目录 kHomeMenuCatalog）；模型层不感知具体条目含义（避免反向依赖
/// widgets），未知 id 由 UI 层解析时丢弃。
abstract final class HomeMenuDefaults {
  /// 已发布版本的默认排列（不含后来新增的任务入口）。
  static const List<String> defaultActions = [
    'overview',
    'statistics',
    'addCourse',
    'exams',
    'importCourses',
    'settings',
  ];
}

/// 玻璃坞底栏按钮的槽位约束与默认排列。
///
/// id 语义：'day' / 'week' 是视图切换动作，其余 id 走首页菜单目录
/// （kHomeMenuCatalog，含 'settings'）。空排列合法——渲染层回退到
/// [defaultActions]，因此不做钉住补位。
abstract final class HomeDockMenu {
  /// 底栏最多容纳的按钮数量（含视图切换与页面入口）。
  static const int maxSlots = 5;

  static const List<String> defaultActions = <String>['day', 'week'];

  static List<String> normalize(Iterable<Object?>? raw) {
    if (raw == null) {
      return const <String>[];
    }
    final unique = <String>[];
    for (final item in raw) {
      if (item is String && item.isNotEmpty && !unique.contains(item)) {
        unique.add(item);
      }
    }
    if (unique.length > maxSlots) {
      unique.removeRange(maxSlots, unique.length);
    }
    return List<String>.unmodifiable(unique);
  }
}

enum BackToCurrentWeekButtonStyle { inline, floating }

enum SectionTimeDisplayMode { hidden, startOnly, startAndEnd }

enum LiveDuringClassTimeDisplayMode { nearest, total }

enum LiveCountdownTextStyle {
  smart,
  smartMinS,
  minuteSecondCn,
  minuteSecondColon,
  minuteSecondMinS,
  minuteSecondMinSlashS,
  minuteOnlyCn,
  minuteOnlyMin,
  minuteOnlySlash,
  secondOnlyCn,
  secondOnlyShort,
  secondOnlySlash,
}

enum MiuiIslandLabelStyle { textOnly, iconAndText }

enum MiuiIslandLabelContent { courseName, location, courseNameAndLocation }

enum MiuiIslandLabelFontWeight { regular, medium, bold }

enum MiuiIslandLabelRenderQuality { standard, high, ultra }

enum MiuiIslandExpandedIconMode { appIcon, customImage, hidden }

enum LiveBeforeClassQuickAction { none, silent, doNotDisturb, both }

const String defaultAppUpdateMirrorUrlPrefix = 'https://ghfast.top/';
const String ghLlkkMirrorUrlPrefix = 'https://gh.llkk.cc/';
const String ghProxyComMirrorUrlPrefix = 'https://gh-proxy.com/';
const String ghproxyNetMirrorUrlPrefix = 'https://ghproxy.net/';

String _normalizeAppLocaleTag(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.isEmpty || normalized == 'system') {
    return '';
  }
  final canonical = normalized.replaceAll('-', '_');
  final lower = canonical.toLowerCase();
  if (lower == 'en_us') return 'en';
  if (lower == 'zh_cn') return 'zh';
  return canonical;
}

String _normalizeMirrorUrlPrefixValue(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

String _migrateLegacyLightChromeInkToWhite(
  String? value,
  String legacyDefault,
) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized.isEmpty) {
    return '#FFFFFF';
  }
  if (normalized == legacyDefault.toLowerCase()) {
    return '#FFFFFF';
  }
  return value!;
}

extension SectionTimeDisplayModeX on SectionTimeDisplayMode {
  String get value => switch (this) {
    SectionTimeDisplayMode.hidden => 'hidden',
    SectionTimeDisplayMode.startOnly => 'start_only',
    SectionTimeDisplayMode.startAndEnd => 'start_and_end',
  };

  static SectionTimeDisplayMode fromValue(String? value) {
    return SectionTimeDisplayMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => SectionTimeDisplayMode.startAndEnd,
    );
  }
}

extension WidgetBackgroundStyleX on WidgetBackgroundStyle {
  String get value => switch (this) {
    WidgetBackgroundStyle.glass => 'glass',
    WidgetBackgroundStyle.solid => 'solid',
    WidgetBackgroundStyle.gradient => 'gradient',
  };

  static WidgetBackgroundStyle fromValue(String? value) {
    return WidgetBackgroundStyle.values.firstWhere(
      (item) => item.value == value,
      orElse: () => WidgetBackgroundStyle.solid,
    );
  }
}

extension AppThemeModeX on AppThemeMode {
  String get value => switch (this) {
    AppThemeMode.system => 'system',
    AppThemeMode.light => 'light',
    AppThemeMode.dark => 'dark',
  };

  static AppThemeMode fromValue(String? value) {
    return AppThemeMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AppThemeMode.system,
    );
  }
}

extension AppFontModeX on AppFontMode {
  String get value => switch (this) {
    AppFontMode.system => 'system',
    AppFontMode.sansSerif => 'sans_serif',
    AppFontMode.miSans => 'mi_sans',
    AppFontMode.harmonyOS => 'harmony_os',
    AppFontMode.oppoSans => 'oppo_sans',
    AppFontMode.pingFang => 'ping_fang',
    AppFontMode.notoSans => 'noto_sans',
    AppFontMode.serif => 'serif',
    AppFontMode.songti => 'songti',
    AppFontMode.monospace => 'monospace',
  };

  static AppFontMode fromValue(String? value) {
    return AppFontMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AppFontMode.system,
    );
  }
}

extension HomeTitleStyleX on HomeTitleStyle {
  String get value => switch (this) {
    HomeTitleStyle.classic => 'classic',
    HomeTitleStyle.brand => 'brand',
  };

  static HomeTitleStyle fromValue(String? value) {
    return HomeTitleStyle.values.firstWhere(
      (item) => item.value == value,
      orElse: () => HomeTitleStyle.classic,
    );
  }
}

extension TimetableHomeViewModeX on TimetableHomeViewMode {
  String get value => switch (this) {
    TimetableHomeViewMode.week => 'week',
    TimetableHomeViewMode.day => 'day',
  };

  static TimetableHomeViewMode fromValue(String? value) {
    return TimetableHomeViewMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TimetableHomeViewMode.week,
    );
  }
}

extension HomeNavigationFormX on HomeNavigationForm {
  String get value => switch (this) {
    HomeNavigationForm.classic => 'classic',
    HomeNavigationForm.glassDock => 'glass_dock',
  };

  static HomeNavigationForm fromValue(String? value) {
    return HomeNavigationForm.values.firstWhere(
      (item) => item.value == value,
      orElse: () => HomeNavigationForm.classic,
    );
  }
}

extension BackToCurrentWeekButtonStyleX on BackToCurrentWeekButtonStyle {
  String get value => switch (this) {
    BackToCurrentWeekButtonStyle.inline => 'inline',
    BackToCurrentWeekButtonStyle.floating => 'floating',
  };

  /// 解析旧档：inline（时间栏内嵌小字）已收敛为浮钮唯一入口，
  /// 存量 'inline' 值迁移为 floating；枚举保留两值仅为兼容旧 JSON。
  static BackToCurrentWeekButtonStyle fromValue(String? value) {
    if (value == 'floating') {
      return BackToCurrentWeekButtonStyle.floating;
    }
    // 'inline' 与未知值一律落到 floating。
    return BackToCurrentWeekButtonStyle.floating;
  }
}

extension LiveDuringClassTimeDisplayModeX on LiveDuringClassTimeDisplayMode {
  String get value => switch (this) {
    LiveDuringClassTimeDisplayMode.nearest => 'nearest',
    LiveDuringClassTimeDisplayMode.total => 'total',
  };

  static LiveDuringClassTimeDisplayMode fromValue(String? value) {
    return LiveDuringClassTimeDisplayMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => LiveDuringClassTimeDisplayMode.nearest,
    );
  }
}

extension LiveCountdownTextStyleX on LiveCountdownTextStyle {
  String get value => switch (this) {
    LiveCountdownTextStyle.smart => 'smart',
    LiveCountdownTextStyle.smartMinS => 'smart_min_s',
    LiveCountdownTextStyle.minuteSecondCn => 'minute_second_cn',
    LiveCountdownTextStyle.minuteSecondColon => 'minute_second_colon',
    LiveCountdownTextStyle.minuteSecondMinS => 'minute_second_min_s',
    LiveCountdownTextStyle.minuteSecondMinSlashS => 'minute_second_min_slash_s',
    LiveCountdownTextStyle.minuteOnlyCn => 'minute_only_cn',
    LiveCountdownTextStyle.minuteOnlyMin => 'minute_only_min',
    LiveCountdownTextStyle.minuteOnlySlash => 'minute_only_slash',
    LiveCountdownTextStyle.secondOnlyCn => 'second_only_cn',
    LiveCountdownTextStyle.secondOnlyShort => 'second_only_short',
    LiveCountdownTextStyle.secondOnlySlash => 'second_only_slash',
  };

  bool get alwaysShowsSeconds => switch (this) {
    LiveCountdownTextStyle.minuteSecondCn ||
    LiveCountdownTextStyle.minuteSecondColon ||
    LiveCountdownTextStyle.minuteSecondMinS ||
    LiveCountdownTextStyle.minuteSecondMinSlashS ||
    LiveCountdownTextStyle.secondOnlyCn ||
    LiveCountdownTextStyle.secondOnlyShort ||
    LiveCountdownTextStyle.secondOnlySlash => true,
    _ => false,
  };

  static LiveCountdownTextStyle fromValue(String? value) {
    return LiveCountdownTextStyle.values.firstWhere(
      (item) => item.value == value,
      orElse: () => LiveCountdownTextStyle.smart,
    );
  }
}

extension MiuiIslandLabelStyleX on MiuiIslandLabelStyle {
  String get value => switch (this) {
    MiuiIslandLabelStyle.textOnly => 'text_only',
    MiuiIslandLabelStyle.iconAndText => 'icon_and_text',
  };

  static MiuiIslandLabelStyle fromValue(String? value) {
    return MiuiIslandLabelStyle.values.firstWhere(
      (item) => item.value == value,
      orElse: () => MiuiIslandLabelStyle.textOnly,
    );
  }
}

extension MiuiIslandLabelContentX on MiuiIslandLabelContent {
  String get value => switch (this) {
    MiuiIslandLabelContent.courseName => 'course_name',
    MiuiIslandLabelContent.location => 'location',
    MiuiIslandLabelContent.courseNameAndLocation => 'course_name_and_location',
  };

  static MiuiIslandLabelContent fromValue(String? value) {
    return MiuiIslandLabelContent.values.firstWhere(
      (item) => item.value == value,
      orElse: () => MiuiIslandLabelContent.courseName,
    );
  }
}

extension MiuiIslandLabelFontWeightX on MiuiIslandLabelFontWeight {
  String get value => switch (this) {
    MiuiIslandLabelFontWeight.regular => 'regular',
    MiuiIslandLabelFontWeight.medium => 'medium',
    MiuiIslandLabelFontWeight.bold => 'bold',
  };

  static MiuiIslandLabelFontWeight fromValue(String? value) {
    return MiuiIslandLabelFontWeight.values.firstWhere(
      (item) => item.value == value,
      orElse: () => MiuiIslandLabelFontWeight.bold,
    );
  }
}

extension MiuiIslandLabelRenderQualityX on MiuiIslandLabelRenderQuality {
  String get value => switch (this) {
    MiuiIslandLabelRenderQuality.standard => 'standard',
    MiuiIslandLabelRenderQuality.high => 'high',
    MiuiIslandLabelRenderQuality.ultra => 'ultra',
  };

  static MiuiIslandLabelRenderQuality fromValue(String? value) {
    return MiuiIslandLabelRenderQuality.values.firstWhere(
      (item) => item.value == value,
      orElse: () => MiuiIslandLabelRenderQuality.standard,
    );
  }
}

extension MiuiIslandExpandedIconModeX on MiuiIslandExpandedIconMode {
  String get value => switch (this) {
    MiuiIslandExpandedIconMode.appIcon => 'app_icon',
    MiuiIslandExpandedIconMode.customImage => 'custom_image',
    MiuiIslandExpandedIconMode.hidden => 'hidden',
  };

  static MiuiIslandExpandedIconMode fromValue(String? value) {
    return MiuiIslandExpandedIconMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => MiuiIslandExpandedIconMode.appIcon,
    );
  }
}

extension LiveBeforeClassQuickActionX on LiveBeforeClassQuickAction {
  String get value => switch (this) {
    LiveBeforeClassQuickAction.none => 'none',
    LiveBeforeClassQuickAction.silent => 'silent',
    LiveBeforeClassQuickAction.doNotDisturb => 'do_not_disturb',
    LiveBeforeClassQuickAction.both => 'both',
  };

  static LiveBeforeClassQuickAction fromValue(String? value) {
    return LiveBeforeClassQuickAction.values.firstWhere(
      (item) => item.value == value,
      orElse: () => LiveBeforeClassQuickAction.none,
    );
  }
}

enum CourseCardVerticalAlign { top, center, bottom, spaceEvenly }

extension CourseCardVerticalAlignX on CourseCardVerticalAlign {
  String get value => switch (this) {
    CourseCardVerticalAlign.top => 'top',
    CourseCardVerticalAlign.center => 'center',
    CourseCardVerticalAlign.bottom => 'bottom',
    CourseCardVerticalAlign.spaceEvenly => 'space_evenly',
  };

  static CourseCardVerticalAlign fromValue(String? value) {
    return CourseCardVerticalAlign.values.firstWhere(
      (item) => item.value == value,
      orElse: () => CourseCardVerticalAlign.center,
    );
  }
}

enum CourseCardHorizontalAlign { left, center, right }

extension CourseCardHorizontalAlignX on CourseCardHorizontalAlign {
  String get value => switch (this) {
    CourseCardHorizontalAlign.left => 'left',
    CourseCardHorizontalAlign.center => 'center',
    CourseCardHorizontalAlign.right => 'right',
  };

  static CourseCardHorizontalAlign fromValue(String? value) {
    return CourseCardHorizontalAlign.values.firstWhere(
      (item) => item.value == value,
      orElse: () => CourseCardHorizontalAlign.center,
    );
  }
}

enum TimetableTimeColumnWidthMode { narrow, wide }

extension TimetableTimeColumnWidthModeX on TimetableTimeColumnWidthMode {
  String get value => switch (this) {
    TimetableTimeColumnWidthMode.narrow => 'narrow',
    TimetableTimeColumnWidthMode.wide => 'wide',
  };

  static TimetableTimeColumnWidthMode fromValue(String? value) {
    return TimetableTimeColumnWidthMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TimetableTimeColumnWidthMode.narrow,
    );
  }
}

enum TimetableCourseSpacingMode { narrow, wide }

extension TimetableCourseSpacingModeX on TimetableCourseSpacingMode {
  String get value => switch (this) {
    TimetableCourseSpacingMode.narrow => 'narrow',
    TimetableCourseSpacingMode.wide => 'wide',
  };

  static TimetableCourseSpacingMode fromValue(String? value) {
    return TimetableCourseSpacingMode.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TimetableCourseSpacingMode.narrow,
    );
  }
}

extension AppUpdateDownloadSourceX on AppUpdateDownloadSource {
  String get value => switch (this) {
    AppUpdateDownloadSource.original => 'original',
    AppUpdateDownloadSource.mirror => 'mirror',
  };

  static AppUpdateDownloadSource fromValue(String? value) {
    return AppUpdateDownloadSource.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AppUpdateDownloadSource.mirror,
    );
  }
}

extension AppUpdateMirrorPresetX on AppUpdateMirrorPreset {
  String get value => switch (this) {
    AppUpdateMirrorPreset.ghfast => 'ghfast',
    AppUpdateMirrorPreset.ghLlkk => 'gh_llkk',
    AppUpdateMirrorPreset.ghProxyCom => 'gh_proxy_com',
    AppUpdateMirrorPreset.ghproxyNet => 'ghproxy_net',
    AppUpdateMirrorPreset.custom => 'custom',
  };

  bool get usesCustomUrl => this == AppUpdateMirrorPreset.custom;

  static AppUpdateMirrorPreset fromValue(String? value) {
    return AppUpdateMirrorPreset.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AppUpdateMirrorPreset.ghfast,
    );
  }

  static AppUpdateMirrorPreset fromUrlPrefix(String? urlPrefix) {
    final normalized = _normalizeMirrorUrlPrefixValue(urlPrefix);
    if (normalized.isEmpty ||
        normalized ==
            _normalizeMirrorUrlPrefixValue(defaultAppUpdateMirrorUrlPrefix)) {
      return AppUpdateMirrorPreset.ghfast;
    }
    if (normalized == _normalizeMirrorUrlPrefixValue(ghLlkkMirrorUrlPrefix)) {
      return AppUpdateMirrorPreset.ghLlkk;
    }
    if (normalized ==
        _normalizeMirrorUrlPrefixValue(ghProxyComMirrorUrlPrefix)) {
      return AppUpdateMirrorPreset.ghProxyCom;
    }
    if (normalized ==
        _normalizeMirrorUrlPrefixValue(ghproxyNetMirrorUrlPrefix)) {
      return AppUpdateMirrorPreset.ghproxyNet;
    }
    return AppUpdateMirrorPreset.custom;
  }
}

String resolveAppUpdateMirrorUrlPrefix({
  required AppUpdateMirrorPreset preset,
  required String customUrlPrefix,
}) {
  final normalizedCustomUrlPrefix = customUrlPrefix.trim();
  return switch (preset) {
    AppUpdateMirrorPreset.ghfast => defaultAppUpdateMirrorUrlPrefix,
    AppUpdateMirrorPreset.ghLlkk => ghLlkkMirrorUrlPrefix,
    AppUpdateMirrorPreset.ghProxyCom => ghProxyComMirrorUrlPrefix,
    AppUpdateMirrorPreset.ghproxyNet => ghproxyNetMirrorUrlPrefix,
    AppUpdateMirrorPreset.custom =>
      normalizedCustomUrlPrefix.isEmpty
          ? defaultAppUpdateMirrorUrlPrefix
          : normalizedCustomUrlPrefix,
  };
}

class LiveDisplaySettings {
  final bool showCourseName;
  final bool showLocation;
  final bool showCountdown;
  final LiveCountdownTextStyle countdownTextStyle;
  final bool showStageText;
  final bool useShortName;
  final bool hidePrefixText;
  final LiveDuringClassTimeDisplayMode duringClassTimeDisplayMode;
  final bool enableMiuiIslandLabelImage;
  final MiuiIslandLabelStyle miuiIslandLabelStyle;
  final MiuiIslandLabelContent miuiIslandLabelContent;
  final String miuiIslandLabelFontColor;
  final MiuiIslandLabelFontWeight miuiIslandLabelFontWeight;
  final MiuiIslandLabelRenderQuality miuiIslandLabelRenderQuality;
  final double miuiIslandLabelFontSize;
  final double miuiIslandLabelOffsetX;
  final double miuiIslandLabelOffsetY;
  final String? miuiIslandLabelLogoPath;
  final double miuiIslandLabelLogoCornerRadius;
  final MiuiIslandExpandedIconMode miuiIslandExpandedIconMode;
  final String? miuiIslandExpandedIconPath;

  const LiveDisplaySettings({
    required this.showCourseName,
    required this.showLocation,
    required this.showCountdown,
    required this.countdownTextStyle,
    required this.showStageText,
    required this.useShortName,
    required this.hidePrefixText,
    required this.duringClassTimeDisplayMode,
    required this.enableMiuiIslandLabelImage,
    required this.miuiIslandLabelStyle,
    required this.miuiIslandLabelContent,
    required this.miuiIslandLabelFontColor,
    required this.miuiIslandLabelFontWeight,
    required this.miuiIslandLabelRenderQuality,
    required this.miuiIslandLabelFontSize,
    required this.miuiIslandLabelOffsetX,
    required this.miuiIslandLabelOffsetY,
    required this.miuiIslandLabelLogoPath,
    required this.miuiIslandLabelLogoCornerRadius,
    required this.miuiIslandExpandedIconMode,
    required this.miuiIslandExpandedIconPath,
  });

  LiveDisplaySettings copyWith({
    bool? showCourseName,
    bool? showLocation,
    bool? showCountdown,
    LiveCountdownTextStyle? countdownTextStyle,
    bool? showStageText,
    bool? useShortName,
    bool? hidePrefixText,
    LiveDuringClassTimeDisplayMode? duringClassTimeDisplayMode,
    bool? enableMiuiIslandLabelImage,
    MiuiIslandLabelStyle? miuiIslandLabelStyle,
    MiuiIslandLabelContent? miuiIslandLabelContent,
    String? miuiIslandLabelFontColor,
    MiuiIslandLabelFontWeight? miuiIslandLabelFontWeight,
    MiuiIslandLabelRenderQuality? miuiIslandLabelRenderQuality,
    double? miuiIslandLabelFontSize,
    double? miuiIslandLabelOffsetX,
    double? miuiIslandLabelOffsetY,
    String? miuiIslandLabelLogoPath,
    bool clearMiuiIslandLabelLogoPath = false,
    double? miuiIslandLabelLogoCornerRadius,
    MiuiIslandExpandedIconMode? miuiIslandExpandedIconMode,
    String? miuiIslandExpandedIconPath,
    bool clearMiuiIslandExpandedIconPath = false,
  }) {
    return LiveDisplaySettings(
      showCourseName: showCourseName ?? this.showCourseName,
      showLocation: showLocation ?? this.showLocation,
      showCountdown: showCountdown ?? this.showCountdown,
      countdownTextStyle: countdownTextStyle ?? this.countdownTextStyle,
      showStageText: showStageText ?? this.showStageText,
      useShortName: useShortName ?? this.useShortName,
      hidePrefixText: hidePrefixText ?? this.hidePrefixText,
      duringClassTimeDisplayMode:
          duringClassTimeDisplayMode ?? this.duringClassTimeDisplayMode,
      enableMiuiIslandLabelImage:
          enableMiuiIslandLabelImage ?? this.enableMiuiIslandLabelImage,
      miuiIslandLabelStyle: miuiIslandLabelStyle ?? this.miuiIslandLabelStyle,
      miuiIslandLabelContent:
          miuiIslandLabelContent ?? this.miuiIslandLabelContent,
      miuiIslandLabelFontColor:
          miuiIslandLabelFontColor ?? this.miuiIslandLabelFontColor,
      miuiIslandLabelFontWeight:
          miuiIslandLabelFontWeight ?? this.miuiIslandLabelFontWeight,
      miuiIslandLabelRenderQuality:
          miuiIslandLabelRenderQuality ?? this.miuiIslandLabelRenderQuality,
      miuiIslandLabelFontSize:
          miuiIslandLabelFontSize ?? this.miuiIslandLabelFontSize,
      miuiIslandLabelOffsetX:
          miuiIslandLabelOffsetX ?? this.miuiIslandLabelOffsetX,
      miuiIslandLabelOffsetY:
          miuiIslandLabelOffsetY ?? this.miuiIslandLabelOffsetY,
      miuiIslandLabelLogoPath: clearMiuiIslandLabelLogoPath
          ? null
          : miuiIslandLabelLogoPath ?? this.miuiIslandLabelLogoPath,
      miuiIslandLabelLogoCornerRadius:
          miuiIslandLabelLogoCornerRadius ??
          this.miuiIslandLabelLogoCornerRadius,
      miuiIslandExpandedIconMode:
          miuiIslandExpandedIconMode ?? this.miuiIslandExpandedIconMode,
      miuiIslandExpandedIconPath: clearMiuiIslandExpandedIconPath
          ? null
          : miuiIslandExpandedIconPath ?? this.miuiIslandExpandedIconPath,
    );
  }
}

class SectionTime {
  final String startTime;
  final String endTime;

  const SectionTime({required this.startTime, required this.endTime});

  Map<String, dynamic> toJson() {
    return {'startTime': startTime, 'endTime': endTime};
  }

  factory SectionTime.fromJson(Map<String, dynamic> json) {
    final rawStart = json['startTime'];
    final rawEnd = json['endTime'];
    if (rawStart is! String || rawStart.trim().isEmpty) {
      throw const FormatException('missing section startTime');
    }
    if (rawEnd is! String || rawEnd.trim().isEmpty) {
      throw const FormatException('missing section endTime');
    }
    return SectionTime(startTime: rawStart, endTime: rawEnd);
  }

  SectionTime copyWith({String? startTime, String? endTime}) {
    return SectionTime(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  String get displayText => '$startTime-$endTime';
}

class TimetableSettings {
  // 颜色默认值常量
  static const String defaultCourseCardTitleColor = '#FFFFFF';
  static const String defaultCourseCardDetailColor = '#FFFFFF';
  static const String defaultWeekdayBarFontColorLight = '#FFFFFF';
  static const String defaultWeekdayBarFontColorDark = '#FFFFFF';
  static const String defaultWeekdayBarAccentColorLight = '#2563EB';
  static const String defaultWeekdayBarAccentColorDark = '#93C5FD';
  static const String defaultTimeAxisFontColorLight = '#FFFFFF';
  static const String defaultTimeAxisFontColorDark = '#FFFFFF';

  static const double defaultFrostedSheetBlurSigma = 15;
  static const double defaultFrostedSheetTintAlpha = 0.70;
  static const double defaultFrostedSheetBarrierAlpha = 0.20;
  static const bool defaultFrostedBlurEnabled = true;

  /// 应用主题色（唯一选项：蓝）。历史上的主题色选择器/主题库已删除，
  /// 此值不再随用户设置变化；旧数据中的其他主题色在读取时被丢弃。
  static const String defaultThemeSeedColor = '#2563EB';

  static const double defaultPageTransitionSpeed = 1;
  static const double minPageTransitionSpeed = 0.5;
  static const double maxPageTransitionSpeed = 2.5;

  final List<SectionTime> sections;
  final String? activeTimeSchemeId;
  final double sectionHeight;
  final double compactFontSize;
  final bool timetableAutoFitSectionHeight;
  final int semesterWeekCount;
  final DateTime? semesterStartDate;
  final bool weeklyReportEnabled;
  final bool enableHolidayMarking;
  final bool timetableShowCurrentWeekCourses;
  final bool timetableShowNonCurrentWeekCourses;
  final bool showConflictBadgeOnTimetable;
  final double timetableConflictCourseOpacity;
  final bool courseCardShowName;
  final bool courseCardShowTeacher;
  final bool courseCardShowLocation;
  final bool courseCardShowTime;
  final bool courseCardShowTimeLabels;
  final bool courseCardShowWeeks;
  final bool courseCardShowDescription;
  final CourseCardVerticalAlign courseCardVerticalAlign;
  final CourseCardHorizontalAlign courseCardHorizontalAlign;
  final double courseCardFontSize;
  final TimetableTimeColumnWidthMode timetableTimeColumnWidthMode;
  final double timetableCourseCardGap;
  final TimetableCourseSpacingMode timetableCourseSpacingMode;
  final WidgetBackgroundStyle widgetBackgroundStyle;
  final bool widgetShowLocation;
  final bool widgetShowCountdown;
  final bool widgetHideCompletedCourses;
  final bool widgetShowTomorrowCourses;
  final double widgetHeightAdjustment;
  final double widgetCornerRadius;
  final int widgetCountdownLeadMinutes;
  final LiveCountdownTextStyle widgetCountdownTextStyle;
  final AppThemeMode appThemeMode;
  final AppFontMode appFontMode;
  final String appLocaleTag;
  final HomeTitleStyle homeTitleStyle;
  final TimetableHomeViewMode timetableHomeViewMode;
  final HomeNavigationForm homeNavigationForm;

  /// 玻璃坞底栏按钮排列（'day'/'week' 为视图动作，其余为目录 id）。
  final List<String> glassDockActions;

  /// 玻璃坞入口开关：日课表 Tab 是否显示。
  /// 至少保留一个模块 Tab 由 UI 层约束（设置页在关闭最后一个时锁定）。
  final bool glassDockShowDayTab;

  /// 玻璃坞入口开关：设置 Tab 是否显示。
  final bool glassDockShowSettingsTab;

  /// 玻璃坞入口开关：周课表 Tab 是否显示。与日/设置同规则，
  /// 三者至少保留一个；隐藏周课表 Tab 不影响周视图本身继续作为底图。
  final bool glassDockShowWeekTab;

  /// 玻璃坞独立圆形按钮（extraButton）打开的入口 id。
  /// 默认 'addCourse' 走首页添加课程弹层；其余 id 由首页菜单目录分发，
  /// 未知/不可见 id 运行时回退添加课程弹层。结构 Tab（day/week/settings）
  /// 不允许作为按钮目标，由 UI 层过滤。圆钮可另选自定义图标：
  /// [glassDockButtonIconName] 存 Miuix 扩展图标名（小驼峰），null =
  /// 按功能自动（addCourse 显示加号，其余显示目录图标）。
  final String glassDockButtonEntryId;
  final String? glassDockButtonIconName;

  /// 玻璃坞入口开关：是否显示独立的圆形「添加」按钮（extraButton），
  /// 点击执行 [glassDockButtonEntryId] 对应功能。
  final bool glassDockShowAddButton;
  final BackToCurrentWeekButtonStyle timetableBackToCurrentWeekButtonStyle;
  final double timetableFloatingBackToCurrentWeekButtonOpacity;
  final int timetableLastViewedDayOfWeek;

  /// Whether couple-timetable overlay (header heart) was last left on.
  final bool coupleTimetableOverlayEnabled;

  /// Whether tapping a course on the desktop couple card opens the timetable
  /// with that course's detail sheet expanded.
  final bool coupleTimetableDetailCardEnabled;
  final SectionTimeDisplayMode timetableSectionTimeDisplayMode;
  final bool timetableHideWeekends;
  final bool timetableVerticalScrollEffectEnabled;
  final bool enableHaptics;
  final double pageTransitionSpeed;

  /// When true, home-page pull-down runs warehouse quick import in the background.
  final bool homePullQuickImportEnabled;
  final bool liveShowCourseName;
  final bool liveShowLocation;
  final bool liveShowCountdown;
  final LiveCountdownTextStyle liveCountdownTextStyle;
  final bool liveShowStageText;
  final bool liveEnableBeforeClass;
  final bool liveEnableDuringClass;
  final bool livePromoteDuringClass;
  final bool liveShowDuringClassNotification;
  final bool liveUseShortName;

  /// 灵动岛/提醒/桌面小组件是否跟随当前课表。
  ///
  /// 默认 false：这些界面始终按「我的课表」计算。桌面情侣卡片右半会把当前
  /// 课表切到 TA，若跟随当前课表，点一下对方的卡片就会把自己的上课提醒与岛
  /// 换成对方的。确需长期用另一份课表（含 TA）驱动提醒时，用户显式开启。
  /// 属全局偏好：[TimetableProvider.updateGlobalTimetableSettings] 写入，
  /// 故意不列入 profile 专属字段，避免各课表各自持有一份而开关失效。
  final bool liveFollowActiveTimetable;
  final bool liveHidePrefixText;
  final LiveDuringClassTimeDisplayMode liveDuringClassTimeDisplayMode;
  final bool liveEnableMiuiIslandLabelImage;
  final bool liveHideFromRecents;
  final bool liveEnableLocalDiagnostics;
  final MiuiIslandLabelStyle liveMiuiIslandLabelStyle;
  final MiuiIslandLabelContent liveMiuiIslandLabelContent;
  final String liveMiuiIslandLabelFontColor;
  final MiuiIslandLabelFontWeight liveMiuiIslandLabelFontWeight;
  final MiuiIslandLabelRenderQuality liveMiuiIslandLabelRenderQuality;
  final double liveMiuiIslandLabelFontSize;
  final double liveMiuiIslandLabelOffsetX;
  final double liveMiuiIslandLabelOffsetY;
  final String? liveMiuiIslandLabelLogoPath;
  final double liveMiuiIslandLabelLogoCornerRadius;
  final MiuiIslandExpandedIconMode liveMiuiIslandExpandedIconMode;
  final String? liveMiuiIslandExpandedIconPath;
  final int liveShowBeforeClassMinutes;
  final int liveClassReminderStartMinutes;
  final int liveTimeCorrectionSeconds;
  final LiveBeforeClassQuickAction liveBeforeClassQuickAction;

  /// 上课前自动执行快捷操作的提前分钟数；0 表示不自动执行（仅保留通知按钮）。
  final int liveBeforeClassQuickActionAutoMinutes;

  /// 常驻通知：没有课程会话时也让通知留在状态栏，内容显示情侣卡片（我这一列）。
  ///
  /// 关闭时回到「随课程起停」的旧行为 —— 无课、课上完、假期都不显示通知。
  final bool livePermanentNotificationEnabled;
  final String timetablePageBackgroundColor;
  final HomePageBackgroundFill homePageBackgroundFill;
  final String? homePageBackgroundImagePath;
  final String? homePageWallpaperPath;

  /// 壁纸在页面内的水平对齐（-1 靠左 … 0 居中 … 1 靠右），用于横向壁纸
  /// 拖动选择显示区域；竖屏壁纸下 cover 不会水平溢出，该值不产生位移。
  final double homePageWallpaperAlignX;

  /// 壁纸在页面内的垂直对齐（-1 靠上 … 0 居中 … 1 靠下），用于长图壁纸
  /// 拖动选择显示区域；cover 下高度未溢出时该值不产生位移。
  final double homePageWallpaperAlignY;

  /// 底层壁纸的高斯模糊强度；0 表示保持原图。
  final double homePageBackdropBlurSigma;

  /// 底层壁纸的白色磨砂层透明度；0 表示不提亮。
  final double homePageBackdropFrostAlpha;
  final int homePageBackgroundScope;
  final bool timetableUseUnifiedCardColor;
  final String timetableUnifiedCardColor;
  final String appUpdateDownloadSource;
  final bool appUpdateUseSystemDownloader;
  final String appUpdateMirrorPreset;
  final String appUpdateMirrorUrlPrefix;

  /// 检测到新版本时是否在首页自动弹出更新提醒；关闭后仅显示红点角标。
  final bool appUpdatePromptEnabled;
  final bool holidayOverrideEnabled;

  /// 上课闹钟：提前量与是否跳过系统时钟确认页。
  final int classAlarmLeadMinutes;
  final bool classAlarmSkipUi;

  /// 单节课提醒：按「课程 + 真实日期」一次性生效的本地通知提醒（保留兼容）。
  /// 新的「这节课闹钟」改为写入系统时钟，不再新增此类条目。
  final List<ClassReminderEntry> classReminders;
  final String courseCardTitleColorLight;
  final String courseCardTitleColorDark;
  final String courseCardDetailColorLight;
  final String courseCardDetailColorDark;
  final String weekdayBarFontColorLight;
  final String weekdayBarFontColorDark;
  final String weekdayBarAccentColorLight;
  final String weekdayBarAccentColorDark;
  final String timeAxisFontColorLight;
  final String timeAxisFontColorDark;

  /// Convenience getter that maps frosted-glass fields to a [FrostedAppearance].
  FrostedAppearance get frostedAppearance => FrostedAppearance(
    sheetBlurSigma: frostedSheetBlurSigma,
    sheetTintAlpha: frostedSheetTintAlpha,
    sheetBarrierAlpha: frostedSheetBarrierAlpha,
    blurEnabled: frostedBlurEnabled,
  );

  final bool linkCourseCardColors; // 标题和详情颜色是否关联
  final double frostedSheetBlurSigma;
  final double frostedSheetTintAlpha;
  final double frostedSheetBarrierAlpha;
  final bool frostedBlurEnabled;

  final bool homePageHeaderBlurEnabled;
  final bool homePageWeekdayBarBlurEnabled;
  final bool homePageTimeColumnBlurEnabled;
  final bool homePageBackdropFollowsWeekPager;

  const TimetableSettings({
    required this.sections,
    this.activeTimeSchemeId,
    this.sectionHeight = 68,
    this.compactFontSize = 9.5,
    this.timetableAutoFitSectionHeight = true,
    this.semesterWeekCount = 20,
    this.semesterStartDate,
    this.weeklyReportEnabled = false,
    this.enableHolidayMarking = true,
    this.timetableShowCurrentWeekCourses = true,
    this.timetableShowNonCurrentWeekCourses = false,
    this.showConflictBadgeOnTimetable = true,
    this.timetableConflictCourseOpacity = 0.70,
    this.courseCardShowName = true,
    this.courseCardShowTeacher = true,
    this.courseCardShowLocation = true,
    this.courseCardShowTime = false,
    this.courseCardShowTimeLabels = true,
    this.courseCardShowWeeks = true,
    this.courseCardShowDescription = false,
    this.courseCardVerticalAlign = CourseCardVerticalAlign.center,
    this.courseCardHorizontalAlign = CourseCardHorizontalAlign.center,
    this.courseCardFontSize = 11.5,
    this.timetableTimeColumnWidthMode = TimetableTimeColumnWidthMode.narrow,
    this.timetableCourseCardGap = 1.25,
    this.timetableCourseSpacingMode = TimetableCourseSpacingMode.narrow,
    this.widgetBackgroundStyle = WidgetBackgroundStyle.solid,
    this.widgetShowLocation = true,
    this.widgetShowCountdown = true,
    this.widgetHideCompletedCourses = false,
    this.widgetShowTomorrowCourses = true,
    this.widgetHeightAdjustment = -11,
    this.widgetCornerRadius = 22,
    this.widgetCountdownLeadMinutes = 20,
    this.widgetCountdownTextStyle = LiveCountdownTextStyle.smart,
    this.appThemeMode = AppThemeMode.system,
    this.appFontMode = AppFontMode.system,
    this.appLocaleTag = '',
    this.homeTitleStyle = HomeTitleStyle.classic,
    this.timetableHomeViewMode = TimetableHomeViewMode.week,
    this.homeNavigationForm = HomeNavigationForm.classic,
    this.glassDockActions = HomeDockMenu.defaultActions,
    this.glassDockShowDayTab = true,
    this.glassDockShowSettingsTab = true,
    this.glassDockShowWeekTab = true,
    this.glassDockButtonEntryId = 'addCourse',
    this.glassDockButtonIconName,
    this.glassDockShowAddButton = false,
    this.timetableBackToCurrentWeekButtonStyle =
        BackToCurrentWeekButtonStyle.floating,
    this.timetableFloatingBackToCurrentWeekButtonOpacity = 0.96,
    this.timetableLastViewedDayOfWeek = 1,
    this.coupleTimetableOverlayEnabled = true,
    this.coupleTimetableDetailCardEnabled = true,
    this.timetableSectionTimeDisplayMode = SectionTimeDisplayMode.startAndEnd,
    this.timetableHideWeekends = false,
    this.timetableVerticalScrollEffectEnabled = false,
    this.enableHaptics = false,
    this.pageTransitionSpeed = defaultPageTransitionSpeed,
    this.homePullQuickImportEnabled = false,
    this.liveShowCourseName = true,
    this.liveShowLocation = true,
    this.liveShowCountdown = true,
    this.liveCountdownTextStyle = LiveCountdownTextStyle.smart,
    this.liveShowStageText = true,
    this.liveEnableBeforeClass = true,
    this.liveEnableDuringClass = true,
    this.livePromoteDuringClass = true,
    this.liveShowDuringClassNotification = true,
    this.liveUseShortName = true,
    this.liveFollowActiveTimetable = false,
    this.liveHidePrefixText = true,
    this.liveDuringClassTimeDisplayMode =
        LiveDuringClassTimeDisplayMode.nearest,
    this.liveEnableMiuiIslandLabelImage = false,
    this.liveHideFromRecents = false,
    this.liveEnableLocalDiagnostics = false,
    this.liveMiuiIslandLabelStyle = MiuiIslandLabelStyle.textOnly,
    this.liveMiuiIslandLabelContent = MiuiIslandLabelContent.courseName,
    this.liveMiuiIslandLabelFontColor = '#FFFFFF',
    this.liveMiuiIslandLabelFontWeight = MiuiIslandLabelFontWeight.bold,
    this.liveMiuiIslandLabelRenderQuality =
        MiuiIslandLabelRenderQuality.standard,
    this.liveMiuiIslandLabelFontSize = 14,
    this.liveMiuiIslandLabelOffsetX = 0,
    this.liveMiuiIslandLabelOffsetY = 0,
    this.liveMiuiIslandLabelLogoPath,
    this.liveMiuiIslandLabelLogoCornerRadius = 8,
    this.liveMiuiIslandExpandedIconMode = MiuiIslandExpandedIconMode.appIcon,
    this.liveMiuiIslandExpandedIconPath,
    this.liveShowBeforeClassMinutes = 20,
    this.liveClassReminderStartMinutes = 0,
    this.liveTimeCorrectionSeconds = 0,
    this.liveBeforeClassQuickAction = LiveBeforeClassQuickAction.none,
    this.liveBeforeClassQuickActionAutoMinutes = 0,
    this.livePermanentNotificationEnabled = true,
    this.timetablePageBackgroundColor = '#F8FAFC',
    this.homePageBackgroundFill = HomePageBackgroundFill.color,
    this.homePageBackgroundImagePath,
    this.homePageWallpaperPath = defaultHomePageWallpaperPath,
    this.homePageWallpaperAlignX = 0,
    this.homePageWallpaperAlignY = 0,
    this.homePageBackdropBlurSigma = 0,
    this.homePageBackdropFrostAlpha = 0,
    this.homePageBackgroundScope = HomePageBackgroundScope.defaultValue,
    this.timetableUseUnifiedCardColor = false,
    this.timetableUnifiedCardColor = '#2563EB',
    this.appUpdateDownloadSource = 'mirror',
    this.appUpdateUseSystemDownloader = false,
    this.appUpdateMirrorPreset = 'ghfast',
    this.appUpdateMirrorUrlPrefix = defaultAppUpdateMirrorUrlPrefix,
    this.appUpdatePromptEnabled = true,
    this.holidayOverrideEnabled = false,
    this.classAlarmLeadMinutes = 30,
    this.classAlarmSkipUi = false,
    this.classReminders = const [],
    this.courseCardTitleColorLight = defaultCourseCardTitleColor,
    this.courseCardTitleColorDark = defaultCourseCardTitleColor,
    this.courseCardDetailColorLight = defaultCourseCardDetailColor,
    this.courseCardDetailColorDark = defaultCourseCardDetailColor,
    this.weekdayBarFontColorLight = defaultWeekdayBarFontColorLight,
    this.weekdayBarFontColorDark = defaultWeekdayBarFontColorDark,
    this.weekdayBarAccentColorLight = defaultWeekdayBarAccentColorLight,
    this.weekdayBarAccentColorDark = defaultWeekdayBarAccentColorDark,
    this.timeAxisFontColorLight = defaultTimeAxisFontColorLight,
    this.timeAxisFontColorDark = defaultTimeAxisFontColorDark,
    this.linkCourseCardColors = true,
    this.frostedSheetBlurSigma = defaultFrostedSheetBlurSigma,
    this.frostedSheetTintAlpha = defaultFrostedSheetTintAlpha,
    this.frostedSheetBarrierAlpha = defaultFrostedSheetBarrierAlpha,
    this.frostedBlurEnabled = defaultFrostedBlurEnabled,
    this.homePageHeaderBlurEnabled = false,
    this.homePageWeekdayBarBlurEnabled = false,
    this.homePageTimeColumnBlurEnabled = false,
    this.homePageBackdropFollowsWeekPager = false,
  });

  factory TimetableSettings.defaults() {
    return const TimetableSettings(
      sections: [
        SectionTime(startTime: '08:00', endTime: '08:45'),
        SectionTime(startTime: '08:55', endTime: '09:40'),
        SectionTime(startTime: '10:00', endTime: '10:45'),
        SectionTime(startTime: '10:55', endTime: '11:40'),
        SectionTime(startTime: '14:00', endTime: '14:45'),
        SectionTime(startTime: '14:55', endTime: '15:40'),
        SectionTime(startTime: '16:00', endTime: '16:45'),
        SectionTime(startTime: '16:55', endTime: '17:40'),
        SectionTime(startTime: '19:00', endTime: '19:45'),
        SectionTime(startTime: '19:55', endTime: '20:40'),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sections': sections.map((section) => section.toJson()).toList(),
      'activeTimeSchemeId': activeTimeSchemeId,
      'sectionHeight': sectionHeight,
      'compactFontSize': compactFontSize,
      'timetableAutoFitSectionHeight': timetableAutoFitSectionHeight,
      'semesterWeekCount': semesterWeekCount,
      'semesterStartDate': semesterStartDate?.millisecondsSinceEpoch,
      'weeklyReportEnabled': weeklyReportEnabled,
      'enableHolidayMarking': enableHolidayMarking,
      'timetableShowCurrentWeekCourses': timetableShowCurrentWeekCourses,
      'timetableShowNonCurrentWeekCourses': timetableShowNonCurrentWeekCourses,
      'showConflictBadgeOnTimetable': showConflictBadgeOnTimetable,
      'timetableConflictCourseOpacity': timetableConflictCourseOpacity,
      'courseCardShowName': courseCardShowName,
      'courseCardShowTeacher': courseCardShowTeacher,
      'courseCardShowLocation': courseCardShowLocation,
      'courseCardShowTime': courseCardShowTime,
      'courseCardShowTimeLabels': courseCardShowTimeLabels,
      'courseCardShowWeeks': courseCardShowWeeks,
      'courseCardShowDescription': courseCardShowDescription,
      'courseCardVerticalAlign': courseCardVerticalAlign.value,
      'courseCardHorizontalAlign': courseCardHorizontalAlign.value,
      'courseCardFontSize': courseCardFontSize,
      'timetableTimeColumnWidthMode': timetableTimeColumnWidthMode.value,
      'timetableCourseCardGap': timetableCourseCardGap,
      'timetableCourseSpacingMode': timetableCourseSpacingMode.value,
      'widgetBackgroundStyle': widgetBackgroundStyle.value,
      'widgetShowLocation': widgetShowLocation,
      'widgetShowCountdown': widgetShowCountdown,
      'widgetHideCompletedCourses': widgetHideCompletedCourses,
      'widgetShowTomorrowCourses': widgetShowTomorrowCourses,
      'widgetHeightAdjustment': widgetHeightAdjustment,
      'widgetCornerRadius': widgetCornerRadius,
      'widgetCountdownLeadMinutes': widgetCountdownLeadMinutes,
      'widgetCountdownTextStyle': widgetCountdownTextStyle.value,
      'appThemeMode': appThemeMode.value,
      'appFontMode': appFontMode.value,
      'appLocaleTag': appLocaleTag,
      'homeTitleStyle': homeTitleStyle.value,
      'timetableHomeViewMode': timetableHomeViewMode.value,
      'homeNavigationForm': homeNavigationForm.value,
      'glassDockActions': glassDockActions,
      'glassDockShowDayTab': glassDockShowDayTab,
      'glassDockShowSettingsTab': glassDockShowSettingsTab,
      'glassDockShowWeekTab': glassDockShowWeekTab,
      'glassDockButtonEntryId': glassDockButtonEntryId,
      'glassDockButtonIconName': glassDockButtonIconName,
      'glassDockShowAddButton': glassDockShowAddButton,
      'timetableBackToCurrentWeekButtonStyle':
          timetableBackToCurrentWeekButtonStyle.value,
      'timetableFloatingBackToCurrentWeekButtonOpacity':
          timetableFloatingBackToCurrentWeekButtonOpacity,
      'timetableLastViewedDayOfWeek': timetableLastViewedDayOfWeek,
      'coupleTimetableOverlayEnabled': coupleTimetableOverlayEnabled,
      'coupleTimetableDetailCardEnabled': coupleTimetableDetailCardEnabled,
      'timetableSectionTimeDisplayMode': timetableSectionTimeDisplayMode.value,
      'timetableHideWeekends': timetableHideWeekends,
      'timetableVerticalScrollEffectEnabled':
          timetableVerticalScrollEffectEnabled,
      'enableHaptics': enableHaptics,
      'pageTransitionSpeed': pageTransitionSpeed,
      'homePullQuickImportEnabled': homePullQuickImportEnabled,
      'liveShowCourseName': liveShowCourseName,
      'liveShowLocation': liveShowLocation,
      'liveShowCountdown': liveShowCountdown,
      'liveCountdownTextStyle': liveCountdownTextStyle.value,
      'liveShowStageText': liveShowStageText,
      'liveEnableBeforeClass': liveEnableBeforeClass,
      'liveEnableDuringClass': liveEnableDuringClass,
      'livePromoteDuringClass': livePromoteDuringClass,
      'liveShowDuringClassNotification': liveShowDuringClassNotification,
      'liveUseShortName': liveUseShortName,
      'liveFollowActiveTimetable': liveFollowActiveTimetable,
      'liveHidePrefixText': liveHidePrefixText,
      'liveDuringClassTimeDisplayMode': liveDuringClassTimeDisplayMode.value,
      'liveEnableMiuiIslandLabelImage': liveEnableMiuiIslandLabelImage,
      'liveHideFromRecents': liveHideFromRecents,
      'liveEnableLocalDiagnostics': liveEnableLocalDiagnostics,
      'liveMiuiIslandLabelStyle': liveMiuiIslandLabelStyle.value,
      'liveMiuiIslandLabelContent': liveMiuiIslandLabelContent.value,
      'liveMiuiIslandLabelFontColor': liveMiuiIslandLabelFontColor,
      'liveMiuiIslandLabelFontWeight': liveMiuiIslandLabelFontWeight.value,
      'liveMiuiIslandLabelRenderQuality':
          liveMiuiIslandLabelRenderQuality.value,
      'liveMiuiIslandLabelFontSize': liveMiuiIslandLabelFontSize,
      'liveMiuiIslandLabelOffsetX': liveMiuiIslandLabelOffsetX,
      'liveMiuiIslandLabelOffsetY': liveMiuiIslandLabelOffsetY,
      'liveMiuiIslandLabelLogoPath': liveMiuiIslandLabelLogoPath,
      'liveMiuiIslandLabelLogoCornerRadius':
          liveMiuiIslandLabelLogoCornerRadius,
      'liveMiuiIslandExpandedIconMode': liveMiuiIslandExpandedIconMode.value,
      'liveMiuiIslandExpandedIconPath': liveMiuiIslandExpandedIconPath,
      'liveShowBeforeClassMinutes': liveShowBeforeClassMinutes,
      'liveClassReminderStartMinutes': liveClassReminderStartMinutes,
      'liveTimeCorrectionSeconds': liveTimeCorrectionSeconds,
      'liveBeforeClassQuickAction': liveBeforeClassQuickAction.value,
      'liveBeforeClassQuickActionAutoMinutes':
          liveBeforeClassQuickActionAutoMinutes,
      'livePermanentNotificationEnabled': livePermanentNotificationEnabled,
      'timetablePageBackgroundColor': timetablePageBackgroundColor,
      'homePageBackgroundFill': homePageBackgroundFill.value,
      if (homePageBackgroundImagePath != null)
        'homePageBackgroundImagePath': homePageBackgroundImagePath,
      'homePageWallpaperPath': homePageWallpaperPath,
      'homePageWallpaperAlignX': homePageWallpaperAlignX,
      'homePageWallpaperAlignY': homePageWallpaperAlignY,
      'homePageBackdropBlurSigma': homePageBackdropBlurSigma,
      'homePageBackdropFrostAlpha': homePageBackdropFrostAlpha,
      'homePageBackgroundScope': homePageBackgroundScope,
      'timetableUseUnifiedCardColor': timetableUseUnifiedCardColor,
      'timetableUnifiedCardColor': timetableUnifiedCardColor,
      'appUpdateDownloadSource': appUpdateDownloadSource,
      'appUpdateUseSystemDownloader': appUpdateUseSystemDownloader,
      'appUpdateMirrorPreset': appUpdateMirrorPreset,
      'appUpdateMirrorUrlPrefix': appUpdateMirrorUrlPrefix,
      'appUpdatePromptEnabled': appUpdatePromptEnabled,
      'holidayOverrideEnabled': holidayOverrideEnabled,
      'classAlarmLeadMinutes': classAlarmLeadMinutes,
      'classAlarmSkipUi': classAlarmSkipUi,
      'classReminders': [for (final entry in classReminders) entry.toJson()],
      'courseCardTitleColorLight': courseCardTitleColorLight,
      'courseCardTitleColorDark': courseCardTitleColorDark,
      'courseCardDetailColorLight': courseCardDetailColorLight,
      'courseCardDetailColorDark': courseCardDetailColorDark,
      'weekdayBarFontColorLight': weekdayBarFontColorLight,
      'weekdayBarFontColorDark': weekdayBarFontColorDark,
      'weekdayBarAccentColorLight': weekdayBarAccentColorLight,
      'weekdayBarAccentColorDark': weekdayBarAccentColorDark,
      'timeAxisFontColorLight': timeAxisFontColorLight,
      'timeAxisFontColorDark': timeAxisFontColorDark,
      'linkCourseCardColors': linkCourseCardColors,
      'frostedSheetBlurSigma': frostedSheetBlurSigma,
      'frostedSheetTintAlpha': frostedSheetTintAlpha,
      'frostedSheetBarrierAlpha': frostedSheetBarrierAlpha,
      'frostedBlurEnabled': frostedBlurEnabled,
      'homePageHeaderBlurEnabled': homePageHeaderBlurEnabled,
      'homePageWeekdayBarBlurEnabled': homePageWeekdayBarBlurEnabled,
      'homePageTimeColumnBlurEnabled': homePageTimeColumnBlurEnabled,
      'homePageBackdropFollowsWeekPager': homePageBackdropFollowsWeekPager,
    };
  }

  factory TimetableSettings.fromJson(Map<String, dynamic> json) {
    // 联动开时详情字色回填为标题字色，规则与 copyWith 的联动回填一致：
    // 旧版本数据 / 主题备份可能残留「联动开、详情色不同」的脏状态（白标题
    // +黑简介混色卡的根源）；独立模式（联动关）保留用户显式选择。
    final linkedCardTextColors = json['linkCourseCardColors'] as bool? ?? true;
    final parsedTitleColorLight =
        json['courseCardTitleColorLight'] as String? ??
        defaultCourseCardTitleColor;
    final parsedTitleColorDark =
        json['courseCardTitleColorDark'] as String? ??
        defaultCourseCardTitleColor;
    final parsedDetailColorLight = linkedCardTextColors
        ? parsedTitleColorLight
        : json['courseCardDetailColorLight'] as String? ??
              defaultCourseCardDetailColor;
    final parsedDetailColorDark = linkedCardTextColors
        ? parsedTitleColorDark
        : json['courseCardDetailColorDark'] as String? ??
              defaultCourseCardDetailColor;
    final rawSections = json['sections'] is List
        ? json['sections'] as List<dynamic>
        : const <dynamic>[];
    // Empty sections fall back to defaults only for the section list; other
    // fields must still parse so a corrupt sections array does not wipe theme /
    // semester / live settings. Malformed SectionTime entries are skipped.
    List<SectionTime> resolvedSections;
    if (rawSections.isEmpty) {
      resolvedSections = TimetableSettings.defaults().sections;
    } else {
      final parsed = <SectionTime>[];
      for (final item in rawSections) {
        try {
          if (item is! Map) continue;
          parsed.add(SectionTime.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          continue;
        }
      }
      resolvedSections = parsed.isEmpty
          ? TimetableSettings.defaults().sections
          : parsed;
    }
    final rawAppUpdateMirrorUrlPrefix =
        json['appUpdateMirrorUrlPrefix'] as String? ??
        defaultAppUpdateMirrorUrlPrefix;
    final rawAppUpdateMirrorPreset = json['appUpdateMirrorPreset'] as String?;

    return TimetableSettings(
      sections: resolvedSections,
      activeTimeSchemeId: json['activeTimeSchemeId'] as String?,
      sectionHeight: (json['sectionHeight'] as num?)?.toDouble() ?? 68,
      compactFontSize: (json['compactFontSize'] as num?)?.toDouble() ?? 9.5,
      timetableAutoFitSectionHeight:
          json['timetableAutoFitSectionHeight'] as bool? ?? true,
      semesterWeekCount: (json['semesterWeekCount'] as num?)?.toInt() ?? 20,
      semesterStartDate: (json['semesterStartDate'] as num?) != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['semesterStartDate'] as num).toInt(),
            )
          : null,
      weeklyReportEnabled: json['weeklyReportEnabled'] as bool? ?? false,
      enableHolidayMarking: json['enableHolidayMarking'] as bool? ?? true,
      timetableShowNonCurrentWeekCourses:
          json['timetableShowNonCurrentWeekCourses'] as bool? ?? false,
      showConflictBadgeOnTimetable:
          json['showConflictBadgeOnTimetable'] as bool? ?? true,
      timetableConflictCourseOpacity:
          ((json['timetableConflictCourseOpacity'] as num?)?.toDouble() ?? 0.70)
              .clamp(0.2, 1.0),
      courseCardShowName: json['courseCardShowName'] as bool? ?? true,
      courseCardShowTeacher: json['courseCardShowTeacher'] as bool? ?? true,
      courseCardShowLocation: json['courseCardShowLocation'] as bool? ?? true,
      courseCardShowTime: json['courseCardShowTime'] as bool? ?? false,
      courseCardShowTimeLabels:
          json['courseCardShowTimeLabels'] as bool? ?? true,
      courseCardShowWeeks: json['courseCardShowWeeks'] as bool? ?? true,
      courseCardShowDescription:
          json['courseCardShowDescription'] as bool? ?? false,
      courseCardVerticalAlign: CourseCardVerticalAlignX.fromValue(
        json['courseCardVerticalAlign'] as String?,
      ),
      courseCardHorizontalAlign: CourseCardHorizontalAlignX.fromValue(
        json['courseCardHorizontalAlign'] as String?,
      ),
      courseCardFontSize: (json['courseCardFontSize'] as num?)?.toDouble() ?? 11.5,
      timetableTimeColumnWidthMode: TimetableTimeColumnWidthModeX.fromValue(
        json['timetableTimeColumnWidthMode'] as String?,
      ),
      timetableCourseCardGap:
          (json['timetableCourseCardGap'] as num?)?.toDouble() ??
          ((json['timetableCourseSpacingMode'] as String?) == 'wide'
              ? 2.0
              : 1.25),
      timetableCourseSpacingMode: TimetableCourseSpacingModeX.fromValue(
        json['timetableCourseSpacingMode'] as String?,
      ),
      widgetBackgroundStyle: WidgetBackgroundStyleX.fromValue(
        json['widgetBackgroundStyle'] as String?,
      ),
      widgetShowLocation: json['widgetShowLocation'] as bool? ?? true,
      widgetShowCountdown: json['widgetShowCountdown'] as bool? ?? true,
      widgetHideCompletedCourses:
          json['widgetHideCompletedCourses'] as bool? ?? false,
      widgetShowTomorrowCourses:
          json['widgetShowTomorrowCourses'] as bool? ?? true,
      widgetHeightAdjustment:
          (json['widgetHeightAdjustment'] as num?)?.toDouble() ?? -11,
      widgetCornerRadius:
          (json['widgetCornerRadius'] as num?)?.toDouble() ?? 22,
      widgetCountdownLeadMinutes:
          (json['widgetCountdownLeadMinutes'] as num?)?.toInt() ?? 20,
      widgetCountdownTextStyle: LiveCountdownTextStyleX.fromValue(
        json['widgetCountdownTextStyle'] as String?,
      ),
      appThemeMode: AppThemeModeX.fromValue(json['appThemeMode'] as String?),
      appFontMode: AppFontModeX.fromValue(json['appFontMode'] as String?),
      appLocaleTag: _normalizeAppLocaleTag(
        json['appLocaleTag'] as String? ?? json['appLocaleMode'] as String?,
      ),
      homeTitleStyle: HomeTitleStyleX.fromValue(
        json['homeTitleStyle'] as String?,
      ),
      timetableHomeViewMode: TimetableHomeViewModeX.fromValue(
        json['timetableHomeViewMode'] as String?,
      ),
      homeNavigationForm: HomeNavigationFormX.fromValue(
        json['homeNavigationForm'] as String?,
      ),
      glassDockActions: HomeDockMenu.normalize(
        (json['glassDockActions'] as List<Object?>?) ??
            [
              // 迁移：旧档无此键时由日/周 Tab 开关推导（旧默认均 true）。
              if (json['glassDockShowDayTab'] as bool? ?? true) 'day',
              if (json['glassDockShowWeekTab'] as bool? ?? true) 'week',
            ],
      ),
      glassDockShowDayTab: json['glassDockShowDayTab'] as bool? ?? true,
      glassDockShowSettingsTab:
          json['glassDockShowSettingsTab'] as bool? ?? true,
      glassDockShowWeekTab: json['glassDockShowWeekTab'] as bool? ?? true,
      glassDockButtonEntryId:
          json['glassDockButtonEntryId'] as String? ?? 'addCourse',
      glassDockButtonIconName: json['glassDockButtonIconName'] as String?,
      glassDockShowAddButton: json['glassDockShowAddButton'] as bool? ?? false,
      timetableBackToCurrentWeekButtonStyle:
          BackToCurrentWeekButtonStyleX.fromValue(
            json['timetableBackToCurrentWeekButtonStyle'] as String?,
          ),
      timetableFloatingBackToCurrentWeekButtonOpacity:
          ((json['timetableFloatingBackToCurrentWeekButtonOpacity'] as num?)
                      ?.toDouble() ??
                  0.96)
              .clamp(0.55, 1.0),
      timetableLastViewedDayOfWeek:
          ((json['timetableLastViewedDayOfWeek'] as num?)?.toInt() ?? 1).clamp(
            1,
            7,
          ),
      coupleTimetableOverlayEnabled:
          json['coupleTimetableOverlayEnabled'] as bool? ?? true,
      coupleTimetableDetailCardEnabled:
          json['coupleTimetableDetailCardEnabled'] as bool? ?? true,
      timetableSectionTimeDisplayMode: SectionTimeDisplayModeX.fromValue(
        json['timetableSectionTimeDisplayMode'] as String?,
      ),
      timetableHideWeekends: json['timetableHideWeekends'] as bool? ?? false,
      timetableVerticalScrollEffectEnabled:
          json['timetableVerticalScrollEffectEnabled'] as bool? ?? false,
      enableHaptics: json['enableHaptics'] as bool? ?? false,
      pageTransitionSpeed:
          ((json['pageTransitionSpeed'] as num?)?.toDouble() ??
                  defaultPageTransitionSpeed)
              .clamp(minPageTransitionSpeed, maxPageTransitionSpeed),
      homePullQuickImportEnabled:
          json['homePullQuickImportEnabled'] as bool? ?? false,
      liveShowCourseName: json['liveShowCourseName'] as bool? ?? true,
      liveShowLocation: json['liveShowLocation'] as bool? ?? true,
      liveShowCountdown: json['liveShowCountdown'] as bool? ?? true,
      liveCountdownTextStyle: LiveCountdownTextStyleX.fromValue(
        json['liveCountdownTextStyle'] as String?,
      ),
      liveShowStageText: json['liveShowStageText'] as bool? ?? true,
      liveEnableBeforeClass: json['liveEnableBeforeClass'] as bool? ?? true,
      // liveEnableBeforeEnd 已随「下课提醒」阶段移除。旧版这两个开关由同一个 UI
      // 开关联动，存盘时可能出现一个真一个假；沿用 OR 读回，避免当初实际开着
      // 课中提醒的用户升级后被静默关掉。
      liveEnableDuringClass:
          (json['liveEnableDuringClass'] as bool? ?? true) ||
          (json['liveEnableBeforeEnd'] as bool? ?? true),
      livePromoteDuringClass: json['livePromoteDuringClass'] as bool? ?? true,
      liveShowDuringClassNotification:
          json['liveShowDuringClassNotification'] as bool? ?? true,
      liveUseShortName: json['liveUseShortName'] as bool? ?? true,
      liveFollowActiveTimetable:
          json['liveFollowActiveTimetable'] as bool? ?? false,
      liveHidePrefixText: json['liveHidePrefixText'] as bool? ?? true,
      liveDuringClassTimeDisplayMode: LiveDuringClassTimeDisplayModeX.fromValue(
        // 「课中时间样式」的选项此前只挂在「课中/下课」那份配置上（现已并入
        // 课前），所以旧存档里的 liveDuringEndTimeDisplayMode 才是用户真正选过的
        // 值；优先读它，避免升级后静默回到默认的「最近节点」。
        json['liveDuringEndTimeDisplayMode'] as String? ??
            json['liveDuringClassTimeDisplayMode'] as String?,
      ),
      liveEnableMiuiIslandLabelImage:
          json['liveEnableMiuiIslandLabelImage'] as bool? ?? false,
      liveHideFromRecents: json['liveHideFromRecents'] as bool? ?? false,
      liveEnableLocalDiagnostics:
          json['liveEnableLocalDiagnostics'] as bool? ?? false,
      liveMiuiIslandLabelStyle: MiuiIslandLabelStyleX.fromValue(
        json['liveMiuiIslandLabelStyle'] as String?,
      ),
      liveMiuiIslandLabelContent: MiuiIslandLabelContentX.fromValue(
        json['liveMiuiIslandLabelContent'] as String?,
      ),
      liveMiuiIslandLabelFontColor:
          json['liveMiuiIslandLabelFontColor'] as String? ?? '#FFFFFF',
      liveMiuiIslandLabelFontWeight: MiuiIslandLabelFontWeightX.fromValue(
        json['liveMiuiIslandLabelFontWeight'] as String?,
      ),
      liveMiuiIslandLabelRenderQuality: MiuiIslandLabelRenderQualityX.fromValue(
        json['liveMiuiIslandLabelRenderQuality'] as String?,
      ),
      liveMiuiIslandLabelFontSize:
          (json['liveMiuiIslandLabelFontSize'] as num?)?.toDouble() ?? 14,
      liveMiuiIslandLabelOffsetX:
          (json['liveMiuiIslandLabelOffsetX'] as num?)?.toDouble() ?? 0,
      liveMiuiIslandLabelOffsetY:
          (json['liveMiuiIslandLabelOffsetY'] as num?)?.toDouble() ?? 0,
      liveMiuiIslandLabelLogoPath:
          json['liveMiuiIslandLabelLogoPath'] as String?,
      liveMiuiIslandLabelLogoCornerRadius:
          (json['liveMiuiIslandLabelLogoCornerRadius'] as num?)?.toDouble() ??
          8,
      liveMiuiIslandExpandedIconMode: MiuiIslandExpandedIconModeX.fromValue(
        json['liveMiuiIslandExpandedIconMode'] as String?,
      ),
      liveMiuiIslandExpandedIconPath:
          json['liveMiuiIslandExpandedIconPath'] as String?,
      liveShowBeforeClassMinutes:
          (json['liveShowBeforeClassMinutes'] as num?)?.toInt() ?? 20,
      liveClassReminderStartMinutes:
          (json['liveClassReminderStartMinutes'] as num?)?.toInt() ?? 0,
      liveTimeCorrectionSeconds:
          (json['liveTimeCorrectionSeconds'] as num?)?.toInt() ?? 0,
      liveBeforeClassQuickAction: LiveBeforeClassQuickActionX.fromValue(
        json['liveBeforeClassQuickAction'] as String?,
      ),
      liveBeforeClassQuickActionAutoMinutes:
          (json['liveBeforeClassQuickActionAutoMinutes'] as num?)?.toInt() ?? 0,
      livePermanentNotificationEnabled:
          json['livePermanentNotificationEnabled'] as bool? ?? true,
      timetablePageBackgroundColor:
          json['timetablePageBackgroundColor'] as String? ?? '#F8FAFC',
      homePageBackgroundFill: HomePageBackgroundFillX.fromValue(
        json['homePageBackgroundFill'] as String?,
      ),
      homePageBackgroundImagePath:
          json['homePageBackgroundImagePath'] as String?,
      homePageWallpaperPath: json.containsKey('homePageWallpaperPath')
          ? json['homePageWallpaperPath'] as String?
          : defaultHomePageWallpaperPath,
      homePageWallpaperAlignX:
          (json['homePageWallpaperAlignX'] as num?)?.toDouble() ?? 0,
      homePageWallpaperAlignY:
          (json['homePageWallpaperAlignY'] as num?)?.toDouble() ?? 0,
      homePageBackdropBlurSigma:
          (json['homePageBackdropBlurSigma'] as num?)?.toDouble() ?? 0,
      homePageBackdropFrostAlpha:
          (json['homePageBackdropFrostAlpha'] as num?)?.toDouble() ?? 0,
      homePageBackgroundScope:
          (json['homePageBackgroundScope'] as num?)?.toInt() ??
          HomePageBackgroundScope.defaultValue,
      timetableUseUnifiedCardColor:
          json['timetableUseUnifiedCardColor'] as bool? ?? false,
      timetableUnifiedCardColor:
          json['timetableUnifiedCardColor'] as String? ?? '#2563EB',
      appUpdateDownloadSource:
          json['appUpdateDownloadSource'] as String? ?? 'mirror',
      appUpdateUseSystemDownloader:
          json['appUpdateUseSystemDownloader'] as bool? ?? false,
      appUpdateMirrorPreset: (rawAppUpdateMirrorPreset == null
          ? AppUpdateMirrorPresetX.fromUrlPrefix(
              rawAppUpdateMirrorUrlPrefix,
            ).value
          : AppUpdateMirrorPresetX.fromValue(rawAppUpdateMirrorPreset).value),
      appUpdateMirrorUrlPrefix: rawAppUpdateMirrorUrlPrefix,
      appUpdatePromptEnabled: json['appUpdatePromptEnabled'] as bool? ?? true,
      holidayOverrideEnabled: json['holidayOverrideEnabled'] as bool? ?? false,
      classAlarmLeadMinutes:
          (json['classAlarmLeadMinutes'] as num?)?.toInt() ?? 30,
      classAlarmSkipUi: json['classAlarmSkipUi'] as bool? ?? false,
      // 脏条目在 listFromJson 内逐条校验丢弃，绝不让单个坏值炸掉整个设置。
      classReminders: ClassReminderEntry.listFromJson(json['classReminders']),
      courseCardTitleColorLight: parsedTitleColorLight,
      courseCardTitleColorDark: parsedTitleColorDark,
      courseCardDetailColorLight: parsedDetailColorLight,
      courseCardDetailColorDark: parsedDetailColorDark,
      weekdayBarFontColorLight: _migrateLegacyLightChromeInkToWhite(
        json['weekdayBarFontColorLight'] as String?,
        '#000000',
      ),
      weekdayBarFontColorDark:
          json['weekdayBarFontColorDark'] as String? ??
          defaultWeekdayBarFontColorDark,
      weekdayBarAccentColorLight:
          json['weekdayBarAccentColorLight'] as String? ??
          defaultWeekdayBarAccentColorLight,
      weekdayBarAccentColorDark:
          json['weekdayBarAccentColorDark'] as String? ??
          defaultWeekdayBarAccentColorDark,
      timeAxisFontColorLight: _migrateLegacyLightChromeInkToWhite(
        json['timeAxisFontColorLight'] as String?,
        '#757575',
      ),
      timeAxisFontColorDark:
          json['timeAxisFontColorDark'] as String? ??
          defaultTimeAxisFontColorDark,
      linkCourseCardColors: json['linkCourseCardColors'] as bool? ?? true,
      frostedSheetBlurSigma:
          (json['frostedSheetBlurSigma'] as num?)?.toDouble() ??
          defaultFrostedSheetBlurSigma,
      frostedSheetTintAlpha:
          (json['frostedSheetTintAlpha'] as num?)?.toDouble() ??
          defaultFrostedSheetTintAlpha,
      frostedSheetBarrierAlpha:
          (json['frostedSheetBarrierAlpha'] as num?)?.toDouble() ??
          defaultFrostedSheetBarrierAlpha,
      frostedBlurEnabled:
          json['frostedBlurEnabled'] as bool? ?? defaultFrostedBlurEnabled,
      homePageHeaderBlurEnabled:
          json['homePageHeaderBlurEnabled'] as bool? ?? false,
      homePageWeekdayBarBlurEnabled:
          json['homePageWeekdayBarBlurEnabled'] as bool? ?? false,
      homePageTimeColumnBlurEnabled:
          json['homePageTimeColumnBlurEnabled'] as bool? ?? false,
      homePageBackdropFollowsWeekPager:
          json['homePageBackdropFollowsWeekPager'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory TimetableSettings.fromJsonString(String jsonString) {
    return TimetableSettings.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  TimetableSettings copyWith({
    List<SectionTime>? sections,
    String? activeTimeSchemeId,
    double? sectionHeight,
    double? compactFontSize,
    bool? timetableAutoFitSectionHeight,
    int? semesterWeekCount,
    DateTime? semesterStartDate,
    bool? weeklyReportEnabled,
    bool? enableHolidayMarking,
    bool? timetableShowCurrentWeekCourses,
    bool? timetableShowNonCurrentWeekCourses,
    bool? showConflictBadgeOnTimetable,
    double? timetableConflictCourseOpacity,
    bool? courseCardShowName,
    bool? courseCardShowTeacher,
    bool? courseCardShowLocation,
    bool? courseCardShowTime,
    bool? courseCardShowTimeLabels,
    bool? courseCardShowWeeks,
    bool? courseCardShowDescription,
    CourseCardVerticalAlign? courseCardVerticalAlign,
    CourseCardHorizontalAlign? courseCardHorizontalAlign,
    double? courseCardFontSize,
    TimetableTimeColumnWidthMode? timetableTimeColumnWidthMode,
    double? timetableCourseCardGap,
    TimetableCourseSpacingMode? timetableCourseSpacingMode,
    WidgetBackgroundStyle? widgetBackgroundStyle,
    bool? widgetShowLocation,
    bool? widgetShowCountdown,
    bool? widgetHideCompletedCourses,
    bool? widgetShowTomorrowCourses,
    double? widgetHeightAdjustment,
    double? widgetCornerRadius,
    int? widgetCountdownLeadMinutes,
    LiveCountdownTextStyle? widgetCountdownTextStyle,
    AppThemeMode? appThemeMode,
    AppFontMode? appFontMode,
    String? appLocaleTag,
    HomeTitleStyle? homeTitleStyle,
    TimetableHomeViewMode? timetableHomeViewMode,
    HomeNavigationForm? homeNavigationForm,
    List<String>? glassDockActions,
    bool? glassDockShowDayTab,
    bool? glassDockShowSettingsTab,
    bool? glassDockShowWeekTab,
    String? glassDockButtonEntryId,
    String? glassDockButtonIconName,
    bool clearGlassDockButtonIconName = false,
    bool? glassDockShowAddButton,
    BackToCurrentWeekButtonStyle? timetableBackToCurrentWeekButtonStyle,
    double? timetableFloatingBackToCurrentWeekButtonOpacity,
    int? timetableLastViewedDayOfWeek,
    bool? coupleTimetableOverlayEnabled,
    bool? coupleTimetableDetailCardEnabled,
    SectionTimeDisplayMode? timetableSectionTimeDisplayMode,
    bool? timetableHideWeekends,
    bool? timetableVerticalScrollEffectEnabled,
    bool? enableHaptics,
    double? pageTransitionSpeed,
    bool? homePullQuickImportEnabled,
    bool? liveShowCourseName,
    bool? liveShowLocation,
    bool? liveShowCountdown,
    LiveCountdownTextStyle? liveCountdownTextStyle,
    bool? liveShowStageText,
    bool? liveEnableBeforeClass,
    bool? liveEnableDuringClass,
    bool? livePromoteDuringClass,
    bool? liveShowDuringClassNotification,
    bool? liveUseShortName,
    bool? liveFollowActiveTimetable,
    bool? liveHidePrefixText,
    LiveDuringClassTimeDisplayMode? liveDuringClassTimeDisplayMode,
    bool? liveEnableMiuiIslandLabelImage,
    bool? liveHideFromRecents,
    bool? liveEnableLocalDiagnostics,
    MiuiIslandLabelStyle? liveMiuiIslandLabelStyle,
    MiuiIslandLabelContent? liveMiuiIslandLabelContent,
    String? liveMiuiIslandLabelFontColor,
    MiuiIslandLabelFontWeight? liveMiuiIslandLabelFontWeight,
    MiuiIslandLabelRenderQuality? liveMiuiIslandLabelRenderQuality,
    double? liveMiuiIslandLabelFontSize,
    double? liveMiuiIslandLabelOffsetX,
    double? liveMiuiIslandLabelOffsetY,
    String? liveMiuiIslandLabelLogoPath,
    bool clearLiveMiuiIslandLabelLogoPath = false,
    double? liveMiuiIslandLabelLogoCornerRadius,
    MiuiIslandExpandedIconMode? liveMiuiIslandExpandedIconMode,
    String? liveMiuiIslandExpandedIconPath,
    bool clearLiveMiuiIslandExpandedIconPath = false,
    int? liveShowBeforeClassMinutes,
    int? liveClassReminderStartMinutes,
    int? liveTimeCorrectionSeconds,
    LiveBeforeClassQuickAction? liveBeforeClassQuickAction,
    int? liveBeforeClassQuickActionAutoMinutes,
    bool? livePermanentNotificationEnabled,
    String? timetablePageBackgroundColor,
    HomePageBackgroundFill? homePageBackgroundFill,
    String? homePageBackgroundImagePath,
    bool clearHomePageBackgroundImagePath = false,
    String? homePageWallpaperPath,
    bool clearHomePageWallpaperPath = false,
    double? homePageWallpaperAlignX,
    double? homePageWallpaperAlignY,
    double? homePageBackdropBlurSigma,
    double? homePageBackdropFrostAlpha,
    int? homePageBackgroundScope,
    bool? timetableUseUnifiedCardColor,
    String? timetableUnifiedCardColor,
    String? appUpdateDownloadSource,
    bool? appUpdateUseSystemDownloader,
    String? appUpdateMirrorPreset,
    String? appUpdateMirrorUrlPrefix,
    bool? appUpdatePromptEnabled,
    bool? holidayOverrideEnabled,
    int? classAlarmLeadMinutes,
    bool? classAlarmSkipUi,
    List<ClassReminderEntry>? classReminders,
    String? courseCardTitleColorLight,
    String? courseCardTitleColorDark,
    String? courseCardDetailColorLight,
    String? courseCardDetailColorDark,
    String? weekdayBarFontColorLight,
    String? weekdayBarFontColorDark,
    String? weekdayBarAccentColorLight,
    String? weekdayBarAccentColorDark,
    String? timeAxisFontColorLight,
    String? timeAxisFontColorDark,
    bool? linkCourseCardColors,
    double? frostedSheetBlurSigma,
    double? frostedSheetTintAlpha,
    double? frostedSheetBarrierAlpha,
    bool? frostedBlurEnabled,
    bool? homePageHeaderBlurEnabled,
    bool? homePageWeekdayBarBlurEnabled,
    bool? homePageTimeColumnBlurEnabled,
    bool? homePageBackdropFollowsWeekPager,
  }) {
    // 联动开时详情字色必须与标题字色一致：设置页在联动下本就同步写入，
    // 但旧版本数据 / 主题备份可能残留「联动开、详情色不同」的脏状态，渲染
    // 端会据此画出白标题+黑简介的混色卡。copyWith 是设置的统一写入口，在
    // 此顺手回填；独立模式（联动关）是用户显式选择，保留原值，由卡面渲染
    // 端做同极性兜底。fromJson 直达构造函数，另有同等规则的回填。
    final linkedCardTextColors =
        linkCourseCardColors ?? this.linkCourseCardColors;
    final healedDetailColorLight = linkedCardTextColors
        ? (courseCardTitleColorLight ?? this.courseCardTitleColorLight)
        : (courseCardDetailColorLight ?? this.courseCardDetailColorLight);
    final healedDetailColorDark = linkedCardTextColors
        ? (courseCardTitleColorDark ?? this.courseCardTitleColorDark)
        : (courseCardDetailColorDark ?? this.courseCardDetailColorDark);
    return TimetableSettings(
      sections: sections ?? this.sections,
      activeTimeSchemeId: activeTimeSchemeId ?? this.activeTimeSchemeId,
      sectionHeight: sectionHeight ?? this.sectionHeight,
      compactFontSize: compactFontSize ?? this.compactFontSize,
      timetableAutoFitSectionHeight:
          timetableAutoFitSectionHeight ?? this.timetableAutoFitSectionHeight,
      semesterWeekCount: semesterWeekCount ?? this.semesterWeekCount,
      semesterStartDate: semesterStartDate ?? this.semesterStartDate,
      weeklyReportEnabled: weeklyReportEnabled ?? this.weeklyReportEnabled,
      enableHolidayMarking: enableHolidayMarking ?? this.enableHolidayMarking,
      timetableShowNonCurrentWeekCourses:
          timetableShowNonCurrentWeekCourses ??
          this.timetableShowNonCurrentWeekCourses,
      showConflictBadgeOnTimetable:
          showConflictBadgeOnTimetable ?? this.showConflictBadgeOnTimetable,
      timetableConflictCourseOpacity:
          (timetableConflictCourseOpacity ??
                  this.timetableConflictCourseOpacity)
              .clamp(0.2, 1.0),
      courseCardShowName: courseCardShowName ?? this.courseCardShowName,
      courseCardShowTeacher:
          courseCardShowTeacher ?? this.courseCardShowTeacher,
      courseCardShowLocation:
          courseCardShowLocation ?? this.courseCardShowLocation,
      courseCardShowTime: courseCardShowTime ?? this.courseCardShowTime,
      courseCardShowTimeLabels:
          courseCardShowTimeLabels ?? this.courseCardShowTimeLabels,
      courseCardShowWeeks: courseCardShowWeeks ?? this.courseCardShowWeeks,
      courseCardShowDescription:
          courseCardShowDescription ?? this.courseCardShowDescription,
      courseCardVerticalAlign:
          courseCardVerticalAlign ?? this.courseCardVerticalAlign,
      courseCardHorizontalAlign:
          courseCardHorizontalAlign ?? this.courseCardHorizontalAlign,
      courseCardFontSize: courseCardFontSize ?? this.courseCardFontSize,
      timetableTimeColumnWidthMode:
          timetableTimeColumnWidthMode ?? this.timetableTimeColumnWidthMode,
      timetableCourseCardGap:
          timetableCourseCardGap ?? this.timetableCourseCardGap,
      timetableCourseSpacingMode:
          timetableCourseSpacingMode ?? this.timetableCourseSpacingMode,
      widgetBackgroundStyle:
          widgetBackgroundStyle ?? this.widgetBackgroundStyle,
      widgetShowLocation: widgetShowLocation ?? this.widgetShowLocation,
      widgetShowCountdown: widgetShowCountdown ?? this.widgetShowCountdown,
      widgetHideCompletedCourses:
          widgetHideCompletedCourses ?? this.widgetHideCompletedCourses,
      widgetShowTomorrowCourses:
          widgetShowTomorrowCourses ?? this.widgetShowTomorrowCourses,
      widgetHeightAdjustment:
          widgetHeightAdjustment ?? this.widgetHeightAdjustment,
      widgetCornerRadius: widgetCornerRadius ?? this.widgetCornerRadius,
      widgetCountdownLeadMinutes:
          widgetCountdownLeadMinutes ?? this.widgetCountdownLeadMinutes,
      widgetCountdownTextStyle:
          widgetCountdownTextStyle ?? this.widgetCountdownTextStyle,
      appThemeMode: appThemeMode ?? this.appThemeMode,
      appFontMode: appFontMode ?? this.appFontMode,
      appLocaleTag: _normalizeAppLocaleTag(appLocaleTag ?? this.appLocaleTag),
      homeTitleStyle: homeTitleStyle ?? this.homeTitleStyle,
      timetableHomeViewMode:
          timetableHomeViewMode ?? this.timetableHomeViewMode,
      homeNavigationForm: homeNavigationForm ?? this.homeNavigationForm,
      glassDockActions: glassDockActions == null
          ? this.glassDockActions
          : HomeDockMenu.normalize(glassDockActions),
      glassDockShowDayTab: glassDockShowDayTab ?? this.glassDockShowDayTab,
      glassDockShowSettingsTab:
          glassDockShowSettingsTab ?? this.glassDockShowSettingsTab,
      glassDockShowWeekTab: glassDockShowWeekTab ?? this.glassDockShowWeekTab,
      glassDockButtonEntryId:
          glassDockButtonEntryId ?? this.glassDockButtonEntryId,
      glassDockButtonIconName: clearGlassDockButtonIconName
          ? null
          : glassDockButtonIconName ?? this.glassDockButtonIconName,
      glassDockShowAddButton:
          glassDockShowAddButton ?? this.glassDockShowAddButton,
      timetableBackToCurrentWeekButtonStyle:
          timetableBackToCurrentWeekButtonStyle ??
          this.timetableBackToCurrentWeekButtonStyle,
      timetableFloatingBackToCurrentWeekButtonOpacity:
          (timetableFloatingBackToCurrentWeekButtonOpacity ??
                  this.timetableFloatingBackToCurrentWeekButtonOpacity)
              .clamp(0.55, 1.0),
      timetableLastViewedDayOfWeek:
          (timetableLastViewedDayOfWeek ?? this.timetableLastViewedDayOfWeek)
              .clamp(1, 7),
      coupleTimetableOverlayEnabled:
          coupleTimetableOverlayEnabled ?? this.coupleTimetableOverlayEnabled,
      coupleTimetableDetailCardEnabled:
          coupleTimetableDetailCardEnabled ??
          this.coupleTimetableDetailCardEnabled,
      timetableSectionTimeDisplayMode:
          timetableSectionTimeDisplayMode ??
          this.timetableSectionTimeDisplayMode,
      timetableHideWeekends:
          timetableHideWeekends ?? this.timetableHideWeekends,
      timetableVerticalScrollEffectEnabled:
          timetableVerticalScrollEffectEnabled ??
          this.timetableVerticalScrollEffectEnabled,
      enableHaptics: enableHaptics ?? this.enableHaptics,
      pageTransitionSpeed: (pageTransitionSpeed ?? this.pageTransitionSpeed)
          .clamp(minPageTransitionSpeed, maxPageTransitionSpeed),
      homePullQuickImportEnabled:
          homePullQuickImportEnabled ?? this.homePullQuickImportEnabled,
      liveShowCourseName: liveShowCourseName ?? this.liveShowCourseName,
      liveShowLocation: liveShowLocation ?? this.liveShowLocation,
      liveShowCountdown: liveShowCountdown ?? this.liveShowCountdown,
      liveCountdownTextStyle:
          liveCountdownTextStyle ?? this.liveCountdownTextStyle,
      liveShowStageText: liveShowStageText ?? this.liveShowStageText,
      liveEnableBeforeClass:
          liveEnableBeforeClass ?? this.liveEnableBeforeClass,
      liveEnableDuringClass:
          liveEnableDuringClass ?? this.liveEnableDuringClass,
      livePromoteDuringClass:
          livePromoteDuringClass ?? this.livePromoteDuringClass,
      liveShowDuringClassNotification:
          liveShowDuringClassNotification ??
          this.liveShowDuringClassNotification,
      liveUseShortName: liveUseShortName ?? this.liveUseShortName,
      liveFollowActiveTimetable:
          liveFollowActiveTimetable ?? this.liveFollowActiveTimetable,
      liveHidePrefixText: liveHidePrefixText ?? this.liveHidePrefixText,
      liveDuringClassTimeDisplayMode:
          liveDuringClassTimeDisplayMode ?? this.liveDuringClassTimeDisplayMode,
      liveEnableMiuiIslandLabelImage:
          liveEnableMiuiIslandLabelImage ?? this.liveEnableMiuiIslandLabelImage,
      liveHideFromRecents: liveHideFromRecents ?? this.liveHideFromRecents,
      liveEnableLocalDiagnostics:
          liveEnableLocalDiagnostics ?? this.liveEnableLocalDiagnostics,
      liveMiuiIslandLabelStyle:
          liveMiuiIslandLabelStyle ?? this.liveMiuiIslandLabelStyle,
      liveMiuiIslandLabelContent:
          liveMiuiIslandLabelContent ?? this.liveMiuiIslandLabelContent,
      liveMiuiIslandLabelFontColor:
          liveMiuiIslandLabelFontColor ?? this.liveMiuiIslandLabelFontColor,
      liveMiuiIslandLabelFontWeight:
          liveMiuiIslandLabelFontWeight ?? this.liveMiuiIslandLabelFontWeight,
      liveMiuiIslandLabelRenderQuality:
          liveMiuiIslandLabelRenderQuality ??
          this.liveMiuiIslandLabelRenderQuality,
      liveMiuiIslandLabelFontSize:
          liveMiuiIslandLabelFontSize ?? this.liveMiuiIslandLabelFontSize,
      liveMiuiIslandLabelOffsetX:
          liveMiuiIslandLabelOffsetX ?? this.liveMiuiIslandLabelOffsetX,
      liveMiuiIslandLabelOffsetY:
          liveMiuiIslandLabelOffsetY ?? this.liveMiuiIslandLabelOffsetY,
      liveMiuiIslandLabelLogoPath: clearLiveMiuiIslandLabelLogoPath
          ? null
          : liveMiuiIslandLabelLogoPath ?? this.liveMiuiIslandLabelLogoPath,
      liveMiuiIslandLabelLogoCornerRadius:
          liveMiuiIslandLabelLogoCornerRadius ??
          this.liveMiuiIslandLabelLogoCornerRadius,
      liveMiuiIslandExpandedIconMode:
          liveMiuiIslandExpandedIconMode ?? this.liveMiuiIslandExpandedIconMode,
      liveMiuiIslandExpandedIconPath: clearLiveMiuiIslandExpandedIconPath
          ? null
          : liveMiuiIslandExpandedIconPath ??
                this.liveMiuiIslandExpandedIconPath,
      liveShowBeforeClassMinutes:
          liveShowBeforeClassMinutes ?? this.liveShowBeforeClassMinutes,
      liveClassReminderStartMinutes:
          liveClassReminderStartMinutes ?? this.liveClassReminderStartMinutes,
      liveTimeCorrectionSeconds:
          liveTimeCorrectionSeconds ?? this.liveTimeCorrectionSeconds,
      liveBeforeClassQuickAction:
          liveBeforeClassQuickAction ?? this.liveBeforeClassQuickAction,
      liveBeforeClassQuickActionAutoMinutes:
          liveBeforeClassQuickActionAutoMinutes ??
          this.liveBeforeClassQuickActionAutoMinutes,
      livePermanentNotificationEnabled:
          livePermanentNotificationEnabled ?? this.livePermanentNotificationEnabled,
      timetablePageBackgroundColor:
          timetablePageBackgroundColor ?? this.timetablePageBackgroundColor,
      homePageBackgroundFill:
          homePageBackgroundFill ?? this.homePageBackgroundFill,
      homePageBackgroundImagePath: clearHomePageBackgroundImagePath
          ? null
          : homePageBackgroundImagePath ?? this.homePageBackgroundImagePath,
      homePageWallpaperPath: clearHomePageWallpaperPath
          ? null
          : homePageWallpaperPath ?? this.homePageWallpaperPath,
      homePageWallpaperAlignX:
          homePageWallpaperAlignX ?? this.homePageWallpaperAlignX,
      homePageWallpaperAlignY:
          homePageWallpaperAlignY ?? this.homePageWallpaperAlignY,
      homePageBackdropBlurSigma:
          homePageBackdropBlurSigma ?? this.homePageBackdropBlurSigma,
      homePageBackdropFrostAlpha:
          homePageBackdropFrostAlpha ?? this.homePageBackdropFrostAlpha,
      homePageBackgroundScope:
          homePageBackgroundScope ?? this.homePageBackgroundScope,
      timetableUseUnifiedCardColor:
          timetableUseUnifiedCardColor ?? this.timetableUseUnifiedCardColor,
      timetableUnifiedCardColor:
          timetableUnifiedCardColor ?? this.timetableUnifiedCardColor,
      appUpdateDownloadSource:
          appUpdateDownloadSource ?? this.appUpdateDownloadSource,
      appUpdateUseSystemDownloader:
          appUpdateUseSystemDownloader ?? this.appUpdateUseSystemDownloader,
      appUpdateMirrorPreset:
          appUpdateMirrorPreset ?? this.appUpdateMirrorPreset,
      appUpdateMirrorUrlPrefix:
          appUpdateMirrorUrlPrefix ?? this.appUpdateMirrorUrlPrefix,
      appUpdatePromptEnabled:
          appUpdatePromptEnabled ?? this.appUpdatePromptEnabled,
      holidayOverrideEnabled:
          holidayOverrideEnabled ?? this.holidayOverrideEnabled,
      // 提前量允许 0（下课即提醒的场景不存在，但保留合法输入区间）。
      classAlarmLeadMinutes:
          classAlarmLeadMinutes ?? this.classAlarmLeadMinutes,
      classAlarmSkipUi: classAlarmSkipUi ?? this.classAlarmSkipUi,
      classReminders: classReminders ?? this.classReminders,
      courseCardTitleColorLight:
          courseCardTitleColorLight ?? this.courseCardTitleColorLight,
      courseCardTitleColorDark:
          courseCardTitleColorDark ?? this.courseCardTitleColorDark,
      courseCardDetailColorLight: healedDetailColorLight,
      courseCardDetailColorDark: healedDetailColorDark,
      weekdayBarFontColorLight:
          weekdayBarFontColorLight ?? this.weekdayBarFontColorLight,
      weekdayBarFontColorDark:
          weekdayBarFontColorDark ?? this.weekdayBarFontColorDark,
      weekdayBarAccentColorLight:
          weekdayBarAccentColorLight ?? this.weekdayBarAccentColorLight,
      weekdayBarAccentColorDark:
          weekdayBarAccentColorDark ?? this.weekdayBarAccentColorDark,
      timeAxisFontColorLight:
          timeAxisFontColorLight ?? this.timeAxisFontColorLight,
      timeAxisFontColorDark:
          timeAxisFontColorDark ?? this.timeAxisFontColorDark,
      linkCourseCardColors: linkCourseCardColors ?? this.linkCourseCardColors,
      frostedSheetBlurSigma:
          frostedSheetBlurSigma ?? this.frostedSheetBlurSigma,
      frostedSheetTintAlpha:
          frostedSheetTintAlpha ?? this.frostedSheetTintAlpha,
      frostedSheetBarrierAlpha:
          frostedSheetBarrierAlpha ?? this.frostedSheetBarrierAlpha,
      frostedBlurEnabled: frostedBlurEnabled ?? this.frostedBlurEnabled,
      homePageHeaderBlurEnabled:
          homePageHeaderBlurEnabled ?? this.homePageHeaderBlurEnabled,
      homePageWeekdayBarBlurEnabled:
          homePageWeekdayBarBlurEnabled ?? this.homePageWeekdayBarBlurEnabled,
      homePageTimeColumnBlurEnabled:
          homePageTimeColumnBlurEnabled ?? this.homePageTimeColumnBlurEnabled,
      homePageBackdropFollowsWeekPager:
          homePageBackdropFollowsWeekPager ??
          this.homePageBackdropFollowsWeekPager,
    );
  }

  int get sectionCount => sections.length;

  LiveDisplaySettings get beforeClassDisplaySettings => LiveDisplaySettings(
    showCourseName: liveShowCourseName,
    showLocation: liveShowLocation,
    showCountdown: liveShowCountdown,
    countdownTextStyle: liveCountdownTextStyle,
    showStageText: liveShowStageText,
    useShortName: liveUseShortName,
    hidePrefixText: liveHidePrefixText,
    duringClassTimeDisplayMode: liveDuringClassTimeDisplayMode,
    enableMiuiIslandLabelImage: liveEnableMiuiIslandLabelImage,
    miuiIslandLabelStyle: liveMiuiIslandLabelStyle,
    miuiIslandLabelContent: liveMiuiIslandLabelContent,
    miuiIslandLabelFontColor: liveMiuiIslandLabelFontColor,
    miuiIslandLabelFontWeight: liveMiuiIslandLabelFontWeight,
    miuiIslandLabelRenderQuality: liveMiuiIslandLabelRenderQuality,
    miuiIslandLabelFontSize: liveMiuiIslandLabelFontSize,
    miuiIslandLabelOffsetX: liveMiuiIslandLabelOffsetX,
    miuiIslandLabelOffsetY: liveMiuiIslandLabelOffsetY,
    miuiIslandLabelLogoPath: liveMiuiIslandLabelLogoPath,
    miuiIslandLabelLogoCornerRadius: liveMiuiIslandLabelLogoCornerRadius,
    miuiIslandExpandedIconMode: liveMiuiIslandExpandedIconMode,
    miuiIslandExpandedIconPath: liveMiuiIslandExpandedIconPath,
  );

  /// 课中/下课一律沿用课前那套显示配置。
  ///
  /// 样式配置已从设置界面移除（后续改为固定样式），课中/下课不再有独立配置，
  /// 因此这里恒返回 [beforeClassDisplaySettings]。
  ///
  /// 历史上课中/下课曾有一整套 `liveDuringEnd*` 字段与一个「跟随课前」开关：
  /// 关掉开关的用户会停在另一套配置上，而那套配置在样式界面移除后再无入口可改，
  /// 改不动也看不见。字段与其序列化已随本次清理删除；旧存档里这些键会被
  /// 忽略，读回后课中/下课直接沿用课前配置。
  LiveDisplaySettings get duringEndDisplaySettings => beforeClassDisplaySettings;

  TimetableSettings copyWithBeforeClassDisplaySettings(
    LiveDisplaySettings settings, {
    bool clearExpandedIconPath = false,
    bool clearLabelLogoPath = false,
  }) {
    return copyWith(
      liveShowCourseName: settings.showCourseName,
      liveShowLocation: settings.showLocation,
      liveShowCountdown: settings.showCountdown,
      liveCountdownTextStyle: settings.countdownTextStyle,
      liveShowStageText: settings.showStageText,
      liveUseShortName: settings.useShortName,
      liveHidePrefixText: settings.hidePrefixText,
      liveDuringClassTimeDisplayMode: settings.duringClassTimeDisplayMode,
      liveEnableMiuiIslandLabelImage: settings.enableMiuiIslandLabelImage,
      liveMiuiIslandLabelStyle: settings.miuiIslandLabelStyle,
      liveMiuiIslandLabelContent: settings.miuiIslandLabelContent,
      liveMiuiIslandLabelFontColor: settings.miuiIslandLabelFontColor,
      liveMiuiIslandLabelFontWeight: settings.miuiIslandLabelFontWeight,
      liveMiuiIslandLabelRenderQuality: settings.miuiIslandLabelRenderQuality,
      liveMiuiIslandLabelFontSize: settings.miuiIslandLabelFontSize,
      liveMiuiIslandLabelOffsetX: settings.miuiIslandLabelOffsetX,
      liveMiuiIslandLabelOffsetY: settings.miuiIslandLabelOffsetY,
      liveMiuiIslandLabelLogoPath: settings.miuiIslandLabelLogoPath,
      liveMiuiIslandLabelLogoCornerRadius:
          settings.miuiIslandLabelLogoCornerRadius,
      clearLiveMiuiIslandLabelLogoPath: clearLabelLogoPath,
      liveMiuiIslandExpandedIconMode: settings.miuiIslandExpandedIconMode,
      liveMiuiIslandExpandedIconPath: settings.miuiIslandExpandedIconPath,
      clearLiveMiuiIslandExpandedIconPath: clearExpandedIconPath,
    );
  }

  TimetableSettings copyWithDuringEndDisplaySettings(
    LiveDisplaySettings settings, {
    bool clearExpandedIconPath = false,
    bool clearLabelLogoPath = false,
  }) {
    return copyWith(
    );
  }

  List<int> get availableWeeks =>
      List.generate(semesterWeekCount, (index) => index + 1);

  SectionTime sectionAt(int section) => sections[section - 1];
}
