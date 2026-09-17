import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../models/timetable_settings.dart';
import '../services/bundled_assets.dart';
import '../utils/hex_color.dart';

/// 实时活动摘要态胶囊预览（ColorOS 流体云）。
///
/// 只预览**上课前**这一档：提升通知已限定为仅 `beforeClass` 上岛（见原生
/// `liveShouldPromoteStage`），课中与下课提醒只剩普通通知，没有胶囊可预览。
///
/// 还原真机摘要态胶囊的单行左右分区：中间是摄像头开孔；左侧是通知 smallIcon
/// 的图标位（上课前为时钟）；右侧是到上课的分钟数（`12分钟`，分钟粒度，
/// 不逐秒刷新）。
///
/// 有一档不在这里预览：课前最后 5 秒右侧改成「开始上课」（见原生
/// `liveShouldShowClassStartingPrompt`）。本预览锚定在开课前约 12 分钟，
/// 只画常态那一档。
///
/// 这条规则对应原生 `LiveUpdateService.buildColorosIslandText()`，**只对 ColorOS
/// 生效**：左侧图标槽实测是约 50px 的圆形位、放不下文字，右侧可用宽度只有
/// 6–7 个字，秒级倒计时还会让胶囊随数字位数不断变宽变窄（用户可见的「长度一直
/// 在跳」），所以 ColorOS 的胶囊一律给分钟粒度或固定短文案，课名/地点/秒级倒计时
/// 全部交给下拉通知。
///
/// ColorOS 上胶囊与下拉是两个互不干扰的面：胶囊只读 `buildColorosIslandText`
/// 这一行，下拉读完整字段。因此「显示内容」那组开关（课程名 / 简称 / 地点 /
/// 倒计时样式 / 阶段文字 / 前缀）在 ColorOS 上不影响胶囊，只作用于展开卡片与
/// 普通通知。
///
/// 注意：小米 / 原生 Android 16 的胶囊**不适用**这条短文案规则，仍按原生
/// `islandCriticalText` 的其它分支拼装（会带上课名与地点，受上面那组开关影响），
/// 故本预览只对应 ColorOS 的观感。
///
/// 「小米岛左侧文字图标」只在小米系生效（原生 `resolveIslandLabelBitmap()` 对非
/// 小米系直接返回 null，本机画的是 `ic_upcoming`），所以本预览也只在
/// [isXiaomiFamilyDevice] 为真时才按该开关绘制左图——否则 ColorOS / 原生
/// Android 16 上会展示一个真机不存在的样式。
///
/// 注意：原生参数里的 progressInfo（环形进度）/ progressTextInfo 服务于点开
/// 后的展开态卡片（由系统渲染），摘要态胶囊没有它；本预览只模拟摘要态，
/// 因此不画环与节点条。
class LiveIslandPreviewCard extends StatefulWidget {
  const LiveIslandPreviewCard({
    super.key,
    required this.display,
    this.isXiaomiFamilyDevice = false,
  });

  final LiveDisplaySettings display;

  /// 本机是否小米系设备。由调用方注入，让本组件保持无 I/O 的纯展示，
  /// 也便于测试覆盖两种品牌下的渲染差异。
  final bool isXiaomiFamilyDevice;

  @override
  State<LiveIslandPreviewCard> createState() => _LiveIslandPreviewCardState();
}

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IslandCapsule(
          iconSlot: _buildSmallIcon(l10n, d),
          criticalText: _criticalText(),
        ),
      ],
    );
  }

  // --- Left icon slot (notification small-icon position) ------------------

  Widget _buildSmallIcon(AppLocalizations l10n, LiveDisplaySettings d) {
    // 左图（小米岛左侧文字图标）只在小米系生效：原生 resolveIslandLabelBitmap()
    // 对非小米系直接返回 null，本机画的是 ic_upcoming。预览必须用同一判据，
    // 否则 ColorOS / 原生 Android 16 上会展示一个真机上不存在的样式。
    if (d.enableMiuiIslandLabelImage && widget.isXiaomiFamilyDevice) {
      return _buildIslandLabel(l10n, d);
    }
    // 原生 setSmallIcon：beforeClass=ic_upcoming（时钟），白色模板图标；
    // 流体云与超级岛都会把它画在摄像头左侧。
    return const SizedBox.square(
      dimension: 28,
      child: Icon(Icons.access_time, size: 24, color: Colors.white),
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

  /// 与原生 `buildColorosIslandText` 同一规则：上课前 = 到上课的分钟数
  /// （分钟粒度，避免逐秒刷新导致胶囊宽度抖动）。最后 5 秒的那一档见类注释。
  String _criticalText() {
    return _formatDuration(
      _beforeWindow.start.difference(DateTime.now()),
      LiveCountdownTextStyle.minuteOnlyCn,
      60,
    );
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

/// 摘要态胶囊（单行）：中间摄像头，左侧阶段图标位，右侧到上课的分钟数。
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
