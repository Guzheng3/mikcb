import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../models/course.dart';
import '../models/course_task.dart';
import '../models/timetable_settings.dart';
import '../providers/timetable_provider.dart';
import '../utils/app_toast.dart';
import 'course_field_picker_sheet.dart';
import 'miuix_date_picker_sheet.dart';
import '../ui/hyperos/hyperos.dart';

enum CourseDeleteMode { course, occurrence }

enum CourseSuspendMode { thisWeek, allWeeks }

class CourseRescheduleDraft {
  const CourseRescheduleDraft({
    required this.targetWeek,
    required this.targetDayOfWeek,
    required this.targetStartSection,
    required this.targetEndSection,
    required this.targetLocation,
  });

  final int targetWeek;
  final int targetDayOfWeek;
  final int targetStartSection;
  final int targetEndSection;
  final String targetLocation;
}

Future<CourseDeleteMode?> showCourseDeleteModeSheet(
  BuildContext context, {
  required bool canDeleteOccurrence,
  required int week,
}) {
  return showHomeHyperosSheet<CourseDeleteMode>(
    context: context,
    builder: (sheetContext) => CourseDeleteModeSheetBody(
      canDeleteOccurrence: canDeleteOccurrence,
      week: week,
    ),
  );
}

Future<CourseSuspendMode?> showCourseSuspendModeSheet(
  BuildContext context, {
  required bool isSuspendedThisWeek,
  required bool hasAnySuspended,
}) {
  return showHomeHyperosSheet<CourseSuspendMode>(
    context: context,
    builder: (sheetContext) => CourseSuspendModeSheetBody(
      isSuspendedThisWeek: isSuspendedThisWeek,
      hasAnySuspended: hasAnySuspended,
    ),
  );
}

Future<CourseRescheduleDraft?> showCourseRescheduleSheet(
  BuildContext context, {
  required Course course,
  required int sourceWeek,
  required TimetableSettings settings,
  required List<String> weekDays,
  required List<SectionTime> sectionTimes,
  required List<String> locationSuggestions,
}) {
  return showHomeHyperosSheet<CourseRescheduleDraft>(
    context: context,
    builder: (sheetContext) => CourseRescheduleSheetBody(
      course: course,
      sourceWeek: sourceWeek,
      settings: settings,
      weekDays: weekDays,
      sectionTimes: sectionTimes,
      locationSuggestions: locationSuggestions,
    ),
  );
}

Future<bool> showCourseTaskSheet(
  BuildContext context, {
  required Course course,
  required int week,
  CourseTask? task,
}) {
  return showHomeHyperosSheet<bool>(
    context: context,
    builder: (sheetContext) =>
        CourseTaskSheetBody(course: course, week: week, task: task),
  ).then((value) => value ?? false);
}

Future<bool> showDeleteCourseConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showHomeHyperosSheet<bool>(
    context: context,
    builder: (ctx) =>
        _DeleteCourseConfirmSheetBody(title: title, message: message),
  ).then((value) => value ?? false);
}

Future<bool> showDeleteOccurrenceConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDeleteCourseConfirmDialog(context, title: title, message: message);
}

class CourseDeleteModeSheetBody extends StatelessWidget {
  const CourseDeleteModeSheetBody({
    required this.canDeleteOccurrence,
    required this.week,
    this.embedded = false,
    this.onResult,
  });

  final bool canDeleteOccurrence;
  final int week;
  final bool embedded;
  final ValueChanged<CourseDeleteMode?>? onResult;

  void _finish(BuildContext context, [CourseDeleteMode? mode]) {
    final callback = onResult;
    if (callback == null) {
      Navigator.of(context).pop(mode);
      return;
    }
    callback(mode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FollowupSheetHeader(
          icon: Icons.delete_outline_rounded,
          iconColor: colors.destructive,
          title: l10n.deleteModeTitle,
          subtitle: l10n.deleteModeSubtitle,
        ),
        const SizedBox(height: 14),
        _FollowupOptionTile(
          icon: Icons.delete_sweep_outlined,
          title: l10n.deleteCourseAction,
          onTap: () => _finish(context, CourseDeleteMode.course),
        ),
        const SizedBox(height: 8),
        _FollowupOptionTile(
          icon: Icons.remove_circle_outline_rounded,
          title: l10n.deleteOccurrenceAction,
          subtitle: canDeleteOccurrence
              ? l10n.deleteModeHintCurrentWeek(week)
              : l10n.deleteModeHintUnavailable(week),
          enabled: canDeleteOccurrence,
          onTap: canDeleteOccurrence
              ? () => _finish(context, CourseDeleteMode.occurrence)
              : null,
        ),
        const SizedBox(height: 14),
        _FollowupCancelButton(onPress: () => _finish(context)),
      ],
    );

    return embedded ? content : _FollowupSheetContainer(child: content);
  }
}

class CourseSuspendModeSheetBody extends StatelessWidget {
  const CourseSuspendModeSheetBody({
    required this.isSuspendedThisWeek,
    required this.hasAnySuspended,
    this.embedded = false,
    this.onResult,
  });

  final bool isSuspendedThisWeek;
  final bool hasAnySuspended;
  final bool embedded;
  final ValueChanged<CourseSuspendMode?>? onResult;

  void _finish(BuildContext context, [CourseSuspendMode? mode]) {
    final callback = onResult;
    if (callback == null) {
      Navigator.of(context).pop(mode);
      return;
    }
    callback(mode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FollowupSheetHeader(
          icon: isSuspendedThisWeek
              ? Icons.play_circle_outline_rounded
              : Icons.pause_circle_outline_rounded,
          iconColor: colors.foreground,
          title: l10n.suspendSheetTitle,
          subtitle: l10n.suspendSheetSubtitle,
        ),
        const SizedBox(height: 14),
        _FollowupOptionTile(
          icon: isSuspendedThisWeek
              ? Icons.play_circle_outline_rounded
              : Icons.pause_circle_outline_rounded,
          title: isSuspendedThisWeek
              ? l10n.courseActionUnsuspend
              : l10n.suspendThisWeek,
          subtitle: l10n.suspendThisWeekDesc,
          onTap: () => _finish(context, CourseSuspendMode.thisWeek),
        ),
        const SizedBox(height: 8),
        _FollowupOptionTile(
          icon: hasAnySuspended
              ? Icons.play_circle_outline_rounded
              : Icons.pause_circle_filled_outlined,
          title: hasAnySuspended
              ? l10n.unsuspendAllWeeks
              : l10n.suspendAllWeeks,
          subtitle: hasAnySuspended
              ? l10n.unsuspendAllWeeksDesc
              : l10n.suspendAllWeeksDesc,
          onTap: () => _finish(context, CourseSuspendMode.allWeeks),
        ),
        const SizedBox(height: 14),
        _FollowupCancelButton(onPress: () => _finish(context)),
      ],
    );

    return embedded ? content : _FollowupSheetContainer(child: content);
  }
}

class _DeleteCourseConfirmSheetBody extends StatelessWidget {
  const _DeleteCourseConfirmSheetBody({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;

    return _FollowupSheetContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FollowupSheetHeader(
            icon: Icons.delete_outline_rounded,
            iconColor: colors.destructive,
            title: title,
          ),
          const SizedBox(height: 12),
          HyperosFrostedSurface(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Text(
                message,
                style: typo.xs2.copyWith(
                  color: colors.mutedForeground,
                  height: 1.45,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: HyperosFrostedSheetButton(
                  label: l10n.cancelAction,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: HyperosFrostedSheetButton(
                  label: l10n.deleteAction,
                  variant: HyperosFrostedSheetButtonVariant.destructive,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CourseRescheduleSheetBody extends StatefulWidget {
  const CourseRescheduleSheetBody({
    required this.course,
    required this.sourceWeek,
    required this.settings,
    required this.weekDays,
    required this.sectionTimes,
    required this.locationSuggestions,
    this.embedded = false,
    this.onCancel,
    this.onConfirmed,
  });

  final Course course;
  final int sourceWeek;
  final TimetableSettings settings;
  final List<String> weekDays;
  final List<SectionTime> sectionTimes;
  final List<String> locationSuggestions;
  final bool embedded;
  final VoidCallback? onCancel;
  final ValueChanged<CourseRescheduleDraft>? onConfirmed;

  @override
  State<CourseRescheduleSheetBody> createState() =>
      _CourseRescheduleSheetBodyState();
}

class CourseTaskSheetBody extends StatefulWidget {
  const CourseTaskSheetBody({
    required this.course,
    required this.week,
    this.task,
    this.embedded = false,
    this.onCancel,
    this.onCompleted,
  });

  final Course course;
  final int week;
  final CourseTask? task;
  final bool embedded;
  final VoidCallback? onCancel;
  final VoidCallback? onCompleted;

  @override
  State<CourseTaskSheetBody> createState() => _CourseTaskSheetBodyState();
}

class _CourseTaskSheetBodyState extends State<CourseTaskSheetBody> {
  late final TextEditingController _titleController = TextEditingController();
  late final TextEditingController _noteController = TextEditingController();
  DateTime? _dueDate;
  bool _hasDueDate = false;
  bool _isCompleted = false;
  bool _isSaving = false;
  bool _didInitTexts = false;
  String? _titleError;

  bool get _isEditing => widget.task != null;

  void _finish() {
    final callback = widget.onCompleted;
    if (callback == null) {
      Navigator.of(context).pop(true);
      return;
    }
    callback();
  }

  void _cancel() {
    final callback = widget.onCancel;
    if (callback == null) {
      Navigator.of(context).pop();
      return;
    }
    callback();
  }

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    if (task != null) {
      _titleController.text = task.title;
      _noteController.text = task.note ?? '';
      _dueDate = task.dueDate;
      _isCompleted = task.isCompleted;
      _hasDueDate = task.dueDate != null;
    } else {
      _dueDate = context.read<TimetableProvider>().dateForCourseOccurrence(
        widget.course,
        widget.week,
      );
      _hasDueDate = _dueDate != null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitTexts) {
      return;
    }
    _didInitTexts = true;
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;
    if (task == null) {
      _titleController.text =
          widget.course.sessionNoteForWeek(widget.week)?.trimmedText ??
          l10n.taskHomeworkDefaultTitle;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showMiuixDatePickerSheet(
      context,
      title: l10n.taskDueDateLabel,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _dueDate = CourseTask.dateOnly(selected);
      _hasDueDate = true;
    });
  }

  Future<void> _deleteTask() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showHyperosConfirmDialog(
      context: context,
      title: l10n.taskDelete,
      message: l10n.taskDeleteConfirm,
      cancelLabel: l10n.cancelAction,
      confirmLabel: l10n.deleteAction,
      destructive: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<TimetableProvider>().deleteTask(widget.task!.id);
    if (!mounted) {
      return;
    }
    _finish();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final title = _titleController.text.trim();
    if (_isSaving) {
      return;
    }
    if (title.isEmpty) {
      setState(() => _titleError = l10n.taskTitleRequired);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _titleError = null;
      _isSaving = true;
    });
    final provider = context.read<TimetableProvider>();
    final now = DateTime.now();
    final note = _noteController.text.trim();
    final task =
        (widget.task ??
                CourseTask(
                  id: const Uuid().v4(),
                  title: title,
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              title: title,
              courseId: widget.course.id,
              sourceWeek: widget.week,
              dueDate: _hasDueDate ? _dueDate : null,
              isCompleted: _isCompleted,
              note: note.isEmpty ? null : note,
              updatedAt: now,
            );
    try {
      if (_isEditing) {
        await provider.updateTask(task);
      } else {
        await provider.addTask(task);
      }
      if (!mounted) {
        return;
      }
      _finish();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: error is ArgumentError
            ? (error.message?.toString() ?? l10n.taskTitleRequired)
            : l10n.taskTitleRequired,
        kind: AppToastKind.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;
    final dueDate = _dueDate;
    final actions = Row(
      children: [
        if (_isEditing) ...[
          Expanded(
            child: HyperosFrostedSheetButton(
              label: l10n.deleteAction,
              variant: HyperosFrostedSheetButtonVariant.destructive,
              expand: true,
              onPressed: _deleteTask,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: HyperosFrostedSheetButton(
            label: l10n.cancelAction,
            expand: true,
            onPressed: _cancel,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: HyperosButton(
            label: l10n.saveTask,
            expand: true,
            onPressed: _isSaving ? null : _save,
          ),
        ),
      ],
    );

    return _RescheduleSheetScaffold(
      embedded: widget.embedded,
      actions: actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FollowupSheetHeader(
            icon: Icons.assignment_outlined,
            iconColor: colors.primary,
            title: _isEditing ? l10n.editTask : l10n.addTask,
            subtitle: '${widget.course.name} · ${l10n.weekLabel(widget.week)}',
          ),
          const SizedBox(height: 14),
          HyperosTextField(
            controller: _titleController,
            label: l10n.taskTitleLabel,
            hint: l10n.taskTitleHint,
            helper: _titleError,
            onChanged: (value) {
              if (_titleError != null && value.trim().isNotEmpty) {
                setState(() => _titleError = null);
              }
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          HyperosTextField(
            controller: _noteController,
            label: l10n.taskNoteLabel,
            hint: l10n.taskNoteHint,
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          HyperosSwitchTile(
            title: l10n.taskDueDateLabel,
            value: _hasDueDate,
            onChanged: (value) {
              setState(() {
                _hasDueDate = value;
                _dueDate ??= CourseTask.dateOnly(DateTime.now());
                if (!value) {
                  _dueDate = null;
                }
              });
            },
          ),
          if (_hasDueDate && dueDate != null) ...[
            const SizedBox(height: 8),
            CourseFieldPickerTile(
              label: l10n.taskDueDateLabel,
              value: DateFormat.yMMMMd(l10n.localeName).format(dueDate),
              icon: Icons.event_outlined,
              onPress: _pickDueDate,
            ),
          ],
          const SizedBox(height: 8),
          HyperosSwitchTile(
            title: l10n.taskCompletedSection,
            value: _isCompleted,
            onChanged: (value) => setState(() => _isCompleted = value),
          ),
        ],
      ),
    );
  }
}

class _CourseRescheduleSheetBodyState extends State<CourseRescheduleSheetBody> {
  late int _targetWeek;
  late int _targetDayOfWeek;
  late int _targetStartSection;
  late int _targetEndSection;
  late final TextEditingController _locationController;

  List<int> get _availableWeeks => widget.settings.availableWeeks;

  List<int> get _sectionNumbers =>
      List.generate(widget.settings.sectionCount, (index) => index + 1);

  @override
  void initState() {
    super.initState();
    _targetWeek = widget.sourceWeek;
    _targetDayOfWeek = widget.course.dayOfWeek;
    _targetStartSection = widget.course.startSection;
    _targetEndSection = widget.course.endSection;
    _locationController = TextEditingController(text: widget.course.location);
    _locationController.addListener(_handleLocationChanged);
  }

  void _handleLocationChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _locationController.removeListener(_handleLocationChanged);
    _locationController.dispose();
    super.dispose();
  }

  String _weekdayLabel(int dayOfWeek) {
    if (dayOfWeek < 1 || dayOfWeek > widget.weekDays.length) {
      return dayOfWeek.toString();
    }
    return widget.weekDays[dayOfWeek - 1];
  }

  String? _timeRangeForSections(int startSection, int endSection) {
    final sections = widget.sectionTimes;
    final startIndex = startSection - 1;
    final endIndex = endSection - 1;
    if (startIndex < 0 ||
        endIndex < 0 ||
        startIndex >= sections.length ||
        endIndex >= sections.length ||
        startSection > endSection) {
      return null;
    }
    return '${sections[startIndex].startTime}-${sections[endIndex].endTime}';
  }

  String _occurrenceLine({
    required AppLocalizations l10n,
    required int week,
    required int dayOfWeek,
    required int startSection,
    required int endSection,
    required String startTime,
    required String endTime,
  }) {
    final resolvedTime =
        _timeRangeForSections(startSection, endSection) ??
        '$startTime-$endTime';
    return '${l10n.weekLabel(week)} · ${_weekdayLabel(dayOfWeek)} · '
        '${l10n.sectionLabel(startSection)}-${l10n.sectionLabel(endSection)} · '
        '$resolvedTime';
  }

  bool get _hasChanges {
    final location = _locationController.text.trim();
    return widget.sourceWeek != _targetWeek ||
        widget.course.dayOfWeek != _targetDayOfWeek ||
        widget.course.startSection != _targetStartSection ||
        widget.course.endSection != _targetEndSection ||
        widget.course.location.trim() != location;
  }

  void _shiftWeek(int delta) {
    final weeks = _availableWeeks;
    final index = weeks.indexOf(_targetWeek);
    if (index == -1) {
      return;
    }
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= weeks.length) {
      return;
    }
    setState(() => _targetWeek = weeks[nextIndex]);
  }

  void _showLocationPicker() {
    final l10n = AppLocalizations.of(context)!;
    showCourseFieldPickerSheet(
      context,
      title: l10n.selectLocationTitle,
      suggestions: widget.locationSuggestions,
      controller: _locationController,
      onConfirmed: _handleLocationChanged,
    );
  }

  Widget _buildCompactSelectField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final theme = context.theme;
    return HyperosFrostedSurface(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colors.border.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: theme.typography.body.sm,
                      children: [
                        TextSpan(
                          text: '$label ',
                          style: TextStyle(color: theme.colors.mutedForeground),
                        ),
                        TextSpan(text: value),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: theme.colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickInt({
    required String title,
    required Map<String, int> items,
    required int current,
    required ValueChanged<int> onSelected,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showHyperosSelectSheet<int>(
      context: context,
      title: title,
      items: items,
      currentValue: current,
      cancelLabel: l10n.cancelAction,
    );
    if (!mounted || selected == null || selected == current) {
      return;
    }
    onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;
    final weekIndex = _availableWeeks.indexOf(_targetWeek);
    final canDecrementWeek = weekIndex > 0;
    final canIncrementWeek =
        weekIndex != -1 && weekIndex < _availableWeeks.length - 1;
    final targetTimeRange = _timeRangeForSections(
      _targetStartSection,
      _targetEndSection,
    );
    final locationText = _locationController.text.trim();
    final sourceLine = _occurrenceLine(
      l10n: l10n,
      week: widget.sourceWeek,
      dayOfWeek: widget.course.dayOfWeek,
      startSection: widget.course.startSection,
      endSection: widget.course.endSection,
      startTime: widget.course.startTime,
      endTime: widget.course.endTime,
    );
    final targetLine = _occurrenceLine(
      l10n: l10n,
      week: _targetWeek,
      dayOfWeek: _targetDayOfWeek,
      startSection: _targetStartSection,
      endSection: _targetEndSection,
      startTime: widget.course.startTime,
      endTime: widget.course.endTime,
    );

    return _RescheduleSheetScaffold(
      embedded: widget.embedded,
      actions: Row(
        children: [
          Expanded(
            child: HyperosFrostedSheetButton(
              label: l10n.cancelAction,
              expand: true,
              onPressed: () {
                final callback = widget.onCancel;
                if (callback != null) {
                  callback();
                  return;
                }
                Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: HyperosButton(
              label: l10n.confirmRescheduleAction,
              expand: true,
              onPressed: _hasChanges
                  ? () {
                      final draft = CourseRescheduleDraft(
                        targetWeek: _targetWeek,
                        targetDayOfWeek: _targetDayOfWeek,
                        targetStartSection: _targetStartSection,
                        targetEndSection: _targetEndSection,
                        targetLocation: _locationController.text,
                      );
                      final callback = widget.onConfirmed;
                      if (callback != null) {
                        callback(draft);
                        return;
                      }
                      Navigator.of(context).pop(draft);
                    }
                  : null,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.rescheduleCurrentOccurrenceTitle,
            style: typo.lg.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.rescheduleCurrentOccurrenceSubtitle(widget.sourceWeek),
            style: typo.xs2.copyWith(
              color: colors.mutedForeground,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${l10n.currentBadge}：$sourceLine',
            style: typo.xs2.copyWith(
              color: colors.mutedForeground,
              height: 1.35,
            ),
          ),
          if (widget.course.location.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              l10n.locationPrefix(widget.course.location.trim()),
              style: typo.xs2.copyWith(color: colors.mutedForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _RescheduleStepButton(
                icon: Icons.remove_rounded,
                enabled: canDecrementWeek,
                onPress: () => _shiftWeek(-1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactSelectField(
                  label: l10n.rescheduleTargetWeekLabel,
                  value: l10n.weekLabel(_targetWeek),
                  onTap: () => _pickInt(
                    title: l10n.rescheduleTargetWeekLabel,
                    items: {
                      for (final week in _availableWeeks)
                        l10n.weekLabel(week): week,
                    },
                    current: _targetWeek,
                    onSelected: (value) => setState(() => _targetWeek = value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _RescheduleStepButton(
                icon: Icons.add_rounded,
                enabled: canIncrementWeek,
                onPress: () => _shiftWeek(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var index = 0; index < widget.weekDays.length; index++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _WeekdayChoiceChip(
                      label: widget.weekDays[index],
                      selected: _targetDayOfWeek == index + 1,
                      onSelected: () =>
                          setState(() => _targetDayOfWeek = index + 1),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactSelectField(
                  label: l10n.startSectionLabel,
                  value: l10n.sectionLabel(_targetStartSection),
                  onTap: () => _pickInt(
                    title: l10n.startSectionLabel,
                    items: {
                      for (final section in _sectionNumbers)
                        l10n.sectionLabel(section): section,
                    },
                    current: _targetStartSection,
                    onSelected: (value) {
                      setState(() {
                        _targetStartSection = value;
                        if (_targetEndSection < _targetStartSection) {
                          _targetEndSection = _targetStartSection;
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactSelectField(
                  label: l10n.endSectionLabel,
                  value: l10n.sectionLabel(_targetEndSection),
                  onTap: () => _pickInt(
                    title: l10n.endSectionLabel,
                    items: {
                      for (final section in _sectionNumbers.where(
                        (value) => value >= _targetStartSection,
                      ))
                        l10n.sectionLabel(section): section,
                    },
                    current: _targetEndSection,
                    onSelected: (value) {
                      setState(() => _targetEndSection = value);
                    },
                  ),
                ),
              ),
            ],
          ),
          if (targetTimeRange != null) ...[
            const SizedBox(height: 4),
            Text(
              targetTimeRange,
              style: typo.xs2.copyWith(color: colors.mutedForeground),
            ),
          ],
          const SizedBox(height: 8),
          CourseFieldPickerTile(
            label: l10n.locationLabel,
            value: locationText.isEmpty ? l10n.manualInputLabel : locationText,
            icon: Icons.location_on_outlined,
            isPlaceholder: locationText.isEmpty,
            onPress: _showLocationPicker,
          ),
          if (_hasChanges) ...[
            const SizedBox(height: 10),
            Text(
              '→ $targetLine',
              style: typo.sm.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (locationText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                l10n.locationPrefix(locationText),
                style: typo.xs2.copyWith(color: colors.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RescheduleSheetScaffold extends StatelessWidget {
  const _RescheduleSheetScaffold({
    required this.child,
    required this.actions,
    this.embedded = false,
  });

  final Widget child;
  final Widget actions;
  final bool embedded;

  static const _footerHeight = 48.0;
  static const _footerGap = 12.0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        if (embedded) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
              ),
              actions,
            ],
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight),
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.only(
                  bottom: _footerHeight + _footerGap,
                ),
                child: child,
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: actions),
            ],
          ),
        );
      },
    );

    if (embedded) {
      return content;
    }

    return HyperosSheetFrame(
      maxHeight: maxHeight,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
      child: content,
    );
  }
}

class _RescheduleStepButton extends StatelessWidget {
  const _RescheduleStepButton({
    required this.icon,
    required this.enabled,
    required this.onPress,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return HyperosIconButton(
      icon: icon,
      iconSize: 18,
      onPressed: enabled ? onPress : null,
    );
  }
}

class _WeekdayChoiceChip extends StatelessWidget {
  const _WeekdayChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;
    final colorScheme = Theme.of(context).colorScheme;
    final highlight = selected ? colorScheme.primary : colors.foreground;

    return HyperosFrostedSurface(
      borderRadius: BorderRadius.circular(999),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? highlight.withValues(alpha: 0.10)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? highlight.withValues(alpha: 0.45)
                    : colors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: typo.xs2.copyWith(
                  color: highlight,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowupSheetContainer extends StatelessWidget {
  const _FollowupSheetContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HyperosSheetFrame(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: child,
    );
  }
}

class _FollowupSheetHeader extends StatelessWidget {
  const _FollowupSheetHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: typo.sm.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: typo.xs2.copyWith(
                    color: colors.mutedForeground,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FollowupOptionTile extends StatelessWidget {
  const _FollowupOptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typo = context.theme.typography.body;
    final foreground = enabled ? colors.foreground : colors.mutedForeground;

    return HyperosFrostedSurface(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: typo.sm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: foreground,
                          height: 1.25,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: typo.xs2.copyWith(
                            color: colors.mutedForeground,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: enabled
                      ? colors.mutedForeground
                      : colors.mutedForeground.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowupCancelButton extends StatelessWidget {
  const _FollowupCancelButton({required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: double.infinity,
      child: HyperosFrostedSheetButton(
        label: l10n.cancelAction,
        expand: true,
        onPressed: onPress,
      ),
    );
  }
}
