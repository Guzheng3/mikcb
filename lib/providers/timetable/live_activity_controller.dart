part of '../timetable_provider.dart';

/// 灵动岛/超级岛、原生课程快照与上课·考试提醒共同依据的课表数据域。
///
/// 这三个界面服务的是「用户自己的课」，与「主界面正在浏览哪份课表」不是
/// 同一件事。桌面情侣卡片右半会把当前课表切到 TA（见 `WidgetLaunchRouter`），
/// 若这些界面继续跟随 [TimetableProvider.activeProfile]，只要看一眼对方的
/// 课表，自己的上课提醒与岛就被换成对方的。
///
/// 因此统一取 [TimetableProvider.myTimetableProfile]：
/// - 当前课表就是我的课表时两者等价，且优先取内存态字段（课程可能有尚未
///   flush 回 profile 列表的编辑），与原 active 路径逐字一致；
/// - 当前课表是 TA 时，改用「我的课表」自身持久化的课程/设置/周次。
class _MyTimetableScope {
  const _MyTimetableScope({
    required this.profile,
    required this.settings,
    required this.courses,
    required this.exams,
    required this.scheduleItems,
    required this.currentWeek,
    required this.currentCalendarWeek,
  });

  final TimetableProfile profile;
  final TimetableSettings settings;
  final List<Course> courses;
  final List<Exam> exams;
  final List<ScheduleItem> scheduleItems;
  final int currentWeek;
  final int currentCalendarWeek;

  int calendarWeekFor(DateTime date, {int? fallbackWeek}) =>
      WeekCalculator.calendarWeekForDate(
        date,
        semesterStart: settings.semesterStartDate,
        fallback: fallbackWeek ?? currentCalendarWeek,
      );

  List<Course> coursesForDay(
    int dayOfWeek,
    int week, {
    required bool activeOnly,
  }) {
    return courses
        .where(
          (course) =>
              course.dayOfWeek == dayOfWeek &&
              (activeOnly
                  ? course.isActiveInWeek(week)
                  : course.isInWeek(week)),
        )
        .toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
  }
}

/// 构建「我的课表」数据域；无可用课表时返回 null。
_MyTimetableScope? _liveMyTimetableScope(TimetableProvider host) {
  final profile = host.myTimetableProfile;
  if (profile == null) {
    return null;
  }
  if (profile.id == host._activeProfileId) {
    return _MyTimetableScope(
      profile: profile,
      settings: host._settings,
      courses: host._courses,
      exams: host._exams,
      scheduleItems: host._scheduleItems,
      currentWeek: host._currentWeek,
      currentCalendarWeek: host._currentCalendarWeek,
    );
  }
  return _MyTimetableScope(
    profile: profile,
    settings: profile.settings,
    courses: profile.courses,
    exams: profile.exams,
    scheduleItems: host._sortScheduleItems(
      List<ScheduleItem>.from(profile.scheduleItems),
    ),
    currentWeek: profile.currentWeek,
    currentCalendarWeek: WeekCalculator.calendarWeekForDate(
      DateTime.now(),
      semesterStart: profile.settings.semesterStartDate,
      fallback: profile.currentWeek,
    ),
  );
}

/// 与 [TimetableProvider.isHoliday] 同口径，但使用给定数据域的假期开关。
bool _liveScopeIsHoliday(
  TimetableProvider host,
  _MyTimetableScope scope,
  DateTime date,
) {
  return HolidayResolver.isHoliday(
    date,
    data: host._holidayData,
    overrideEnabled: scope.settings.holidayOverrideEnabled,
    markingEnabled: scope.settings.enableHolidayMarking,
  );
}

String _liveResolveRealTime(
  TimetableProvider host,
  Course course,
  bool isStart, {
  required TimetableSettings settings,
}) {
  // Diagnostic fixtures intentionally carry temporary free-form clocks. They
  // must exercise the production selection path without mutating a user's
  // active time scheme.
  if (_isLiveTestingFixture(course)) {
    return isStart ? course.startTime : course.endTime;
  }
  // Live always resolves against the calendar day being evaluated so date
  // rules (e.g. summer timetable) apply for today without being baked into
  // persisted Course clocks.
  final onDate = DateTime.now();
  return LiveActivityLogic.resolveRealTime(
    course,
    isStart,
    host._resolveSectionsForCourse(course, settings: settings, onDate: onDate),
  );
}

DateTime _liveApplyTimeCorrection(
  TimetableProvider host,
  DateTime dateTime, {
  required TimetableSettings settings,
}) {
  final correctionSeconds = settings.liveTimeCorrectionSeconds;
  if (correctionSeconds == 0) {
    return dateTime;
  }
  return dateTime.add(Duration(seconds: correctionSeconds));
}

DateTime? _liveBuildCorrectedCourseDateTime(
  TimetableProvider host,
  DateTime date,
  String courseTime, {
  required TimetableSettings settings,
}) {
  final base = LiveActivityLogic.buildCourseDateTime(date, courseTime);
  if (base == null) {
    return null;
  }
  return _liveApplyTimeCorrection(host, base, settings: settings);
}

DateTime? _liveResolveBeforeClassBlockedUntil(
  TimetableProvider host,
  List<Course> todayCourses,
  int courseIndex,
  DateTime referenceDate, {
  required TimetableSettings settings,
}) {
  if (courseIndex <= 0 || courseIndex >= todayCourses.length) {
    return null;
  }

  final course = todayCourses[courseIndex];
  final courseStartTime = _liveBuildCorrectedCourseDateTime(
    host,
    referenceDate,
    _liveResolveRealTime(host, course, true, settings: settings),
    settings: settings,
  );
  if (courseStartTime == null) {
    return null;
  }

  DateTime? blockedUntil;
  for (var i = 0; i < courseIndex; i++) {
    final previousCourse = todayCourses[i];
    final previousStartTime = _liveBuildCorrectedCourseDateTime(
      host,
      referenceDate,
      _liveResolveRealTime(host, previousCourse, true, settings: settings),
      settings: settings,
    );
    final previousEndTime = _liveBuildCorrectedCourseDateTime(
      host,
      referenceDate,
      _liveResolveRealTime(host, previousCourse, false, settings: settings),
      settings: settings,
    );
    if (previousStartTime == null || previousEndTime == null) {
      continue;
    }
    if (previousStartTime.isAfter(courseStartTime)) {
      continue;
    }
    if (blockedUntil == null || previousEndTime.isAfter(blockedUntil)) {
      blockedUntil = previousEndTime;
    }
  }

  return blockedUntil;
}

List<String> _liveBuildHolidayDatesForSnapshot(
  TimetableProvider host, {
  required TimetableSettings settings,
}) {
  if (!settings.enableHolidayMarking || host._holidayData == null) {
    return const [];
  }
  // Full HolidayData.isHoliday semantics (custom makeup beats statutory hide).
  // Do not use TimetableProvider.isHoliday: holidayOverride is sent separately.
  return host._holidayData!.holidayDateKeysForSnapshot();
}

/// Makeup days that must punch through native [holidayOverrideEnabled].
List<String> _liveBuildAdjustedWorkdayDatesForSnapshot(TimetableProvider host) {
  if (host._holidayData == null) {
    return const [];
  }
  return host._holidayData!.adjustedWorkdayDateKeysForSnapshot();
}

void _liveStartActivityTick(TimetableProvider host) {
  host._liveActivityTimer?.cancel();
  unawaited(host.syncTemporalContext());
  unawaited(_liveUpdateActivity(host));
  _liveScheduleActivityTick(host);
}

Future<void> _liveHandleAppResumed(TimetableProvider host) async {
  host._liveActivityTimer?.cancel();
  await host.syncTemporalContext();
  final requestVersion = ++host._liveSurfaceRequestVersion;
  // Clear + push under one exclusive section so a concurrent apply
  // cannot interleave a half-updated native snapshot.
  await host._runLiveSurfaceExclusive(() async {
    if (requestVersion != host._liveSurfaceRequestVersion) {
      return;
    }
    host._lastLiveSnapshotSignature = null;
    host._currentLiveCourseId = null;
    await _liveUpdateActivityBody(host);
  });
  _liveScheduleActivityTick(host);
}

void _liveScheduleActivityTick(TimetableProvider host) {
  host._liveActivityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    unawaited(host.syncTemporalContext());
    _liveCheckActivityStageTransition(host);
  });
}

void _liveCheckActivityStageTransition(TimetableProvider host) {
  final selection = host.getLiveActivityCourseSelection();
  final liveCourse = selection?.currentCourse;
  if (liveCourse == null || selection == null) {
    if (host._lastLiveActivityStageKey != null ||
        host._currentLiveCourseId != null) {
      host._lastLiveActivityStageKey = null;
      host._currentLiveCourseId = null;
      unawaited(_liveUpdateActivity(host));
    }
    return;
  }

  final key = LiveActivityLogic.buildStageTransitionKey(selection);
  if (host._lastLiveActivityStageKey != null &&
      host._lastLiveActivityStageKey != key) {
    host._currentLiveCourseId = null;
    unawaited(_liveUpdateActivity(host));
  }
  host._lastLiveActivityStageKey = key;
}

void _liveSeedTrackingForTesting(
  TimetableProvider host, {
  String? lastStageKey,
  String? currentCourseId,
}) {
  host._lastLiveActivityStageKey = lastStageKey;
  host._currentLiveCourseId = currentCourseId;
}

Future<void> _liveUpdateActivityForTesting(
  TimetableProvider host, {
  bool syncScheduleSnapshot = true,
}) => _liveUpdateActivity(host, syncScheduleSnapshot: syncScheduleSnapshot);

/// Comparator that orders live candidates by their resolved (corrected) start
/// time. Preset fixture courses carry free-form clocks, so section order alone
/// is not chronological once the overlay is merged in.
int _liveCompareByResolvedStart(
  TimetableProvider host,
  DateTime referenceDate,
  Course a,
  Course b, {
  required TimetableSettings settings,
}) {
  final aStart = _liveBuildCorrectedCourseDateTime(
    host,
    referenceDate,
    _liveResolveRealTime(host, a, true, settings: settings),
    settings: settings,
  );
  final bStart = _liveBuildCorrectedCourseDateTime(
    host,
    referenceDate,
    _liveResolveRealTime(host, b, true, settings: settings),
    settings: settings,
  );
  if (aStart == null || bStart == null) {
    if (aStart == null && bStart == null) {
      return a.startSection.compareTo(b.startSection);
    }
    return aStart == null ? 1 : -1;
  }
  return aStart.compareTo(bStart);
}

LiveActivityCourseSelection? _liveGetActivityCourseSelection(
  TimetableProvider host, {
  DateTime? now,
  bool allowUpcomingFallback = false,
  int? week,
  _MyTimetableScope? scope,
}) {
  final activeScope = scope ?? _liveMyTimetableScope(host);
  if (activeScope == null) {
    return null;
  }
  final settings = activeScope.settings;
  final currentTime = now ?? DateTime.now();
  // Selection must honor holiday semantics; do not rely solely on the stop
  // branch in _liveUpdateActivityBody (tick/stage paths call selection first).
  if (_liveScopeIsHoliday(host, activeScope, currentTime)) {
    return null;
  }
  final targetWeek =
      week ??
      activeScope.calendarWeekFor(
        currentTime,
        fallbackWeek: activeScope.currentWeek,
      );
  var todayCourses = activeScope.coursesForDay(
    currentTime.weekday,
    targetWeek,
    activeOnly: true,
  );
  final fixtureCourses = host._liveTestFixtureOverlayCourses
      .where(
        (course) =>
            course.dayOfWeek == currentTime.weekday &&
            course.isActiveInWeek(targetWeek),
      )
      .toList(growable: false);
  if (fixtureCourses.isNotEmpty) {
    // 自检预设课与真实课同场竞争：按解析后的开始时间统一排序，真实课照常优先。
    todayCourses = [...todayCourses, ...fixtureCourses]
      ..sort(
        (a, b) => _liveCompareByResolvedStart(
          host,
          currentTime,
          a,
          b,
          settings: settings,
        ),
      );
  }
  if (todayCourses.isEmpty) {
    return null;
  }

  for (var i = 0; i < todayCourses.length; i++) {
    final course = todayCourses[i];
    final startTime = _liveBuildCorrectedCourseDateTime(
      host,
      currentTime,
      _liveResolveRealTime(host, course, true, settings: settings),
      settings: settings,
    );
    final endTime = _liveBuildCorrectedCourseDateTime(
      host,
      currentTime,
      _liveResolveRealTime(host, course, false, settings: settings),
      settings: settings,
    );
    if (startTime == null || endTime == null) {
      continue;
    }

    final aheadTime = startTime.subtract(
      Duration(minutes: settings.liveShowBeforeClassMinutes),
    );
    final blockedUntil = _liveResolveBeforeClassBlockedUntil(
      host,
      todayCourses,
      i,
      currentTime,
      settings: settings,
    );
    final effectiveAheadTime =
        blockedUntil != null && blockedUntil.isAfter(aheadTime)
        ? blockedUntil
        : aheadTime;
    final stage = LiveActivityLogic.resolveLiveActivityStage(
      currentTime: currentTime,
      startTime: startTime,
      endTime: endTime,
      aheadTime: effectiveAheadTime,
      settings: settings,
      endReminderWindow: TimetableProvider._liveEndReminderWindow,
    );
    if (stage != null) {
      final nextCourse = i + 1 < todayCourses.length
          ? todayCourses[i + 1]
          : null;
      return LiveActivityCourseSelection(
        currentCourse: host.resolveCourseDisplayName(
          course,
          peers: activeScope.courses,
        ),
        nextCourse: nextCourse == null
            ? null
            : host.resolveCourseDisplayName(
                nextCourse,
                peers: activeScope.courses,
              ),
        stage: stage,
      );
    }
  }

  if (!allowUpcomingFallback || !settings.liveEnableBeforeClass) {
    return null;
  }

  for (var i = 0; i < todayCourses.length; i++) {
    final course = todayCourses[i];
    final startTime = _liveBuildCorrectedCourseDateTime(
      host,
      currentTime,
      _liveResolveRealTime(host, course, true, settings: settings),
      settings: settings,
    );
    if (startTime == null || !startTime.isAfter(currentTime)) {
      continue;
    }
    final blockedUntil = _liveResolveBeforeClassBlockedUntil(
      host,
      todayCourses,
      i,
      currentTime,
      settings: settings,
    );
    if (blockedUntil != null && currentTime.isBefore(blockedUntil)) {
      continue;
    }

    final nextCourse = i + 1 < todayCourses.length ? todayCourses[i + 1] : null;
    return LiveActivityCourseSelection(
      currentCourse: host.resolveCourseDisplayName(
        course,
        peers: activeScope.courses,
      ),
      nextCourse: nextCourse == null
          ? null
          : host.resolveCourseDisplayName(
              nextCourse,
              peers: activeScope.courses,
            ),
      stage: LiveActivityStage.beforeClass,
    );
  }

  return null;
}

LiveActivityCourseSelection? _liveGetTestActivityCourseSelection(
  TimetableProvider host, {
  DateTime? now,
  _MyTimetableScope? scope,
}) {
  final activeScope = scope ?? _liveMyTimetableScope(host);
  if (activeScope == null) {
    return null;
  }
  final settings = activeScope.settings;
  final currentTime = now ?? DateTime.now();
  final targetWeek = activeScope.calendarWeekFor(
    currentTime,
    fallbackWeek: activeScope.currentWeek,
  );
  final immediateSelection = host.getLiveActivityCourseSelection(
    now: currentTime,
    allowUpcomingFallback: true,
    week: targetWeek,
  );
  if (immediateSelection != null) {
    return immediateSelection;
  }

  final today = DateTime(currentTime.year, currentTime.month, currentTime.day);
  final maxWeek = activeScope.courses.isEmpty
      ? targetWeek
      : activeScope.courses
            .map((course) => course.endWeek)
            .reduce((a, b) => a > b ? a : b);

  Course? bestCourse;
  DateTime? bestStartTime;
  int? bestWeek;

  for (final course in activeScope.courses) {
    for (var week = targetWeek; week <= maxWeek; week++) {
      if (!course.isInWeek(week)) {
        continue;
      }

      final dayOffset =
          (week - targetWeek) * 7 + course.dayOfWeek - currentTime.weekday;
      if (dayOffset < 0) {
        continue;
      }

      final candidateDate = today.add(Duration(days: dayOffset));
      final candidateStart = _liveBuildCorrectedCourseDateTime(
        host,
        candidateDate,
        _liveResolveRealTime(host, course, true, settings: settings),
        settings: settings,
      );
      if (candidateStart == null || !candidateStart.isAfter(currentTime)) {
        continue;
      }

      if (bestStartTime == null || candidateStart.isBefore(bestStartTime)) {
        bestCourse = course;
        bestStartTime = candidateStart;
        bestWeek = week;
      }
      break;
    }
  }

  final fallbackStage = LiveActivityLogic.preferredTestStage(settings);
  if (bestCourse == null || bestWeek == null || fallbackStage == null) {
    return null;
  }
  final resolvedWeek = bestWeek;

  final sameDayCourses =
      activeScope.courses
          .where(
            (course) =>
                course.dayOfWeek == bestCourse!.dayOfWeek &&
                course.isInWeek(resolvedWeek),
          )
          .toList()
        ..sort((a, b) => a.startSection.compareTo(b.startSection));
  final currentIndex = sameDayCourses.indexWhere(
    (course) => course.id == bestCourse!.id,
  );
  final nextCourse =
      currentIndex != -1 && currentIndex + 1 < sameDayCourses.length
      ? sameDayCourses[currentIndex + 1]
      : null;

  return LiveActivityCourseSelection(
    currentCourse: host.resolveCourseDisplayName(
      bestCourse,
      peers: activeScope.courses,
    ),
    nextCourse: nextCourse == null
        ? null
        : host.resolveCourseDisplayName(
            nextCourse,
            peers: activeScope.courses,
          ),
    stage: fallbackStage,
  );
}

HomeWidgetSnapshot? _liveBuildHomeWidgetSnapshot(
  TimetableProvider host,
  _MyTimetableScope scope, {
  DateTime? now,
}) {
  final profile = scope.profile;
  final settings = scope.settings;
  final currentTime = now ?? DateTime.now();
  // Must use calendar week (no semesterWeekCount clamp). Clamping to the last
  // teaching week after the term ends would revive endWeek=N courses forever.
  final targetWeek = scope.calendarWeekFor(
    currentTime,
    fallbackWeek: scope.currentWeek,
  );
  final originalTodayCount = scope
      .coursesForDay(currentTime.weekday, targetWeek, activeOnly: false)
      .length;
  final todayIsHoliday = _liveScopeIsHoliday(host, scope, currentTime);
  final todayCourses = todayIsHoliday
      ? const <Course>[]
      : scope
            .coursesForDay(currentTime.weekday, targetWeek, activeOnly: true)
            .map(
              (course) =>
                  host.resolveCourseDisplayName(course, peers: scope.courses),
            )
            .toList(growable: false);

  final tomorrow = currentTime.add(const Duration(days: 1));
  final tomorrowWeek = scope.calendarWeekFor(tomorrow);
  final tomorrowIsHoliday = _liveScopeIsHoliday(host, scope, tomorrow);
  final tomorrowCourses = tomorrowIsHoliday
      ? const <Course>[]
      : scope
            .coursesForDay(tomorrow.weekday, tomorrowWeek, activeOnly: true)
            .map(
              (course) =>
                  host.resolveCourseDisplayName(course, peers: scope.courses),
            )
            .toList(growable: false);

  final holidayEntry = host.getHolidayForDate(currentTime);
  final upcomingExams = scope.exams.where((exam) => !exam.isExpired).toList()
    ..sort(Exam.compareByStart);

  return host._homeWidgetSnapshotService.build(
    profileId: profile.id,
    profileName: profile.name,
    currentWeek: targetWeek,
    settings: settings,
    todayCourses: todayCourses,
    now: currentTime,
    countdownLeadMinutes: settings.widgetCountdownLeadMinutes,
    countdownTextStyle: settings.widgetCountdownTextStyle.value,
    nextExam: upcomingExams.isEmpty ? null : upcomingExams.first,
    isHoliday: todayIsHoliday,
    holidayName: todayIsHoliday ? holidayEntry?.name : null,
    tomorrowCourses: tomorrowCourses,
    tomorrowWeek: tomorrowWeek,
    tomorrowDayOfWeek: tomorrow.weekday,
    showTomorrowCourses: settings.widgetShowTomorrowCourses,
    originalTodayCourseCount: todayIsHoliday ? 0 : originalTodayCount,
  );
}

/// 按任意课表（含 TA 课表）构建桌面卡片快照，与上面的 active 路径平行：
/// 周次/课程/节假日开关/外观设置全部取自 [profile] 自身，而非当前课表。
/// active 路径不能直接委托这里——active 的内存态课程可能尚未 flush 回
/// profile 列表，两者的数据源语义不同。
HomeWidgetSnapshot? _liveBuildHomeWidgetSnapshotForProfile(
  TimetableProvider host,
  TimetableProfile profile, {
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final settings = profile.settings;
  // Must use calendar week (no semesterWeekCount clamp), same as active path.
  final targetWeek = WeekCalculator.calendarWeekForDate(
    currentTime,
    semesterStart: settings.semesterStartDate,
    fallback: profile.currentWeek,
  );
  List<Course> coursesForDay(
    int dayOfWeek,
    int week, {
    required bool activeOnly,
  }) {
    return profile.courses
        .where(
          (course) =>
              course.dayOfWeek == dayOfWeek &&
              (activeOnly
                  ? course.isActiveInWeek(week)
                  : course.isInWeek(week)),
        )
        .toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
  }

  final originalTodayCount = coursesForDay(
    currentTime.weekday,
    targetWeek,
    activeOnly: false,
  ).length;
  final todayIsHoliday = HolidayResolver.isHoliday(
    currentTime,
    data: host._holidayData,
    overrideEnabled: settings.holidayOverrideEnabled,
    markingEnabled: settings.enableHolidayMarking,
  );
  final todayCourses = todayIsHoliday
      ? const <Course>[]
      : coursesForDay(currentTime.weekday, targetWeek, activeOnly: true);

  final tomorrow = currentTime.add(const Duration(days: 1));
  final tomorrowWeek = WeekCalculator.calendarWeekForDate(
    tomorrow,
    semesterStart: settings.semesterStartDate,
    fallback: profile.currentWeek,
  );
  final tomorrowIsHoliday = HolidayResolver.isHoliday(
    tomorrow,
    data: host._holidayData,
    overrideEnabled: settings.holidayOverrideEnabled,
    markingEnabled: settings.enableHolidayMarking,
  );
  final tomorrowCourses = tomorrowIsHoliday
      ? const <Course>[]
      : coursesForDay(tomorrow.weekday, tomorrowWeek, activeOnly: true);

  final holidayEntry = host.getHolidayForDate(currentTime);
  final upcomingExams = profile.exams.where((exam) => !exam.isExpired).toList()
    ..sort(Exam.compareByStart);
  final nextExam = upcomingExams.isEmpty ? null : upcomingExams.first;

  return host._homeWidgetSnapshotService.build(
    profileId: profile.id,
    profileName: profile.name,
    currentWeek: targetWeek,
    settings: settings,
    todayCourses: todayCourses,
    now: currentTime,
    countdownLeadMinutes: settings.widgetCountdownLeadMinutes,
    countdownTextStyle: settings.widgetCountdownTextStyle.value,
    nextExam: nextExam,
    isHoliday: todayIsHoliday,
    holidayName: todayIsHoliday ? holidayEntry?.name : null,
    tomorrowCourses: tomorrowCourses,
    tomorrowWeek: tomorrowWeek,
    tomorrowDayOfWeek: tomorrow.weekday,
    showTomorrowCourses: settings.widgetShowTomorrowCourses,
    originalTodayCourseCount: todayIsHoliday ? 0 : originalTodayCount,
  );
}

/// 为所有绑定了非当前课表的卡片同步专属快照，返回这些卡片的刷新触发点
/// （与当前课表的触发点取并集用）。绑定课表已消失时清掉专属快照，
/// 渲染侧会回落「跟随当前课表」。
Future<Set<int>> _liveSyncBoundWidgetSnapshots(
  TimetableProvider host,
  DateTime now,
) async {
  final instances = await host._homeWidgetBindingService
      .listTodayWidgetInstances();
  final boundInstances = instances
      .where((instance) => instance.boundProfileId != null)
      .toList(growable: false);
  if (boundInstances.isEmpty) {
    return const <int>{};
  }

  final triggers = <int>{};
  for (final instance in boundInstances) {
    final appWidgetId = instance.appWidgetId;
    final profile = host._profiles
        .where((candidate) => candidate.id == instance.boundProfileId)
        .firstOrNull;
    if (profile == null) {
      await host._homeWidgetBindingService.clearWidgetSnapshot(appWidgetId);
      host._lastWidgetSnapshotSignatures.remove(appWidgetId);
      continue;
    }
    final snapshot = host.buildHomeWidgetSnapshotForProfile(profile, now: now);
    if (snapshot == null) {
      await host._homeWidgetBindingService.clearWidgetSnapshot(appWidgetId);
      host._lastWidgetSnapshotSignatures.remove(appWidgetId);
      continue;
    }
    final signature = jsonEncode(snapshot.toDedupJson());
    if (host._lastWidgetSnapshotSignatures[appWidgetId] != signature) {
      final synced = await host._homeWidgetBindingService.syncWidgetSnapshot(
        appWidgetId,
        snapshot,
      );
      if (synced) {
        host._lastWidgetSnapshotSignatures[appWidgetId] = signature;
      }
    }
    if (snapshot.state != HomeWidgetSnapshotState.holiday) {
      triggers.addAll(
        host._homeWidgetSnapshotService.buildRefreshTriggers(
          todayCourses: profile.courses
              .where(
                (course) =>
                    course.dayOfWeek == now.weekday &&
                    course.isActiveInWeek(snapshot.currentWeek),
              )
              .toList(growable: false),
          now: now,
          showCountdown: snapshot.showCountdown,
          state: snapshot.state.value,
          countdownLeadMinutes: profile.settings.widgetCountdownLeadMinutes,
        ),
      );
    }
  }
  return triggers;
}

Future<void> _liveUpdateActivity(
  TimetableProvider host, {
  bool syncScheduleSnapshot = true,
}) {
  return _liveRunLatestActivityBody(
    host,
    syncScheduleSnapshot: syncScheduleSnapshot,
  );
}

Future<void> _liveRunLatestActivityBody(
  TimetableProvider host, {
  bool syncScheduleSnapshot = true,
}) {
  final requestVersion = ++host._liveSurfaceRequestVersion;
  return host._runLiveSurfaceExclusive(() async {
    if (requestVersion != host._liveSurfaceRequestVersion) {
      return;
    }
    await _liveUpdateActivityBody(
      host,
      syncScheduleSnapshot: syncScheduleSnapshot,
    );
  });
}

Future<void> _liveUpdateActivityBody(
  TimetableProvider host, {
  bool syncScheduleSnapshot = true,
  _MyTimetableScope? scope,
}) async {
  // 自检预设课全部结束后立刻摘除覆盖层，让随后的快照同步与选课回到纯真实数据。
  host.disarmLiveTestFixtureCoursesIfFinished(DateTime.now());
  // 岛与原生课程快照一律按「我的课表」计算：当前课表切到 TA 时不能跟着走。
  final activeScope = scope ?? _liveMyTimetableScope(host);
  await _liveSyncHomeWidgetSnapshot(host, scope: activeScope);
  if (!host._enableLiveActivitySync) {
    return;
  }

  final suspendedUntil = host._liveActivitySuspendedUntil;
  if (suspendedUntil != null) {
    if (DateTime.now().isBefore(suspendedUntil)) {
      return;
    }
    host._liveActivitySuspendedUntil = null;
  }

  if (syncScheduleSnapshot) {
    await _liveSyncScheduleSnapshot(host, scope: activeScope);
  }

  if (activeScope == null ||
      _liveScopeIsHoliday(host, activeScope, DateTime.now())) {
    host._currentLiveCourseId = null;
    host._lastLiveActivityStageKey = null;
    await host._liveActivitiesService.stopLiveUpdate();
    return;
  }

  final selection = _liveGetActivityCourseSelection(host, scope: activeScope);
  final liveCourse = selection?.currentCourse;

  if (liveCourse != null) {
    final activeSelection = selection!;
    final settings = activeScope.settings;
    final displaySettings =
        activeSelection.stage == LiveActivityStage.beforeClass
        ? settings.beforeClassDisplaySettings
        : settings.duringEndDisplaySettings;
    final nextCourse = activeSelection.nextCourse;
    final nextCourseKey = nextCourse != null
        ? '${nextCourse.id}:${nextCourse.name}:${nextCourse.startSection}'
        : 'null';
    final liveActivityKey =
        '${liveCourse.id}:${activeSelection.stage.name}:${liveCourse.name}:${liveCourse.startSection}:${liveCourse.endSection}:${liveCourse.location}:${liveCourse.teacher}:$nextCourseKey:${settings.hashCode}';
    if (host._currentLiveCourseId == liveActivityKey) {
      return;
    }

    final displayCourse = liveCourse.copyWith(
      startTime: _liveResolveRealTime(
        host,
        liveCourse,
        true,
        settings: settings,
      ),
      endTime: _liveResolveRealTime(
        host,
        liveCourse,
        false,
        settings: settings,
      ),
    );
    final displayNextCourse = activeSelection.nextCourse?.copyWith(
      startTime: _liveResolveRealTime(
        host,
        activeSelection.nextCourse!,
        true,
        settings: settings,
      ),
      endTime: _liveResolveRealTime(
        host,
        activeSelection.nextCourse!,
        false,
        settings: settings,
      ),
    );
    final startAtMillis = _liveBuildCorrectedCourseDateTime(
      host,
      DateTime.now(),
      _liveResolveRealTime(host, displayCourse, true, settings: settings),
      settings: settings,
    )?.millisecondsSinceEpoch;
    final endAtMillis = _liveBuildCorrectedCourseDateTime(
      host,
      DateTime.now(),
      _liveResolveRealTime(host, displayCourse, false, settings: settings),
      settings: settings,
    )?.millisecondsSinceEpoch;
    final sections = host._resolveSectionsForCourse(
      displayCourse,
      settings: settings,
      onDate: DateTime.now(),
    );
    final progressMilestones = LiveActivityLogic.buildLiveProgressMilestones(
      displayCourse,
      sections,
      startAtMillis: startAtMillis,
      endAtMillis: endAtMillis,
    );
    final progressBreakOffsetsMillis =
        LiveActivityLogic.buildLiveProgressBreakOffsetsMillis(
          displayCourse,
          sections,
          startAtMillis: startAtMillis,
          endAtMillis: endAtMillis,
        );

    await host._liveActivitiesService.startLiveUpdate(
      displayCourse,
      displayNextCourse,
      stage: selection.stage.name,
      validateAgainstSchedule: true,
      beforeClassLeadMillis: settings.liveShowBeforeClassMinutes * 60000,
      startAtMillis: startAtMillis,
      endAtMillis: endAtMillis,
      liveClassReminderStartMinutes: settings.liveClassReminderStartMinutes,
      endSecondsCountdownThreshold: settings.liveEndSecondsCountdownThreshold,
      promoteDuringClass:
          activeSelection.stage == LiveActivityStage.duringClassStatusBar
          ? false
          : settings.livePromoteDuringClass,
      showNotificationDuringClass:
          activeSelection.stage == LiveActivityStage.duringClassStatusBar
          ? true
          : settings.liveShowDuringClassNotification,
      enableBeforeClass: settings.liveEnableBeforeClass,
      enableDuringClass: settings.liveEnableDuringClass,
      enableBeforeEnd: settings.liveEnableBeforeEnd,
      showCountdown: displaySettings.showCountdown,
      countdownTextStyle: displaySettings.countdownTextStyle,
      showStageText: displaySettings.showStageText,
      showCourseNameInIsland: displaySettings.showCourseName,
      showLocationInIsland: displaySettings.showLocation,
      useShortNameInIsland: displaySettings.useShortName,
      hidePrefixText: displaySettings.hidePrefixText,
      duringClassTimeDisplayMode: displaySettings.duringClassTimeDisplayMode,
      enableMiuiIslandLabelImage: displaySettings.enableMiuiIslandLabelImage,
      miuiIslandLabelStyle: displaySettings.miuiIslandLabelStyle,
      miuiIslandLabelContent: displaySettings.miuiIslandLabelContent,
      miuiIslandLabelFontColor: displaySettings.miuiIslandLabelFontColor,
      miuiIslandLabelFontWeight: displaySettings.miuiIslandLabelFontWeight,
      miuiIslandLabelRenderQuality:
          displaySettings.miuiIslandLabelRenderQuality,
      miuiIslandLabelFontSize: displaySettings.miuiIslandLabelFontSize,
      miuiIslandLabelOffsetX: displaySettings.miuiIslandLabelOffsetX,
      miuiIslandLabelOffsetY: displaySettings.miuiIslandLabelOffsetY,
      miuiIslandLabelLogoPath: displaySettings.miuiIslandLabelLogoPath,
      miuiIslandLabelLogoCornerRadius:
          displaySettings.miuiIslandLabelLogoCornerRadius,
      miuiIslandExpandedIconMode: displaySettings.miuiIslandExpandedIconMode,
      miuiIslandExpandedIconPath: displaySettings.miuiIslandExpandedIconPath,
      beforeClassQuickAction: settings.liveBeforeClassQuickAction,
      beforeClassQuickActionAutoMinutes:
          settings.liveBeforeClassQuickActionAutoMinutes,
      progressBreakOffsetsMillis: progressBreakOffsetsMillis,
      progressMilestoneLabels: progressMilestones
          .map((milestone) => milestone['label'] as String)
          .toList(),
      progressMilestoneTimeTexts: progressMilestones
          .map((milestone) => milestone['timeText'] as String)
          .toList(),
    );
    host._currentLiveCourseId = liveActivityKey;
  } else {
    host._currentLiveCourseId = null;
    host._lastLiveActivityStageKey = null;
    await host._liveActivitiesService.stopLiveUpdate();
  }
}

Future<void> _liveSyncScheduleSnapshot(
  TimetableProvider host, {
  _MyTimetableScope? scope,
}) async {
  final activeScope = scope ?? _liveMyTimetableScope(host);
  final overlayCourses = host._liveTestFixtureOverlayCourses;
  if (activeScope == null ||
      (activeScope.courses.isEmpty && overlayCourses.isEmpty)) {
    if (host._lastLiveSnapshotSignature != null) {
      final cleared = await host._liveActivitiesService.clearScheduleSnapshot();
      if (cleared) {
        host._lastLiveSnapshotSignature = null;
      }
    }
    return;
  }

  final settings = activeScope.settings;
  // 自检预设课随覆盖层一并进入原生快照：原生侧的校验与续排都以此为准。
  final displayCourses = [
    ...activeScope.courses,
    ...overlayCourses,
  ].map((course) => host.resolveCourseDisplayName(course, peers: activeScope.courses)).toList(growable: false);
  final now = DateTime.now();
  // Use calendar week (not UI browse week) so native schedule matches live
  // course selection even when the user has scrolled the timetable.
  final scheduleWeek = activeScope.calendarWeekFor(now);
  final todayKey =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final todayIsHoliday = _liveScopeIsHoliday(host, activeScope, now);
  final holidayDates = _liveBuildHolidayDatesForSnapshot(
    host,
    settings: settings,
  );
  final adjustedWorkdayDates = _liveBuildAdjustedWorkdayDatesForSnapshot(host);
  final snapshotSignature = jsonEncode({
    'profileId': activeScope.profile.id,
    'currentWeek': scheduleWeek,
    'semesterStartDate':
        settings.semesterStartDate?.millisecondsSinceEpoch,
    'isHoliday': todayIsHoliday,
    'isHolidayDate': todayKey,
    'holidayDates': holidayDates,
    'adjustedWorkdayDates': adjustedWorkdayDates,
    'holidayOverrideEnabled': settings.holidayOverrideEnabled,
    'enableHolidayMarking': settings.enableHolidayMarking,
    'settings': settings.toJson(),
    'courses': displayCourses.map((course) => course.toJson()).toList(),
  });
  if (host._lastLiveSnapshotSignature == snapshotSignature) {
    return;
  }

  final synced = await host._liveActivitiesService.syncScheduleSnapshot(
    courses: displayCourses,
    settings: settings,
    currentWeek: scheduleWeek,
    semesterStartDate: settings.semesterStartDate,
    endReminderLeadMillis:
        TimetableProvider._liveEndReminderWindow.inMilliseconds,
    isHoliday: todayIsHoliday,
    isHolidayDate: todayKey,
    holidayDates: holidayDates,
    adjustedWorkdayDates: adjustedWorkdayDates,
    holidayOverrideEnabled: settings.holidayOverrideEnabled,
    enableHolidayMarking: settings.enableHolidayMarking,
  );
  if (synced) {
    host._lastLiveSnapshotSignature = snapshotSignature;
  }
}

Future<void> _liveSyncHomeWidgetSnapshot(
  TimetableProvider host, {
  _MyTimetableScope? scope,
}) async {
  // 统计小组件与今日小组件共用这一入口：冷启动、回前台、课表变更都会走到，
  // 否则用户不进统计页时桌面统计组件永远读不到快照。
  // 今日/统计小组件与超级岛同域（「我的课表」）：绑定指定课表的卡片另有
  // [_liveSyncBoundWidgetSnapshots] 单独处理，不受这里影响。
  final activeScope = scope ?? _liveMyTimetableScope(host);
  await _liveSyncStatsWidgetSnapshot(host, scope: activeScope);
  await _liveSyncCoupleWidgetSnapshot(host);
  if (activeScope == null) {
    if (host._lastHomeWidgetSnapshotSignature != null) {
      final cleared = await host._homeWidgetService.clearSnapshot();
      if (cleared) {
        host._lastHomeWidgetSnapshotSignature = null;
      }
    }
    return;
  }
  final now = DateTime.now();
  final snapshot = _liveBuildHomeWidgetSnapshot(host, activeScope, now: now);
  if (snapshot == null) {
    if (host._lastHomeWidgetSnapshotSignature != null) {
      final cleared = await host._homeWidgetService.clearSnapshot();
      if (cleared) {
        host._lastHomeWidgetSnapshotSignature = null;
      }
    }
    return;
  }

  final snapshotSignature = jsonEncode(snapshot.toDedupJson());
  if (host._lastHomeWidgetSnapshotSignature != snapshotSignature) {
    final synced = await host._homeWidgetService.syncSnapshot(snapshot);
    if (synced) {
      host._lastHomeWidgetSnapshotSignature = snapshotSignature;
    }
  }
  final triggerAtMillis = snapshot.state == HomeWidgetSnapshotState.holiday
      ? <int>[]
      : host._homeWidgetSnapshotService.buildRefreshTriggers(
          todayCourses: activeScope.coursesForDay(
            now.weekday,
            snapshot.currentWeek,
            activeOnly: true,
          ),
          now: now,
          showCountdown: snapshot.showCountdown,
          state: snapshot.state.value,
          countdownLeadMinutes:
              activeScope.settings.widgetCountdownLeadMinutes,
        );
  // 绑定卡片：各自课表的专属快照 + 刷新触发点并入并集，
  // 否则 TA 第三节课开始时闹钟仍按当前课表的时间没响。
  final boundTriggers = await _liveSyncBoundWidgetSnapshots(host, now);
  await host._homeWidgetService.scheduleRefresh([
    ...triggerAtMillis,
    ...boundTriggers,
  ]);
}

Future<CoupleTimetableWidgetSnapshot> _liveBuildCoupleWidgetSnapshot(
  TimetableProvider host,
) async {
  if (!host.settings.coupleTimetableOverlayEnabled) {
    return CoupleTimetableWidgetSnapshot.unavailable(
      CoupleTimetableWidgetStatus.coupleModeOff,
    );
  }

  WithuCoupleSession? session;
  try {
    session = await host._withuSessionStore.load();
  } catch (_) {
    return CoupleTimetableWidgetSnapshot.unavailable(
      CoupleTimetableWidgetStatus.notLoggedIn,
    );
  }
  final binding = host.partnerBinding;
  final partnerProfile = host.partnerProfile;
  final myProfile = host.myTimetableProfile;
  final displayProfile = await host._withuSessionStore.loadDisplayProfile();
  if (session == null || !session.isUsable) {
    return CoupleTimetableWidgetSnapshot.unavailable(
      CoupleTimetableWidgetStatus.notLoggedIn,
    );
  }
  if (binding == null || partnerProfile == null || myProfile == null) {
    return CoupleTimetableWidgetSnapshot.unavailable(
      CoupleTimetableWidgetStatus.coupleModeOff,
    );
  }

  final myName = displayProfile?.userNickname.trim().isNotEmpty == true
      ? displayProfile!.userNickname.trim()
      : (session.username.trim().isNotEmpty
            ? session.username.trim()
            : myProfile.name.trim());
  final partnerName = displayProfile?.partnerNickname.trim().isNotEmpty == true
      ? displayProfile!.partnerNickname.trim()
      : (binding.partnerName.trim().isNotEmpty
            ? binding.partnerName.trim()
            : partnerProfile.name.trim());
  if (myName.isEmpty || partnerName.isEmpty) {
    return CoupleTimetableWidgetSnapshot.unavailable(
      CoupleTimetableWidgetStatus.coupleModeOff,
    );
  }

  final now = DateTime.now();
  final tomorrow = now.add(const Duration(days: 1));
  // 「我的课表」周次按我自己的开学时间对齐：当前课表切到 TA 后，不能拿
  // TA 的学期起点来算我的周次（双方卡片左栏仍须是我的课）。
  int myCalendarWeekFor(DateTime date) => WeekCalculator.calendarWeekForDate(
    date,
    semesterStart: myProfile.settings.semesterStartDate,
    fallback: host.currentCalendarWeek,
  );
  List<Course> myCoursesFor(DateTime date) =>
      myProfile.courses
          .where(
            (course) =>
                course.dayOfWeek == date.weekday &&
                course.isActiveInWeek(myCalendarWeekFor(date)),
          )
          .toList()
        ..sort((a, b) => a.startSection.compareTo(b.startSection));
  return CoupleTimetableWidgetSnapshot(
    myName: myName,
    partnerName: partnerName,
    leftColorHex: binding.mineColorHex,
    rightColorHex: binding.partnerColorHex,
    status: CoupleTimetableWidgetStatus.ok,
    generatedAtMillis: now.millisecondsSinceEpoch,
    mine: CoupleTimetableWidgetDayCourses(
      today: _liveBuildCoupleCoursesForDate(
        host,
        myCoursesFor(now),
        now,
        settings: myProfile.settings,
      ),
      tomorrow: _liveBuildCoupleCoursesForDate(
        host,
        myCoursesFor(tomorrow),
        tomorrow,
        settings: myProfile.settings,
      ),
    ),
    partner: CoupleTimetableWidgetDayCourses(
      today: _liveBuildCouplePartnerCoursesForDate(host, partnerProfile, now),
      tomorrow: _liveBuildCouplePartnerCoursesForDate(
        host,
        partnerProfile,
        tomorrow,
      ),
    ),
  );
}

List<CoupleTimetableWidgetCourse> _liveBuildCouplePartnerCoursesForDate(
  TimetableProvider host,
  TimetableProfile partnerProfile,
  DateTime date,
) {
  final calendarWeek = host._calculateCalendarWeekForDate(date);
  final partnerWeek = host.partnerWeekFor(calendarWeek);
  final courses =
      partnerProfile.courses
          .where(
            (course) =>
                course.dayOfWeek == date.weekday &&
                course.isActiveInWeek(partnerWeek),
          )
          .toList()
        ..sort((a, b) => a.startSection.compareTo(b.startSection));
  return _liveBuildCoupleCoursesForDate(
    host,
    courses,
    date,
    settings: partnerProfile.settings,
  );
}

List<CoupleTimetableWidgetCourse> _liveBuildCoupleCoursesForDate(
  TimetableProvider host,
  List<Course> courses,
  DateTime date, {
  required TimetableSettings settings,
}) {
  final result = <CoupleTimetableWidgetCourse>[];
  for (final source in courses) {
    final course = host.resolveCourseDisplayName(source);
    final sections = host._resolveSectionsForCourse(
      source,
      settings: settings,
      onDate: date,
    );
    final startTime = LiveActivityLogic.resolveRealTime(source, true, sections);
    final endTime = LiveActivityLogic.resolveRealTime(source, false, sections);
    if (startTime.isEmpty || endTime.isEmpty) {
      continue;
    }

    final breaks = <CoupleTimetableWidgetBreak>[];
    final firstSectionIndex = source.startSection - 1;
    final lastSectionIndex = source.endSection - 1;
    if (sections != null &&
        firstSectionIndex >= 0 &&
        lastSectionIndex > firstSectionIndex &&
        lastSectionIndex < sections.length) {
      for (var index = firstSectionIndex; index < lastSectionIndex; index++) {
        final breakStart = sections[index].endTime;
        final breakEnd = sections[index + 1].startTime;
        if (breakStart.isNotEmpty && breakEnd.isNotEmpty) {
          breaks.add(
            CoupleTimetableWidgetBreak(
              startTime: breakStart,
              endTime: breakEnd,
            ),
          );
        }
      }
    }

    result.add(
      CoupleTimetableWidgetCourse(
        id: course.id,
        name: course.name,
        shortName: course.shortName,
        location: course.location,
        color: course.color,
        startSection: course.startSection,
        endSection: course.endSection,
        startTime: startTime,
        endTime: endTime,
        breaks: breaks,
      ),
    );
  }
  return result;
}

Future<void> _liveSyncCoupleWidgetSnapshot(TimetableProvider host) async {
  final snapshot = await _liveBuildCoupleWidgetSnapshot(host);
  await CoupleTimetableWidgetService.syncSnapshot(snapshot);
}

Future<void> _liveSyncStatsWidgetSnapshot(
  TimetableProvider host, {
  _MyTimetableScope? scope,
}) async {
  final activeScope = scope ?? _liveMyTimetableScope(host);
  final snapshot = activeScope == null
      ? null
      : StatsWidgetSnapshot.fromCourses(
          courses: activeScope.courses,
          currentWeek: activeScope.currentWeek,
          semesterWeekCount: activeScope.settings.semesterWeekCount,
          profileName: activeScope.profile.name,
        );
  if (snapshot == null) {
    await StatsWidgetService.clearSnapshot();
    return;
  }
  await StatsWidgetService.syncSnapshot(snapshot);
}

Future<void> _liveRefreshNow(
  TimetableProvider host, {
  bool forceSnapshotSync = false,
}) async {
  await host.initialize();
  if (forceSnapshotSync) {
    host._lastLiveSnapshotSignature = null;
  }
  host._currentLiveCourseId = null;
  await _liveSyncScheduleSnapshot(host);
  await _liveUpdateActivity(host, syncScheduleSnapshot: false);
}
