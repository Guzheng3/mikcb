import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';

import '../domain/course_domain.dart';
import '../providers/timetable_provider.dart';
import '../services/course_recolor_history_service.dart';
import '../services/import_random_color_preferences.dart';
import '../utils/app_toast.dart';
import '../utils/course_recolor.dart';
import '../utils/hex_color.dart';

/// 「课表重新配色」：导入后随时给全部课程刷一套随机颜色，无需重新导入。
///
/// 「换一批」生成新随机批次；「上一套 / 下一套」在配色历史（含首次换色
/// 前的导入原色快照）里往返。色板只有唯一一套 30 色随机预设，文字色开关
/// 与导入随机配色共用同一偏好。历史按课表 profile 隔离，切换课表互不影响。
Future<void> showCourseRecolorSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  if (context.read<TimetableProvider>().courses.isEmpty) {
    showAppToast(context, message: l10n.courseRecolorNoCoursesToast);
    return;
  }
  await showHyperosSheet<void>(
    context: context,
    enableDrag: false,
    builder: (sheetContext) => const CourseRecolorSheet(),
  );
}

class CourseRecolorSheet extends StatefulWidget {
  const CourseRecolorSheet({super.key});

  @override
  State<CourseRecolorSheet> createState() => _CourseRecolorSheetState();
}

class _CourseRecolorSheetState extends State<CourseRecolorSheet> {
  CourseRecolorHistoryState _history = const CourseRecolorHistoryState.empty();
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  String _historyScope(TimetableProvider provider) =>
      provider.activeProfileId ?? 'default';

  Future<void> _loadHistory() async {
    final provider = context.read<TimetableProvider>();
    final state = await CourseRecolorHistoryService.load(
      _historyScope(provider),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _history = state;
      _loaded = true;
    });
  }

  Future<void> _applyNewBatch() async {
    if (_busy || !_loaded) {
      return;
    }
    final provider = context.read<TimetableProvider>();
    final courses = provider.courses;
    if (courses.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final assignMatchingTextColor =
          await ImportRandomColorPreferences.isTextColorEnabled();
      final schemes = [..._history.schemes];
      if (schemes.isEmpty) {
        // 首次换色：先把当前（导入原）颜色存成快照，永远有路可回。
        schemes.add(captureCourseRecolorSnapshot(courses));
      } else if (_history.index < schemes.length - 1) {
        // 从历史中途换新：丢弃被放弃的前向分支（undo/redo 语义）。
        schemes.removeRange(_history.index + 1, schemes.length);
      }
      final scheme = CourseRecolorScheme.seed(
        seed: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
        assignMatchingTextColor: assignMatchingTextColor,
        createdAt: DateTime.now(),
      );
      schemes.add(scheme);
      final index = schemes.length - 1;
      // 先落历史再应用：apply 内部会把课程颜色持久化，若先应用后存历史，
      // 两步之间进程被杀会留下「颜色已变、历史未存」——首次换色时导入原
      // 色快照就此永久丢失。反过来最坏只是多存一条尚未应用的方案，用户
      // 下一拍导航/重刷即可自愈。
      await CourseRecolorHistoryService.save(
        _historyScope(provider),
        schemes,
        index,
      );
      await provider.applyCourseRecolors(
        applyCourseRecolorScheme(courses, scheme),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _history = CourseRecolorHistoryState(schemes: schemes, index: index);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _move(int delta) async {
    if (_busy || !_loaded) {
      return;
    }
    final target = _history.index + delta;
    if (target < 0 || target >= _history.schemes.length) {
      return;
    }
    final provider = context.read<TimetableProvider>();
    final courses = provider.courses;
    if (courses.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final scheme = _history.schemes[target];
      // 与 _applyNewBatch 同口径：先落历史再应用，避免中间态丢历史。
      await CourseRecolorHistoryService.save(
        _historyScope(provider),
        _history.schemes,
        target,
      );
      await provider.applyCourseRecolors(
        applyCourseRecolorScheme(courses, scheme),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _history = CourseRecolorHistoryState(
          schemes: _history.schemes,
          index: target,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = context.theme;
    final historyIsEmpty = _history.schemes.isEmpty;
    return HyperosSheet(
      title: l10n.courseRecolorSheetTitle,
      description: l10n.courseRecolorSheetDescription,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.32,
            ),
            child: const SingleChildScrollView(
              physics: ClampingScrollPhysics(),
              child: _CourseColorPreview(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: HyperosButton(
                  label: l10n.courseRecolorPrevious,
                  variant: HyperosButtonVariant.secondary,
                  fitLabel: true,
                  onPressed:
                      _history.canGoBack && !_busy ? () => _move(-1) : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: historyIsEmpty
                    ? const SizedBox.shrink()
                    : Text(
                        l10n.courseRecolorSchemePosition(
                          _history.index + 1,
                          _history.schemes.length,
                        ),
                        maxLines: 1,
                        style: theme.typography.body.xs2.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
              ),
              Expanded(
                child: HyperosButton(
                  label: l10n.courseRecolorNext,
                  variant: HyperosButtonVariant.secondary,
                  fitLabel: true,
                  onPressed:
                      _history.canGoForward && !_busy ? () => _move(1) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          HyperosButton(
            label: l10n.courseRecolorNewBatchButton,
            expand: true,
            loading: _busy,
            onPressed: _loaded ? _applyNewBatch : null,
          ),
        ],
      ),
    );
  }
}

/// 当前整份课表的颜色预览：同名一组，按课表出现顺序排布胶囊。
class _CourseColorPreview extends StatelessWidget {
  const _CourseColorPreview();

  @override
  Widget build(BuildContext context) {
    return Consumer<TimetableProvider>(
      builder: (context, provider, _) {
        final seen = <String>{};
        final pills = <({String name, String color})>[];
        for (final course in provider.courses) {
          final key = buildSharedCourseNameKey(course.name);
          if (!seen.add(key)) {
            continue;
          }
          pills.add((name: course.name, color: course.color));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final pill in pills)
              _GroupColorPill(name: pill.name, colorHex: pill.color),
          ],
        );
      },
    );
  }
}

class _GroupColorPill extends StatelessWidget {
  const _GroupColorPill({required this.name, required this.colorHex});

  final String name;
  final String colorHex;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final color = tryParseHexColor(colorHex) ?? const Color(0xFF2196F3);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // 玻璃弹层里的浅井用 secondaryVariant；colors.secondary 是兼容
          // 垫片上的深色 M3 强调色，浅色弹窗里会像一颗黑块。
          color: HyperosColors.secondaryVariant(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colors.border, width: 0.8),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.xs2.copyWith(
                  color: theme.colors.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
