import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../models/course.dart';
import '../models/timetable_settings.dart';
import '../domain/couple_timetable_logic.dart';
import '../providers/timetable_provider.dart';
import '../ui/hyperos/hyperos_motion.dart';
import '../utils/hex_color.dart';
import '../ui/hyperos/hyperos.dart';
import 'class_reminder_sheet.dart';
import 'course_followup_sheets.dart';
import 'course_note_sheet.dart';
import 'course_action_sheet_reveal.dart';

typedef CourseActionHandler = void Function(Course course);
typedef CourseAlarmHandler = Future<void> Function(Course course);

class CourseActionSheetResult {
  const CourseActionSheetResult.reschedule(this.course, this.rescheduleDraft)
    : deleteMode = null,
      suspendMode = null;

  const CourseActionSheetResult.delete(this.course, this.deleteMode)
    : rescheduleDraft = null,
      suspendMode = null;

  const CourseActionSheetResult.suspend(this.course, this.suspendMode)
    : rescheduleDraft = null,
      deleteMode = null;

  final Course course;
  final CourseRescheduleDraft? rescheduleDraft;
  final CourseDeleteMode? deleteMode;
  final CourseSuspendMode? suspendMode;
}

class CourseActionPreviewItem {
  const CourseActionPreviewItem({
    required this.course,
    this.isPartnerCourse = false,
    this.coupleKind,
    this.isConflict = false,
  });

  final Course course;
  final bool isPartnerCourse;
  final CoupleCourseKind? coupleKind;
  final bool isConflict;

  bool get isReadOnly => isPartnerCourse;

  bool get isCoupleRelated =>
      coupleKind == CoupleCourseKind.together ||
      coupleKind == CoupleCourseKind.partner;
}

/// Shows the home timetable course action sheet with Forui styling.
Future<CourseActionSheetResult?> showCourseActionSheet(
  BuildContext context, {
  required List<CourseActionPreviewItem> previewItems,
  required int week,
  required CourseActionHandler onEdit,
  CourseAlarmHandler? onSetAlarm,
}) {
  return showHomeHyperosSheet<CourseActionSheetResult>(
    context: context,
    builder: (sheetContext) => CourseActionSheetBody(
      previewItems: previewItems,
      week: week,
      onEdit: onEdit,
      onSetAlarm: onSetAlarm,
    ),
  );
}

class CourseActionSheetBody extends StatefulWidget {
  const CourseActionSheetBody({
    super.key,
    required this.previewItems,
    required this.week,
    required this.onEdit,
    this.onSetAlarm,
  });

  final List<CourseActionPreviewItem> previewItems;
  final int week;
  final CourseActionHandler onEdit;
  final CourseAlarmHandler? onSetAlarm;

  @override
  State<CourseActionSheetBody> createState() => _CourseActionSheetBodyState();
}

class _CourseActionSheetBodyState extends State<CourseActionSheetBody> {
  final _scrollController = ScrollController();
  _CourseActionSheetView _view = _CourseActionSheetView.main;
  int _selectedIndex = 0;
  bool _relatedExpanded = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectCourse(int index) {
    if (index == _selectedIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
      _relatedExpanded = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _switchView(_CourseActionSheetView view) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() => _view = view);
  }

  void _completeWith(CourseActionSheetResult result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return AnimatedSize(
      duration: HyperosMotionScope.of(context).scaledDuration(280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: HyperosSheetFrame(
        maxHeight: maxHeight,
        child: AnimatedSwitcher(
          duration: HyperosMotionScope.of(context).scaledDuration(280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.55, curve: Curves.easeOut),
              reverseCurve: const Interval(0.45, 1, curve: Curves.easeIn),
            ),
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey('course-action-view-${_view.name}'),
            child: _buildView(),
          ),
        ),
      ),
    );
  }

  Widget _buildView() {
    final selectedItem = widget.previewItems[_selectedIndex];
    final provider = context.watch<TimetableProvider>();
    switch (_view) {
      case _CourseActionSheetView.main:
        final otherIndexes = <int>[
          for (var index = 0; index < widget.previewItems.length; index++)
            if (index != _selectedIndex) index,
        ];
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CourseActionSheetContent(
                  key: ValueKey(
                    'course-action-selected-${selectedItem.course.id}',
                  ),
                  previewItem: selectedItem,
                  week: widget.week,
                  onEdit: widget.onEdit,
                  onOpenView: _switchView,
                  onSetAlarm: widget.onSetAlarm,
                ),
                if (otherIndexes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _RelatedCoursesPanel(
                    previewItems: widget.previewItems,
                    otherIndexes: otherIndexes,
                    week: widget.week,
                    expanded: _relatedExpanded,
                    onToggleExpanded: () {
                      setState(() => _relatedExpanded = !_relatedExpanded);
                    },
                    onSelect: _selectCourse,
                  ),
                ],
              ],
            ),
          ),
        );
      case _CourseActionSheetView.alarm:
        return ClassReminderSheetBody(
          course: selectedItem.course,
          week: widget.week,
          embedded: true,
          onBack: () => _switchView(_CourseActionSheetView.main),
        );
      case _CourseActionSheetView.task:
        final existingTask = provider
            .getTasksForCourse(selectedItem.course.id)
            .where(
              (task) =>
                  task.sourceWeek == null || task.sourceWeek == widget.week,
            )
            .firstOrNull;
        return CourseTaskSheetBody(
          course: selectedItem.course,
          week: widget.week,
          task: existingTask,
          embedded: true,
          onCancel: () => _switchView(_CourseActionSheetView.main),
          onCompleted: () => _switchView(_CourseActionSheetView.main),
        );
      case _CourseActionSheetView.note:
        return CourseNoteSheetBody(
          course: selectedItem.course,
          week: widget.week,
          readOnly: selectedItem.isReadOnly,
          embedded: true,
          onCancel: () => _switchView(_CourseActionSheetView.main),
          onSaved: () => _switchView(_CourseActionSheetView.main),
        );
      case _CourseActionSheetView.reschedule:
        final l10n = AppLocalizations.of(context)!;
        return CourseRescheduleSheetBody(
          course: selectedItem.course,
          sourceWeek: widget.week,
          settings: provider.settings,
          weekDays: [
            l10n.weekdayMon,
            l10n.weekdayTue,
            l10n.weekdayWed,
            l10n.weekdayThu,
            l10n.weekdayFri,
            l10n.weekdaySat,
            l10n.weekdaySun,
          ],
          sectionTimes:
              provider.resolveCourseTimeScheme(selectedItem.course)?.sections ??
              provider.settings.sections,
          locationSuggestions: provider.uniqueLocations,
          embedded: true,
          onCancel: () => _switchView(_CourseActionSheetView.main),
          onConfirmed: (draft) => _completeWith(
            CourseActionSheetResult.reschedule(selectedItem.course, draft),
          ),
        );
      case _CourseActionSheetView.delete:
        return CourseDeleteModeSheetBody(
          canDeleteOccurrence: selectedItem.course.isInWeek(widget.week),
          week: widget.week,
          embedded: true,
          onResult: (mode) {
            if (mode == null) {
              _switchView(_CourseActionSheetView.main);
              return;
            }
            _completeWith(
              CourseActionSheetResult.delete(selectedItem.course, mode),
            );
          },
        );
      case _CourseActionSheetView.suspend:
        return CourseSuspendModeSheetBody(
          isSuspendedThisWeek: selectedItem.course.isSuspendedInWeek(
            widget.week,
          ),
          hasAnySuspended:
              selectedItem.course.suspendedWeeks?.isNotEmpty ?? false,
          embedded: true,
          onResult: (mode) {
            if (mode == null) {
              _switchView(_CourseActionSheetView.main);
              return;
            }
            _completeWith(
              CourseActionSheetResult.suspend(selectedItem.course, mode),
            );
          },
        );
    }
  }
}

enum _CourseActionSheetView {
  main,
  alarm,
  task,
  note,
  reschedule,
  delete,
  suspend,
}

class _RelatedCoursesPanel extends StatelessWidget {
  const _RelatedCoursesPanel({
    required this.previewItems,
    required this.otherIndexes,
    required this.week,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onSelect,
  });

  final List<CourseActionPreviewItem> previewItems;
  final List<int> otherIndexes;
  final int week;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;
    final muted = typo.xs2.copyWith(color: colors.mutedForeground);
    final conflictCount = otherIndexes
        .where((index) => previewItems[index].isConflict)
        .length;
    final coupleCount = otherIndexes.length - conflictCount;
    final accent = coupleCount > 0 && conflictCount == 0
        ? parseHexColorOrFallback(
            context.read<TimetableProvider>().coupleColorForKind(
              CoupleCourseKind.together,
            ),
            fallback: colors.primary,
          )
        : colors.destructive;
    final panelIcon = coupleCount > 0 && conflictCount == 0
        ? Icons.favorite_rounded
        : Icons.warning_amber_rounded;
    final previewNames = otherIndexes
        .map((index) => previewItems[index].course.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final previewLine = _conflictPreviewLine(previewNames);
    final title = _relatedPanelTitle(
      l10n,
      conflictCount: conflictCount,
      coupleCount: coupleCount,
      totalCount: otherIndexes.length,
    );
    final subtitle = expanded
        ? (coupleCount > 0 && conflictCount == 0
              ? l10n.courseActionCoupleCollapseHint
              : l10n.courseActionConflictCollapseHint)
        : (previewLine ??
              (coupleCount > 0 && conflictCount == 0
                  ? l10n.courseActionCoupleExpandHint
                  : l10n.courseActionConflictExpandHint));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CourseDetailReveal(
          child: HyperosFrostedSurface(
            borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggleExpanded,
                borderRadius: BorderRadius.circular(
                  HyperosTokens.controlRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        width: HyperosTokens.iconBadgeSize,
                        height: HyperosTokens.iconBadgeSize,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            HyperosTokens.iconBadgeRadius,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(panelIcon, size: 17, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: typo.sm.copyWith(height: 1.25),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: muted.copyWith(height: 1.3),
                              maxLines: expanded ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: colors.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          for (
            var itemIndex = 0;
            itemIndex < otherIndexes.length;
            itemIndex++
          ) ...[
            if (itemIndex > 0) const SizedBox(height: 8),
            CourseDetailReveal(
              index: itemIndex + 1,
              child: _RelatedCourseCompactRow(
                previewItem: previewItems[otherIndexes[itemIndex]],
                week: week,
                onTap: () => onSelect(otherIndexes[itemIndex]),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

String _relatedPanelTitle(
  AppLocalizations l10n, {
  required int conflictCount,
  required int coupleCount,
  required int totalCount,
}) {
  if (coupleCount > 0 && conflictCount == 0) {
    return l10n.courseActionCoupleRelatedCount(coupleCount);
  }
  if (conflictCount > 0 && coupleCount == 0) {
    return l10n.conflictCountLabel(conflictCount);
  }
  return l10n.courseActionMixedRelatedCount(totalCount);
}

String? _conflictPreviewLine(List<String> names) {
  if (names.isEmpty) {
    return null;
  }
  if (names.length == 1) {
    return names.first;
  }
  if (names.length == 2) {
    return '${names[0]} · ${names[1]}';
  }
  return '${names[0]} · ${names[1]}…';
}

class _RelatedCourseCompactRow extends StatelessWidget {
  const _RelatedCourseCompactRow({
    required this.previewItem,
    required this.week,
    required this.onTap,
  });

  final CourseActionPreviewItem previewItem;
  final int week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;
    final course = previewItem.course;
    final courseColor = _previewItemColor(context, previewItem, colors);
    final scheduleLine =
        '${_weekdayLabel(l10n, course.dayOfWeek)} · ${l10n.sectionRangeLabel(course.startSection, course.endSection)} · ${course.startTime}-${course.endTime}';
    final muted = typo.xs2.copyWith(color: colors.mutedForeground);
    final badgeLabel = _previewItemBadgeLabel(l10n, previewItem);

    return HyperosFrostedSurface(
      borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: courseColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              course.name,
                              style: typo.sm.copyWith(height: 1.25),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (badgeLabel != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              badgeLabel,
                              style: typo.xs2.copyWith(color: courseColor),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scheduleLine,
                        style: muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (course.location.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          course.location.trim(),
                          style: muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.courseActionConflictSwitchAction,
                  style: typo.xs2.copyWith(color: colors.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _previewItemColor(
  BuildContext context,
  CourseActionPreviewItem item,
  FColors colors,
) {
  if (item.coupleKind != null) {
    return parseHexColorOrFallback(
      context.read<TimetableProvider>().coupleColorForKind(item.coupleKind!),
      fallback: colors.primary,
    );
  }
  if (item.isConflict) {
    return colors.destructive;
  }
  return parseHexColorOrFallback(item.course.color, fallback: colors.primary);
}

String? _previewItemBadgeLabel(
  AppLocalizations l10n,
  CourseActionPreviewItem item,
) {
  if (item.isConflict) {
    return l10n.conflictLabel;
  }
  return switch (item.coupleKind) {
    CoupleCourseKind.together => l10n.coupleTimetableLegendTogether,
    CoupleCourseKind.partner => l10n.coupleTimetableLegendPartner,
    CoupleCourseKind.mine => l10n.coupleTimetableLegendMine,
    null => null,
  };
}

class _CourseActionSheetContent extends StatelessWidget {
  const _CourseActionSheetContent({
    super.key,
    required this.previewItem,
    required this.week,
    required this.onEdit,
    required this.onOpenView,
    this.onSetAlarm,
  });

  final CourseActionPreviewItem previewItem;
  final int week;
  final CourseActionHandler onEdit;
  final ValueChanged<_CourseActionSheetView> onOpenView;
  final CourseAlarmHandler? onSetAlarm;

  Course get course => previewItem.course;

  void _closeSheetThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;
    final provider = context.watch<TimetableProvider>();
    var course = previewItem.course;
    for (final item in provider.courses) {
      if (item.id == previewItem.course.id) {
        course = item;
        break;
      }
    }
    final courseColor = _previewItemColor(
      context,
      CourseActionPreviewItem(
        course: course,
        isPartnerCourse: previewItem.isPartnerCourse,
        coupleKind: previewItem.coupleKind,
        isConflict: previewItem.isConflict,
      ),
      colors,
    );
    final coupleBadge = _previewItemBadgeLabel(l10n, previewItem);
    final natureLabel = course.courseNature == CourseNature.elective
        ? l10n.courseNatureElective
        : l10n.courseNatureRequired;
    final teacher = course.teacher.trim();
    final location = course.location.trim();
    final headerDetail = course.weekDescription(l10n);
    final headerWeekDetail = '${l10n.weekLabel(week)} · $headerDetail';
    final sectionTitle =
        '${_weekdayLabel(l10n, course.dayOfWeek)} · ${l10n.sectionRangeLabel(course.startSection, course.endSection)}';
    final timeSubtitle = _formatTimeTileSubtitle(
      context,
      course: course,
      week: week,
      settings: provider.settings,
    );
    final shortName = course.shortName?.trim();
    final shortNameSubtitle = shortName?.isNotEmpty == true
        ? l10n.shortNamePrefix(shortName!)
        : null;
    final canReschedule = !previewItem.isReadOnly && course.isInWeek(week);
    final isSuspended = course.isSuspendedInWeek(week);
    final headerIcon = previewItem.coupleKind == CoupleCourseKind.together
        ? Icons.favorite_rounded
        : previewItem.isPartnerCourse
        ? Icons.person_outline_rounded
        : Icons.menu_book_rounded;
    final canEdit = !previewItem.isReadOnly;
    final showAlarm =
        canEdit &&
        onSetAlarm != null &&
        _isAlarmAvailable(
          settings: provider.settings,
          week: week,
          course: course,
          provider: provider,
        );
    final headerActions = <_CourseHeaderAction>[
      if (canEdit)
        _CourseHeaderAction(
          icon: Icons.edit_outlined,
          label: l10n.courseHeaderEditAction,
          tooltip: l10n.courseActionEditPrimary,
          onPressed: () => _closeSheetThen(context, () => onEdit(course)),
        ),
    ];
    final bottomActions = <_CourseHeaderAction>[
      if (showAlarm)
        _CourseHeaderAction(
          icon: Icons.alarm_outlined,
          label: l10n.courseHeaderAlarmAction,
          onPressed: () => onOpenView(_CourseActionSheetView.alarm),
        ),
      if (canEdit)
        _CourseHeaderAction(
          icon: Icons.assignment_outlined,
          label: l10n.courseHeaderTaskAction,
          onPressed: () => onOpenView(_CourseActionSheetView.task),
        ),
      _CourseHeaderAction(
        icon: Icons.sticky_note_2_outlined,
        label: l10n.courseHeaderNoteAction,
        onPressed: () => onOpenView(_CourseActionSheetView.note),
      ),
      _CourseHeaderAction(
        icon: Icons.event_repeat_outlined,
        label: l10n.courseActionRescheduleSecondary,
        onPressed: canReschedule
            ? () => onOpenView(_CourseActionSheetView.reschedule)
            : null,
      ),
      _CourseHeaderAction(
        icon: isSuspended
            ? Icons.play_circle_outline_rounded
            : Icons.pause_circle_outline_rounded,
        label: isSuspended
            ? l10n.courseActionUnsuspend
            : l10n.courseActionSuspendSecondary,
        onPressed: () => onOpenView(_CourseActionSheetView.suspend),
      ),
      _CourseHeaderAction(
        icon: Icons.delete_outline_rounded,
        label: l10n.courseActionDeleteSecondary,
        destructive: true,
        onPressed: () => onOpenView(_CourseActionSheetView.delete),
      ),
    ];
    final bottomActionRows = [
      bottomActions.take(3).toList(),
      bottomActions.skip(3).toList(),
    ];

    return Column(
      key: ValueKey('course-action-content-${course.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CourseDetailReveal(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: courseColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(headerIcon, color: courseColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: course.name,
                        style: typo.sm.copyWith(height: 1.2),
                        children: [
                          if (!previewItem.isPartnerCourse)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.aboveBaseline,
                              baseline: TextBaseline.alphabetic,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 3),
                                child: Text(
                                  natureLabel,
                                  style: typo.xs2.copyWith(
                                    color: colors.mutedForeground,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5.2),
                    Text(
                      headerWeekDetail,
                      style: typo.xs2.copyWith(
                        color: colors.mutedForeground,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (previewItem.isConflict || coupleBadge != null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (previewItem.isConflict)
                            Text(
                              l10n.conflictLabel,
                              style: typo.xs2.copyWith(
                                color: colors.destructive,
                              ),
                            ),
                          if (coupleBadge != null)
                            Text(
                              coupleBadge,
                              style: typo.xs2.copyWith(color: courseColor),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (headerActions.isNotEmpty) ...[
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < headerActions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      _CourseHeaderActionButton(action: headerActions[i]),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        CourseDetailReveal(
          index: 1,
          child: _CourseDetailTile(
            icon: Icons.schedule_outlined,
            title: timeSubtitle,
            subtitle: sectionTitle,
            trailing: Text(
              '${course.startTime}-${course.endTime}',
              style: typo.sm.copyWith(color: colors.foreground, height: 1.2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        CourseDetailReveal(
          index: 2,
          child: _CourseDetailTile(
            icon: Icons.person_outline_rounded,
            title: teacher.isNotEmpty ? teacher : l10n.unknownTeacher,
            subtitle: shortNameSubtitle,
          ),
        ),
        const SizedBox(height: 8),
        CourseDetailReveal(
          index: 3,
          child: _CourseDetailTile(
            icon: Icons.location_on_outlined,
            iconColor: courseColor,
            title: location.isNotEmpty ? location : l10n.unknownLocation,
            subtitle: shortNameSubtitle,
          ),
        ),
        if (!previewItem.isReadOnly) ...[
          const SizedBox(height: 14),
          CourseDetailReveal(
            index: 4,
            child: Column(
              children: [
                for (
                  var rowIndex = 0;
                  rowIndex < bottomActionRows.length;
                  rowIndex++
                ) ...[
                  if (rowIndex > 0) const SizedBox(height: 4),
                  Row(
                    children: [
                      for (
                        var i = 0;
                        i < bottomActionRows[rowIndex].length;
                        i++
                      ) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: HyperosFrostedSheetButton(
                            key: ValueKey(
                              'course-action-$rowIndex-${bottomActionRows[rowIndex][i].label}-${course.id}',
                            ),
                            icon: bottomActionRows[rowIndex][i].icon,
                            label: bottomActionRows[rowIndex][i].label,
                            variant: bottomActionRows[rowIndex][i].destructive
                                ? HyperosFrostedSheetButtonVariant.destructive
                                : HyperosFrostedSheetButtonVariant.neutral,
                            dense: true,
                            expand: true,
                            onPressed: bottomActionRows[rowIndex][i].onPressed,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CourseHeaderAction {
  const _CourseHeaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool destructive;
}

class _CourseHeaderActionButton extends StatelessWidget {
  const _CourseHeaderActionButton({required this.action});

  final _CourseHeaderAction action;

  @override
  Widget build(BuildContext context) {
    final typo = context.theme.typography.body;
    final colors = context.theme.colors;
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 19, color: colors.foreground),
              const SizedBox(height: 2),
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: typo.xs2.copyWith(
                  color: colors.mutedForeground,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(message: action.tooltip ?? action.label, child: button);
  }
}

class _CourseDetailTile extends StatelessWidget {
  const _CourseDetailTile({
    required this.icon,
    this.title,
    this.subtitle,
    this.trailing,
    this.iconColor,
  });

  final IconData icon;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final typo = context.theme.typography.body;
    final colors = context.theme.colors;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? colors.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title!,
                  style: typo.sm.copyWith(height: 1.25),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: typo.xs2.copyWith(
                      color: colors.mutedForeground,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );

    return SizedBox(
      height: 52,
      child: HyperosFrostedSurface(
        borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
        child: content,
      ),
    );
  }
}

String _formatTimeTileSubtitle(
  BuildContext context, {
  required Course course,
  required int week,
  required TimetableSettings settings,
}) {
  final l10n = AppLocalizations.of(context)!;
  final date = _dateForWeekDay(settings, week, course.dayOfWeek);
  final parts = <String>[];

  if (date != null) {
    final localeName = Localizations.localeOf(context).toString();
    parts.add(DateFormat.MMMd(localeName).format(date));
  }

  parts.add(l10n.weekLabel(week));

  return parts.join(' ');
}

String _weekdayLabel(AppLocalizations l10n, int dayOfWeek) {
  final labels = [
    l10n.weekdayMon,
    l10n.weekdayTue,
    l10n.weekdayWed,
    l10n.weekdayThu,
    l10n.weekdayFri,
    l10n.weekdaySat,
    l10n.weekdaySun,
  ];
  if (dayOfWeek < 1 || dayOfWeek > labels.length) {
    return dayOfWeek.toString();
  }
  return labels[dayOfWeek - 1];
}

DateTime? _dateForWeekDay(TimetableSettings settings, int week, int dayOfWeek) {
  final semesterStart = settings.semesterStartDate;
  if (semesterStart == null) {
    return null;
  }

  final normalizedStart = DateTime(
    semesterStart.year,
    semesterStart.month,
    semesterStart.day,
  ).subtract(Duration(days: semesterStart.weekday - 1));

  return normalizedStart.add(Duration(days: (week - 1) * 7 + dayOfWeek - 1));
}

bool _isAlarmAvailable({
  required TimetableSettings settings,
  required int week,
  required Course course,
  required TimetableProvider provider,
}) {
  final date = _dateForWeekDay(settings, week, course.dayOfWeek);
  if (date == null) return false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final courseDate = DateTime(date.year, date.month, date.day);
  if (courseDate.isBefore(today)) return false;
  if (courseDate.isAfter(today)) return true;
  // 当天：已开课的不显示闹钟入口。
  final startText = provider.resolvedCourseStartTime(course);
  if (startText == null) return false;
  final parts = startText.split(':');
  if (parts.length != 2) return false;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return false;
  final startAt = DateTime(now.year, now.month, now.day, hour, minute);
  return now.isBefore(startAt);
}
