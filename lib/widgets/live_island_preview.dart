import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../models/timetable_settings.dart';
import '../services/bundled_assets.dart';
import '../ui/hyperos/hyperos.dart';
import '../utils/hex_color.dart';

/// 实时活动摘要态胶囊预览（ColorOS 流体云 / HyperOS 超级岛共用同一形态）。
///
/// 还原真机摘要态胶囊的单行左右分区：中间是摄像头开孔；左侧是通知 smallIcon
/// 的图标位（随阶段切换：时钟 / 书 / 对勾）；右侧文本按阶段分发：
///
/// * 上课前 = 分钟数（`12分钟`，分钟粒度，不逐秒刷新）；
/// * 上课中 = 「上课中」（刚上课 1 分钟内为「开始上课」）；
/// * 下课 = 「即将下课」；
/// * 大课（多节连上）内部课间 = 到下一节上课的分钟数。
///
/// 这条规则与原生 `LiveUpdateService.buildColorosIslandText()` 一致：左侧图标槽
/// 实测是约 50px 的圆形位、放不下文字，右侧可用宽度只有 6–7 个字，秒级倒计时
/// 还会让胶囊随数字位数不断变宽变窄（用户可见的「长度一直在跳」），所以摘要态
/// 一律给分钟粒度或固定短文案，课名/地点/秒级倒计时交给展开卡片和普通通知。
///
/// 「大课下课后下一次上课的倒计时」由下一节课自身的课前提醒（beforeClass）
/// 接管：只有它进入课前窗口时才显示，间隔过大（11:40 下课、14:00 再上课）
/// 自然不显示，因此预览不做单独模拟。
///
/// 「显示内容」那组开关（课程名 / 简称 / 地点 / 倒计时样式 / 阶段文字 / 前缀）
/// 因此不再影响摘要态胶囊，只作用于展开卡片与普通通知；本预览中开启实验性的
/// 「小米岛左侧文字图标」时，左侧图标位改按标签配置绘制，便于先调样式。
///
/// 注意：原生参数里的 progressInfo（环形进度）/ progressTextInfo 服务于点开
/// 后的展开态卡片（由系统渲染），摘要态胶囊没有它；本预览只模拟摘要态，
/// 因此不画环与节点条。
class LiveIslandPreviewCard extends StatefulWidget {
  const LiveIslandPreviewCard({
    super.key,
    required this.display,
    required this.forDuringEnd,
    this.followBeforeClass = false,
    this.endSecondsCountdownThresholdSeconds = 60,
  });

  final LiveDisplaySettings display;

  /// 课中/下课提醒页传 true：该页同时预览「上课中」与「下课提醒」两个岛；
  /// 课前提醒页传 false：只预览「即将上课」岛。
  final bool forDuringEnd;

  /// True on the during/end page while it follows the before-class config;
  /// renders an explanatory badge instead of silently previewing.
  final bool followBeforeClass;

  /// 保留以兼容既有调用点；摘要态胶囊已不含秒级倒计时，不再使用该阈值。
  final int endSecondsCountdownThresholdSeconds;

  @override
  State<LiveIslandPreviewCard> createState() => _LiveIslandPreviewCardState();
}

enum _PreviewStage { beforeClass, duringClass, beforeEnd }

class _LiveIslandPreviewCardState extends State<LiveIslandPreviewCard> {
  static const _pillColor = Color(0xFF060608);
  static const _defaultLabelColor = Color(0xFFFFFFFF);

  late final DateTime _anchor = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // --- Demo course window anchored at [_anchor]; minutes tick naturally ---

  ({DateTime start, DateTime end}) get _beforeWindow {
    final start = _anchor.add(const Duration(minutes: 12, seconds: 37));
    return (start: start, end: start.add(const Duration(minutes: 45)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final d = widget.display;
    final stages = widget.forDuringEnd
        ? const [_PreviewStage.duringClass, _PreviewStage.beforeEnd]
        : const [_PreviewStage.beforeClass];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.followBeforeClass)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.liveIslandPreviewFollowBadge,
                    style: HyperosTypography.listDetail(context),
                  ),
                ),
              ],
            ),
          ),
        for (var index = 0; index < stages.length; index++) ...[
          if (stages.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _stageWord(l10n, stages[index]),
                style: HyperosTypography.listDetail(context),
              ),
            ),
          _IslandCapsule(
            iconSlot: _buildSmallIcon(l10n, d, stages[index]),
            criticalText: _criticalText(l10n, stages[index]),
          ),
          if (index != stages.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  // --- Left icon slot (notification small-icon position) ------------------

  Widget _buildSmallIcon(
    AppLocalizations l10n,
    LiveDisplaySettings d,
    _PreviewStage stage,
  ) {
    // 实验性左图（小米岛左侧文字图标）优先：开关打开就按配置预览左图；
    // 真机上原生 resolveIslandLabelBitmap() 只对小米系下发，预览里仍按开关
    // 展示，方便先调样式。
    if (d.enableMiuiIslandLabelImage) {
      return _buildIslandLabel(l10n, d);
    }
    // 原生 setSmallIcon：beforeClass=ic_upcoming（时钟）、
    // duringClass=ic_course（书）、beforeEnd=ic_countdown（对勾圆环），
    // 都是白色模板图标；流体云与超级岛都会把它画在摄像头左侧。
    return SizedBox.square(
      dimension: 28,
      child: Icon(_stageSmallIconData(stage), size: 24, color: Colors.white),
    );
  }

  Widget _buildIslandLabel(AppLocalizations l10n, LiveDisplaySettings d) {
    // 原生 buildIslandLabelBitmap：可选图标部分 + 自动缩放的标签文字。
    final includeIcon =
        d.miuiIslandLabelStyle == MiuiIslandLabelStyle.iconAndText;
    final nameToUse = d.useShortName
        ? l10n.liveIslandPreviewSampleCourseShort
        : l10n.liveIslandPreviewSampleCourse;
    final labelText = switch (d.miuiIslandLabelContent) {
      MiuiIslandLabelContent.courseName => nameToUse,
      MiuiIslandLabelContent.location =>
        l10n.liveIslandPreviewSampleLocation,
      MiuiIslandLabelContent.courseNameAndLocation =>
        '$nameToUse ${l10n.liveIslandPreviewSampleLocation}',
    };
    final fontWeight = switch (d.miuiIslandLabelFontWeight) {
      MiuiIslandLabelFontWeight.medium => FontWeight.w500,
      MiuiIslandLabelFontWeight.bold => FontWeight.w700,
      MiuiIslandLabelFontWeight.regular => FontWeight.w400,
    };
    final label = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          labelText,
          maxLines: 1,
          style: TextStyle(
            color: parseHexColorOrFallback(
              d.miuiIslandLabelFontColor,
              fallback: _defaultLabelColor,
            ),
            fontSize: d.miuiIslandLabelFontSize.clamp(4.0, 32.0),
            fontWeight: fontWeight,
          ),
        ),
      );
    if (!includeIcon) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: label,
      );
    }
    final logoPath = d.miuiIslandLabelLogoPath;
    final corner = d.miuiIslandLabelLogoCornerRadius.clamp(0.0, 12.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(corner),
          child: logoPath != null
              ? Image.file(
                  File(logoPath),
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _appIconImage(22),
                )
              : _appIconImage(22),
        ),
        const SizedBox(width: 3),
        Flexible(child: label),
      ],
    );
  }

  /// 对应原生 ic_upcoming / ic_course / ic_countdown 三枚白色矢量图标的
  /// 最接近的 Material 字形。
  IconData _stageSmallIconData(_PreviewStage stage) => switch (stage) {
        _PreviewStage.beforeClass => Icons.access_time,
        _PreviewStage.duringClass => Icons.import_contacts,
        _PreviewStage.beforeEnd => Icons.check_circle_outline,
      };

  Widget _appIconImage(double size) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset(
          BundledAssets.launcherIcon,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );

  // --- Right text (islandCriticalText) ------------------------------------

  /// 与原生 `buildColorosIslandText` 同一规则：
  /// 上课前 = 到上课的分钟数（分钟粒度，避免逐秒刷新导致胶囊宽度抖动）；
  /// 上课中 = 「上课中」；下课 = 「即将下课」。大课内部课间与「下一节倒计时」
  /// 依赖真机的课间里程碑与下一节课选择，预览不做模拟。
  String _criticalText(AppLocalizations l10n, _PreviewStage stage) {
    switch (stage) {
      case _PreviewStage.beforeClass:
        return _formatDuration(
          _beforeWindow.start.difference(DateTime.now()),
          LiveCountdownTextStyle.minuteOnlyCn,
          60,
        );
      case _PreviewStage.duringClass:
        return l10n.liveIslandPreviewStageInClass;
      case _PreviewStage.beforeEnd:
        return l10n.liveIslandPreviewAboutToEnd;
    }
  }

  String _stageWord(AppLocalizations l10n, _PreviewStage stage) {
    switch (stage) {
      case _PreviewStage.beforeClass:
        return l10n.liveIslandPreviewStageBeforeClass;
      case _PreviewStage.duringClass:
        return l10n.liveIslandPreviewStageInClass;
      case _PreviewStage.beforeEnd:
        return l10n.liveIslandPreviewStageBeforeEnd;
    }
  }

  // --- Countdown formatter (port of CountdownFormat.kt) -------------------

  String _formatDuration(
    Duration duration,
    LiveCountdownTextStyle style,
    int thresholdSeconds,
  ) {
    final millis = duration.inMilliseconds;
    final totalSeconds = millis <= 0 ? 0 : millis ~/ 1000;
    switch (style) {
      case LiveCountdownTextStyle.smartMinS:
        return _smart(totalSeconds, thresholdSeconds, 'min', 's');
      case LiveCountdownTextStyle.minuteSecondCn:
        return _minuteSecond(totalSeconds, '分钟', '秒');
      case LiveCountdownTextStyle.minuteSecondColon:
        final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
        final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
        return '$minutes:$seconds';
      case LiveCountdownTextStyle.minuteSecondMinS:
        return _minuteSecond(totalSeconds, 'min', 's');
      case LiveCountdownTextStyle.minuteSecondMinSlashS:
        return _minuteSecond(totalSeconds, 'min/', 's');
      case LiveCountdownTextStyle.minuteOnlyCn:
        return '${_minutesFloor(totalSeconds)}分钟';
      case LiveCountdownTextStyle.minuteOnlyMin:
        return '${_minutesFloor(totalSeconds)}min';
      case LiveCountdownTextStyle.minuteOnlySlash:
        return '${_minutesFloor(totalSeconds)}/min';
      case LiveCountdownTextStyle.secondOnlyCn:
        return '$totalSeconds秒';
      case LiveCountdownTextStyle.secondOnlyShort:
        // 相邻字面量拼接：'59s'，避免 's' 并入标识符触发插值花括号 lint。
        return '$totalSeconds' 's';
      case LiveCountdownTextStyle.secondOnlySlash:
        return '$totalSeconds/s';
      case LiveCountdownTextStyle.smart:
        return _smart(totalSeconds, thresholdSeconds, '分钟', '秒');
    }
  }

  String _smart(
    int totalSeconds,
    int thresholdSeconds,
    String minuteSuffix,
    String secondSuffix,
  ) {
    if (totalSeconds <= thresholdSeconds) {
      return '$totalSeconds$secondSuffix';
    }
    if (totalSeconds > 120) {
      return '${(totalSeconds ~/ 60).clamp(1, 1 << 30)}$minuteSuffix';
    }
    if (totalSeconds > 60) {
      return '${((totalSeconds + 59) ~/ 60).clamp(1, 1 << 30)}$minuteSuffix';
    }
    return '$totalSeconds$secondSuffix';
  }

  String _minuteSecond(int totalSeconds, String minuteSuffix, String secondSuffix) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0 && seconds > 0) {
      return '$minutes$minuteSuffix$seconds$secondSuffix';
    }
    if (minutes > 0) {
      // Kotlin 对 min/ 变体去掉尾部斜杠。
      final trimmed = minuteSuffix.endsWith('/')
          ? minuteSuffix.substring(0, minuteSuffix.length - 1)
          : minuteSuffix;
      return '$minutes$trimmed';
    }
    return '$seconds$secondSuffix';
  }

  int _minutesFloor(int totalSeconds) => (totalSeconds ~/ 60).clamp(1, 1 << 30);
}

// --- Mock widgets（HyperOS 超级岛观感，深色、与主题无关） --------------------

/// 摘要态胶囊（单行）：中间摄像头，左侧阶段图标位，右侧文本
/// （上课前＝分钟数，上课中 / 下课为空）。
class _IslandCapsule extends StatelessWidget {
  const _IslandCapsule({required this.iconSlot, required this.criticalText});

  /// 摄像头左侧的图标位（通知 smallIcon，随阶段切换）。
  final Widget iconSlot;

  /// 摄像头右侧的文本（islandCriticalText）。
  final String criticalText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _LiveIslandPreviewCardState._pillColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 4, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: iconSlot,
              ),
            ),
          ),
          const _CameraHole(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 13, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: criticalText.isEmpty
                    ? const SizedBox.shrink()
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          criticalText,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 居中前置摄像头开孔。
class _CameraHole extends StatelessWidget {
  const _CameraHole();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF08090B),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Center(
        child: Container(
          width: 11,
          height: 11,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF191B20),
          ),
        ),
      ),
    );
  }
}
