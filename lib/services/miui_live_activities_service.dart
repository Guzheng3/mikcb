import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/course.dart';
import '../models/timetable_settings.dart';
import '../logging/app_debug_log.dart';
import '../logging/app_log_messages.dart';
import 'app_log_service.dart';
import 'umeng_analytics_service.dart';

class MiuiLiveActivitiesService {
  static const MethodChannel _channel = MethodChannel(
    'vip.qinghan.withu/miui_live',
  );

  static final MiuiLiveActivitiesService _instance =
      MiuiLiveActivitiesService._internal();
  factory MiuiLiveActivitiesService() => _instance;
  MiuiLiveActivitiesService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _channel.invokeMethod('initialize');
      _isInitialized = true;
    } catch (e, stackTrace) {
      await AppLogService.instance.error(
        'miui_live_initialize_failed',
        AppLogMessages.miuiLiveInitializeFailed,
        error: e,
        stackTrace: stackTrace,
      );
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_flutter_initialize_failed',
        AppLogMessages.miuiLiveInitializeFailed,
        error: e,
        stackTrace: stackTrace,
      );
      appDebugLog('MiuiLive', '初始化失败：$e');
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod(
        'requestNotificationPermission',
      );
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 是否小米系设备（Redmi / POCO 同族）。
  ///
  /// 岛左侧文字标签这类能力原生只对小米系下发（另见 ColorOS 走标准提升通知
  /// 通道），界面据此隐藏对自己无效的设置项。判据与原生 `liveSurfaceBrand`
  /// 共用一份，避免两边品牌规则漂移。
  /// 刻意不做 `Platform.isAndroid` 短路：非 Android 上 `invokeMethod` 会抛
  /// MissingPluginException，下面的 catch 已兜底返回 false；留着短路会让测试
  /// 无法 mock 通道、覆盖不到小米分支。
  Future<bool> isXiaomiFamilyDevice() async {
    try {
      final result = await _channel.invokeMethod('isXiaomiFamilyDevice');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod('checkNotificationPermission');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  // 检查推广通知支持
  Future<Map<String, dynamic>> checkPromotedSupport() async {
    try {
      final result = await _channel.invokeMethod('checkPromotedSupport');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      return {
        'androidVersion': 0,
        'hasNotificationPermission': false,
        'hasPromotedPermission': false,
        'canPostPromoted': false,
      };
    }
  }

  // 打开推广通知设置
  Future<void> openPromotedSettings() async {
    try {
      await _channel.invokeMethod('openPromotedSettings');
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'miui_live_open_promoted_settings_failed',
          AppLogMessages.miuiLiveOpenPromotedSettingsFailed,
          extras: {'error': '$e'},
        ),
      );
      appDebugLog('MiuiLive', '打开设置失败：$e');
    }
  }

  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'miui_live_open_notification_settings_failed',
          AppLogMessages.miuiLiveOpenNotificationSettingsFailed,
          extras: {'error': '$e'},
        ),
      );
      appDebugLog('MiuiLive', '打开通知设置失败：$e');
    }
  }

  Future<void> openAutoStartSettings() async {
    try {
      await _channel.invokeMethod('openAutoStartSettings');
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'miui_live_open_autostart_settings_failed',
          AppLogMessages.miuiLiveOpenAutostartSettingsFailed,
          extras: {'error': '$e'},
        ),
      );
      appDebugLog('MiuiLive', '打开自启动设置失败：$e');
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'miui_live_open_battery_settings_failed',
          AppLogMessages.miuiLiveOpenBatterySettingsFailed,
          extras: {'error': '$e'},
        ),
      );
      appDebugLog('MiuiLive', '打开电池优化设置失败：$e');
    }
  }

  Future<bool> isAutoStartEnabled() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod('isAutoStartEnabled');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  Future<void> setHideFromRecents(bool value) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setHideFromRecents', value);
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'miui_live_hide_from_recents_failed',
          AppLogMessages.miuiLiveHideFromRecentsFailed,
          extras: {'error': '$e', 'value': value},
        ),
      );
      appDebugLog('MiuiLive', '更新从最近任务隐藏失败：$e');
    }
  }

  Future<void> setLiveDiagnosticsEnabled(bool value) async {
    await UmengAnalyticsService.setLiveDiagnosticsEnabled(value);
  }

  /// 同步「常驻通知」开关到原生侧。
  ///
  /// 必须独立于 startLiveUpdate 下发：无课程会话时 Flutter 根本不会启动会话，
  /// 用户在这个时刻关掉开关的话，原生落盘值会一直停在 true，下一次开机或启动
  /// 就会把常驻通知又挂回来。
  Future<void> setPermanentNotification(bool value) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setPermanentNotification', value);
    } catch (e) {
      unawaited(
        AppLogService.instance.warn(
          'live_permanent_notification_failed',
          AppLogMessages.liveUpdatePermanentNotificationFailed,
          extras: {'error': '$e', 'value': value},
        ),
      );
      appDebugLog('MiuiLive', '更新常驻通知开关失败：$e');
    }
  }

  Future<void> recordDiagnosticEvent(
    String category,
    String message, {
    Map<String, Object?> extras = const {},
    DiagnosticLogLevel level = DiagnosticLogLevels.info,
  }) async {
    await UmengAnalyticsService.recordDiagnosticEvent(
      category,
      message,
      extras: extras,
      level: level,
    );
  }

  Future<String?> exportLiveDiagnosticsFile() async {
    return UmengAnalyticsService.exportLiveDiagnosticsFile();
  }

  Future<String?> readLiveDiagnosticsText() async {
    return UmengAnalyticsService.readLiveDiagnosticsText();
  }

  Stream<String> watchLiveDiagnosticsText({
    Duration interval = const Duration(seconds: 1),
  }) {
    late final StreamController<String> controller;
    Timer? pollTimer;
    var closed = false;
    String? lastEmitted;

    Future<void> poll() async {
      if (closed) {
        return;
      }
      try {
        final text = await readLiveDiagnosticsText();
        final normalized = text ?? '';
        if (closed || normalized == lastEmitted) {
          return;
        }
        lastEmitted = normalized;
        controller.add(normalized);
      } catch (error, stackTrace) {
        if (!closed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<String>(
      onListen: () {
        poll();
        pollTimer = Timer.periodic(interval, (_) => poll());
      },
      onCancel: () {
        closed = true;
        pollTimer?.cancel();
      },
    );

    return controller.stream;
  }

  Future<bool> clearLiveDiagnostics() async {
    return UmengAnalyticsService.clearLiveDiagnostics();
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod(
        'isIgnoringBatteryOptimizations',
      );
      return result == true;
    } catch (e) {
      return false;
    }
  }

  Future<void> startLiveUpdate(
    Course currentCourse,
    Course? nextCourse, {
    int autoDismissAfterStartMinutes = 0,
    String? stage,
    int beforeClassLeadMillis = 0,
    int? startAtMillis,
    int? endAtMillis,
    int liveClassReminderStartMinutes = 0,
    bool promoteDuringClass = true,
    bool showNotificationDuringClass = true,
    bool enableBeforeClass = true,
    bool enableDuringClass = true,
    bool showCountdown = true,
    LiveCountdownTextStyle countdownTextStyle = LiveCountdownTextStyle.smart,
    bool showStageText = true,
    bool showCourseNameInIsland = true,
    bool showLocationInIsland = true,
    bool useShortNameInIsland = true,
    bool hidePrefixText = false,
    LiveDuringClassTimeDisplayMode duringClassTimeDisplayMode =
        LiveDuringClassTimeDisplayMode.nearest,
    bool enableMiuiIslandLabelImage = false,
    MiuiIslandLabelStyle miuiIslandLabelStyle = MiuiIslandLabelStyle.textOnly,
    MiuiIslandLabelContent miuiIslandLabelContent =
        MiuiIslandLabelContent.courseName,
    String miuiIslandLabelFontColor = '#FFFFFF',
    MiuiIslandLabelFontWeight miuiIslandLabelFontWeight =
        MiuiIslandLabelFontWeight.bold,
    MiuiIslandLabelRenderQuality miuiIslandLabelRenderQuality =
        MiuiIslandLabelRenderQuality.standard,
    double miuiIslandLabelFontSize = 14,
    double miuiIslandLabelOffsetX = 0,
    double miuiIslandLabelOffsetY = 0,
    String? miuiIslandLabelLogoPath,
    double miuiIslandLabelLogoCornerRadius = 8,
    MiuiIslandExpandedIconMode miuiIslandExpandedIconMode =
        MiuiIslandExpandedIconMode.appIcon,
    String? miuiIslandExpandedIconPath,
    LiveBeforeClassQuickAction beforeClassQuickAction =
        LiveBeforeClassQuickAction.none,
    int beforeClassQuickActionAutoMinutes = 0,
    List<int> progressBreakOffsetsMillis = const [],
    List<String> progressMilestoneLabels = const [],
    List<String> progressMilestoneTimeTexts = const [],
    bool validateAgainstSchedule = false,
    bool permanentNotification = true,
  }) async {
    await initialize();
    try {
      final data = _buildData(
        currentCourse,
        nextCourse,
        autoDismissAfterStartMinutes: autoDismissAfterStartMinutes,
        stage: stage,
        beforeClassLeadMillis: beforeClassLeadMillis,
        validateAgainstSchedule: validateAgainstSchedule,
        startAtMillis: startAtMillis,
        endAtMillis: endAtMillis,
        liveClassReminderStartMinutes: liveClassReminderStartMinutes,
        promoteDuringClass: promoteDuringClass,
        showNotificationDuringClass: showNotificationDuringClass,
        enableBeforeClass: enableBeforeClass,
        enableDuringClass: enableDuringClass,
        showCountdown: showCountdown,
        countdownTextStyle: countdownTextStyle,
        showStageText: showStageText,
        showCourseNameInIsland: showCourseNameInIsland,
        showLocationInIsland: showLocationInIsland,
        useShortNameInIsland: useShortNameInIsland,
        hidePrefixText: hidePrefixText,
        duringClassTimeDisplayMode: duringClassTimeDisplayMode,
        enableMiuiIslandLabelImage: enableMiuiIslandLabelImage,
        miuiIslandLabelStyle: miuiIslandLabelStyle,
        miuiIslandLabelContent: miuiIslandLabelContent,
        miuiIslandLabelFontColor: miuiIslandLabelFontColor,
        miuiIslandLabelFontWeight: miuiIslandLabelFontWeight,
        miuiIslandLabelRenderQuality: miuiIslandLabelRenderQuality,
        miuiIslandLabelFontSize: miuiIslandLabelFontSize,
        miuiIslandLabelOffsetX: miuiIslandLabelOffsetX,
        miuiIslandLabelOffsetY: miuiIslandLabelOffsetY,
        miuiIslandLabelLogoPath: miuiIslandLabelLogoPath,
        miuiIslandLabelLogoCornerRadius: miuiIslandLabelLogoCornerRadius,
        miuiIslandExpandedIconMode: miuiIslandExpandedIconMode,
        miuiIslandExpandedIconPath: miuiIslandExpandedIconPath,
        beforeClassQuickAction: beforeClassQuickAction,
        beforeClassQuickActionAutoMinutes: beforeClassQuickActionAutoMinutes,
        progressBreakOffsetsMillis: progressBreakOffsetsMillis,
        progressMilestoneLabels: progressMilestoneLabels,
        progressMilestoneTimeTexts: progressMilestoneTimeTexts,
        permanentNotification: permanentNotification,
      );
      await _channel.invokeMethod('startLiveUpdate', data);
    } catch (e, stackTrace) {
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_start_failed',
        AppLogMessages.liveUpdateStartFailed,
        error: e,
        stackTrace: stackTrace,
      );
      appDebugLog('MiuiLive', '启动超级岛失败：$e');
    }
  }

  Future<void> stopLiveUpdate() async {
    try {
      await _channel.invokeMethod('stopLiveUpdate');
    } catch (e, stackTrace) {
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_stop_failed',
        AppLogMessages.liveUpdateStopFailed,
        error: e,
        stackTrace: stackTrace,
      );
      appDebugLog('MiuiLive', '停止超级岛失败：$e');
    }
  }

  Future<Map<String, dynamic>> getLiveUpdateDebugStatus() async {
    await initialize();
    try {
      final result = await _channel.invokeMethod('getLiveUpdateDebugStatus');
      return Map<String, dynamic>.from(result as Map);
    } catch (e, stackTrace) {
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_debug_status_failed',
        AppLogMessages.liveUpdateDebugStatusFailed,
        error: e,
        stackTrace: stackTrace,
      );
      appDebugLog('MiuiLive', '获取超级岛调试状态失败：$e');
      return {
        'summary': {
          'serviceRunning': false,
          'statusText': '读取失败',
          'notIslandReason': e.toString(),
        },
      };
    }
  }

  Map<String, dynamic> _buildData(
    Course currentCourse,
    Course? nextCourse, {
    int autoDismissAfterStartMinutes = 0,
    String? stage,
    int beforeClassLeadMillis = 0,
    int? startAtMillis,
    int? endAtMillis,
    int liveClassReminderStartMinutes = 0,
    bool promoteDuringClass = true,
    bool showNotificationDuringClass = true,
    bool enableBeforeClass = true,
    bool enableDuringClass = true,
    bool showCountdown = true,
    LiveCountdownTextStyle countdownTextStyle = LiveCountdownTextStyle.smart,
    bool showStageText = true,
    bool showCourseNameInIsland = true,
    bool showLocationInIsland = true,
    bool useShortNameInIsland = true,
    bool hidePrefixText = false,
    LiveDuringClassTimeDisplayMode duringClassTimeDisplayMode =
        LiveDuringClassTimeDisplayMode.nearest,
    bool enableMiuiIslandLabelImage = false,
    MiuiIslandLabelStyle miuiIslandLabelStyle = MiuiIslandLabelStyle.textOnly,
    MiuiIslandLabelContent miuiIslandLabelContent =
        MiuiIslandLabelContent.courseName,
    String miuiIslandLabelFontColor = '#FFFFFF',
    MiuiIslandLabelFontWeight miuiIslandLabelFontWeight =
        MiuiIslandLabelFontWeight.bold,
    MiuiIslandLabelRenderQuality miuiIslandLabelRenderQuality =
        MiuiIslandLabelRenderQuality.standard,
    double miuiIslandLabelFontSize = 14,
    double miuiIslandLabelOffsetX = 0,
    double miuiIslandLabelOffsetY = 0,
    String? miuiIslandLabelLogoPath,
    double miuiIslandLabelLogoCornerRadius = 8,
    MiuiIslandExpandedIconMode miuiIslandExpandedIconMode =
        MiuiIslandExpandedIconMode.appIcon,
    String? miuiIslandExpandedIconPath,
    LiveBeforeClassQuickAction beforeClassQuickAction =
        LiveBeforeClassQuickAction.none,
    int beforeClassQuickActionAutoMinutes = 0,
    List<int> progressBreakOffsetsMillis = const [],
    List<String> progressMilestoneLabels = const [],
    List<String> progressMilestoneTimeTexts = const [],
    bool validateAgainstSchedule = false,
    bool permanentNotification = true,
  }) {
    final data = <String, dynamic>{
      'autoDismissAfterStartMinutes': autoDismissAfterStartMinutes,
      'stage': stage,
      'beforeClassLeadMillis': beforeClassLeadMillis,
      'validateAgainstSchedule': validateAgainstSchedule,
      'permanentNotification': permanentNotification,
      'startAtMillis': startAtMillis,
      'endAtMillis': endAtMillis,
      'liveClassReminderStartMinutes': liveClassReminderStartMinutes,
      'beforeClassQuickAction': beforeClassQuickAction.value,
      'beforeClassQuickActionAutoMinutes': beforeClassQuickActionAutoMinutes,
      'promoteDuringClass': promoteDuringClass,
      'showNotificationDuringClass': showNotificationDuringClass,
      'enableBeforeClass': enableBeforeClass,
      'enableDuringClass': enableDuringClass,
      'showCountdown': showCountdown,
      'countdownTextStyle': countdownTextStyle.value,
      'showStageText': showStageText,
      'progressBreakOffsetsMillis': progressBreakOffsetsMillis,
      'progressMilestoneLabels': progressMilestoneLabels,
      'progressMilestoneTimeTexts': progressMilestoneTimeTexts,
      'islandConfig': {
        'showCourseName': showCourseNameInIsland,
        'showLocation': showLocationInIsland,
        'useShortName': useShortNameInIsland,
        'hidePrefixText': hidePrefixText,
        'duringClassTimeDisplayMode': duringClassTimeDisplayMode.value,
        'enableMiuiIslandLabelImage': enableMiuiIslandLabelImage,
        'miuiIslandLabelStyle': miuiIslandLabelStyle.value,
        'miuiIslandLabelContent': miuiIslandLabelContent.value,
        'miuiIslandLabelFontColor': miuiIslandLabelFontColor,
        'miuiIslandLabelFontWeight': miuiIslandLabelFontWeight.value,
        'miuiIslandLabelRenderQuality': miuiIslandLabelRenderQuality.value,
        'miuiIslandLabelFontSize': miuiIslandLabelFontSize,
        'miuiIslandLabelOffsetX': miuiIslandLabelOffsetX,
        'miuiIslandLabelOffsetY': miuiIslandLabelOffsetY,
        'miuiIslandLabelLogoPath': miuiIslandLabelLogoPath,
        'miuiIslandLabelLogoCornerRadius': miuiIslandLabelLogoCornerRadius,
        'miuiIslandExpandedIconMode': miuiIslandExpandedIconMode.value,
        'miuiIslandExpandedIconPath': miuiIslandExpandedIconPath,
      },
      'currentCourse': {
        'name': currentCourse.name,
        'shortName': currentCourse.shortName,
        'teacher': currentCourse.teacher,
        'location': currentCourse.location,
        'note': currentCourse.note,
        'startTime': currentCourse.startTime,
        'endTime': currentCourse.endTime,
      },
    };
    if (nextCourse != null) {
      data['nextCourse'] = {
        'name': nextCourse.name,
        'shortName': nextCourse.shortName,
        'teacher': nextCourse.teacher,
        'location': nextCourse.location,
        'note': nextCourse.note,
        'startTime': nextCourse.startTime,
        'endTime': nextCourse.endTime,
      };
    }
    return data;
  }

  Future<bool> syncScheduleSnapshot({
    required List<Course> courses,
    required TimetableSettings settings,
    required int currentWeek,
    DateTime? semesterStartDate,
    bool isHoliday = false,
    List<String> holidayDates = const [],
    List<String> adjustedWorkdayDates = const [],
    bool holidayOverrideEnabled = false,
    bool enableHolidayMarking = true,
    String? isHolidayDate,
  }) async {
    await initialize();
    try {
      final snapshotJson = jsonEncode({
        'currentWeek': currentWeek,
        'semesterStartMillis': semesterStartDate?.millisecondsSinceEpoch,
        'isHoliday': isHoliday,
        'isHolidayDate': isHolidayDate,
        'holidayDates': holidayDates,
        'adjustedWorkdayDates': adjustedWorkdayDates,
        'holidayOverrideEnabled': holidayOverrideEnabled,
        'enableHolidayMarking': enableHolidayMarking,
        'courses': courses.map((course) => course.toJson()).toList(),
        'settings': settings.toJson(),
      });
      await _channel.invokeMethod('syncScheduleSnapshot', snapshotJson);
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_settings_synced',
        AppLogMessages.liveUpdateSettingsSynced(
          beforeClass: settings.liveEnableBeforeClass,
          duringClass: settings.liveEnableDuringClass,
          promote: settings.livePromoteDuringClass,
          notification: settings.liveShowDuringClassNotification,
          countdown: settings.liveShowCountdown,
          courseName: settings.liveShowCourseName,
          location: settings.liveShowLocation,
        ),
      );
      return true;
    } catch (e, stackTrace) {
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_snapshot_sync_failed',
        AppLogMessages.liveUpdateSnapshotSyncFailed,
        error: e,
        stackTrace: stackTrace,
      );
      appDebugLog('MiuiLive', '同步课表快照失败：$e');
      return false;
    }
  }

  Future<bool> clearScheduleSnapshot() async {
    await initialize();
    try {
      await _channel.invokeMethod('clearScheduleSnapshot');
      return true;
    } catch (e, stackTrace) {
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_snapshot_clear_failed',
        AppLogMessages.liveUpdateSnapshotClearFailed,
        error: e,
        stackTrace: stackTrace,
      );
      appDebugLog('MiuiLive', '清空课表快照失败：$e');
      return false;
    }
  }

  Future<bool> suspendScheduleTriggers(int untilMillis) async {
    await initialize();
    try {
      await _channel.invokeMethod('suspendScheduleTriggers', untilMillis);
      return true;
    } catch (e, stackTrace) {
      await UmengAnalyticsService.reportDiagnostic(
        'live_update_suspend_triggers_failed',
        AppLogMessages.liveUpdateSuspendTriggersFailed,
        error: e,
        stackTrace: stackTrace,
      );
      appDebugLog('MiuiLive', '挂起课表调度失败：$e');
      return false;
    }
  }
}

/// Lightweight in-memory test double; does not call the native channel.
@visibleForTesting
class TestMiuiLiveActivitiesService extends MiuiLiveActivitiesService {
  TestMiuiLiveActivitiesService() : super._internal();

  int stopLiveUpdateCallCount = 0;
  int startLiveUpdateCallCount = 0;
  int syncScheduleSnapshotCallCount = 0;
  /// 最近一次同步给原生侧的快照课程（含解析后的时间），供断言使用。
  List<Course>? lastSyncedCourses;

  @override
  Future<void> stopLiveUpdate() async {
    stopLiveUpdateCallCount++;
  }

  @override
  Future<void> startLiveUpdate(
    Course currentCourse,
    Course? nextCourse, {
    int autoDismissAfterStartMinutes = 0,
    String? stage,
    int beforeClassLeadMillis = 0,
    int? startAtMillis,
    int? endAtMillis,
    int liveClassReminderStartMinutes = 0,
    bool promoteDuringClass = true,
    bool showNotificationDuringClass = true,
    bool enableBeforeClass = true,
    bool enableDuringClass = true,
    bool showCountdown = true,
    LiveCountdownTextStyle countdownTextStyle = LiveCountdownTextStyle.smart,
    bool showStageText = true,
    bool showCourseNameInIsland = true,
    bool showLocationInIsland = true,
    bool useShortNameInIsland = true,
    bool hidePrefixText = false,
    LiveDuringClassTimeDisplayMode duringClassTimeDisplayMode =
        LiveDuringClassTimeDisplayMode.nearest,
    bool enableMiuiIslandLabelImage = false,
    MiuiIslandLabelStyle miuiIslandLabelStyle = MiuiIslandLabelStyle.textOnly,
    MiuiIslandLabelContent miuiIslandLabelContent =
        MiuiIslandLabelContent.courseName,
    String miuiIslandLabelFontColor = '#FFFFFF',
    MiuiIslandLabelFontWeight miuiIslandLabelFontWeight =
        MiuiIslandLabelFontWeight.bold,
    MiuiIslandLabelRenderQuality miuiIslandLabelRenderQuality =
        MiuiIslandLabelRenderQuality.standard,
    double miuiIslandLabelFontSize = 14,
    double miuiIslandLabelOffsetX = 0,
    double miuiIslandLabelOffsetY = 0,
    String? miuiIslandLabelLogoPath,
    double miuiIslandLabelLogoCornerRadius = 8,
    MiuiIslandExpandedIconMode miuiIslandExpandedIconMode =
        MiuiIslandExpandedIconMode.appIcon,
    String? miuiIslandExpandedIconPath,
    LiveBeforeClassQuickAction beforeClassQuickAction =
        LiveBeforeClassQuickAction.none,
    int beforeClassQuickActionAutoMinutes = 0,
    List<int> progressBreakOffsetsMillis = const [],
    List<String> progressMilestoneLabels = const [],
    List<String> progressMilestoneTimeTexts = const [],
    bool validateAgainstSchedule = false,
    bool permanentNotification = true,
  }) async {
    startLiveUpdateCallCount++;
  }

  @override
  Future<bool> syncScheduleSnapshot({
    required List<Course> courses,
    required TimetableSettings settings,
    required int currentWeek,
    DateTime? semesterStartDate,
    bool isHoliday = false,
    List<String> holidayDates = const [],
    List<String> adjustedWorkdayDates = const [],
    bool holidayOverrideEnabled = false,
    bool enableHolidayMarking = true,
    String? isHolidayDate,
  }) async {
    syncScheduleSnapshotCallCount++;
    lastSyncedCourses = List<Course>.unmodifiable(courses);
    return true;
  }

  @override
  Future<bool> suspendScheduleTriggers(int untilMillis) async {
    return true;
  }

  @override
  Future<bool> clearScheduleSnapshot() async {
    return true;
  }
}
