import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/widgets/live_island_preview.dart';

/// 实时活动摘要态胶囊预览与原生 ColorOS 分支的一致性测试。
///
/// 提升通知已限定为仅上课前上岛（原生 `liveShouldPromoteStage`），课中与下课
/// 提醒只剩普通通知，所以预览只画课前这一档：
/// 左侧时钟图标 + 右侧分钟数（分钟粒度，不逐秒刷新）。
void main() {
  LiveDisplaySettings display({
    bool showCourseName = true,
    bool showLocation = true,
    bool showCountdown = true,
    LiveCountdownTextStyle countdownTextStyle = LiveCountdownTextStyle.smart,
    bool showStageText = true,
    bool useShortName = false,
    bool hidePrefixText = false,
    bool enableMiuiIslandLabelImage = false,
    MiuiIslandLabelStyle miuiIslandLabelStyle = MiuiIslandLabelStyle.textOnly,
    MiuiIslandLabelContent miuiIslandLabelContent =
        MiuiIslandLabelContent.courseNameAndLocation,
  }) {
    return LiveDisplaySettings(
      showCourseName: showCourseName,
      showLocation: showLocation,
      showCountdown: showCountdown,
      countdownTextStyle: countdownTextStyle,
      showStageText: showStageText,
      useShortName: useShortName,
      hidePrefixText: hidePrefixText,
      duringClassTimeDisplayMode: LiveDuringClassTimeDisplayMode.nearest,
      enableMiuiIslandLabelImage: enableMiuiIslandLabelImage,
      miuiIslandLabelStyle: miuiIslandLabelStyle,
      miuiIslandLabelContent: miuiIslandLabelContent,
      miuiIslandLabelFontColor: '#FFFFFF',
      miuiIslandLabelFontWeight: MiuiIslandLabelFontWeight.medium,
      miuiIslandLabelRenderQuality: MiuiIslandLabelRenderQuality.standard,
      miuiIslandLabelFontSize: 12,
      miuiIslandLabelOffsetX: 0,
      miuiIslandLabelOffsetY: 0,
      miuiIslandLabelLogoPath: null,
      miuiIslandLabelLogoCornerRadius: 2,
      miuiIslandExpandedIconMode: MiuiIslandExpandedIconMode.appIcon,
      miuiIslandExpandedIconPath: null,
    );
  }

  Finder textMatching(RegExp pattern) => find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data != null && pattern.hasMatch(widget.data!),
      );

  Future<void> pumpPreview(
    WidgetTester tester, {
    required LiveDisplaySettings displayConfig,
    bool isXiaomiFamilyDevice = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: LiveIslandPreviewCard(
            display: displayConfig,
            isXiaomiFamilyDevice: isXiaomiFamilyDevice,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('课前岛：左侧时钟图标，右侧分钟数', (tester) async {
    await pumpPreview(tester, displayConfig: display());

    expect(find.byIcon(Icons.access_time), findsOneWidget,
        reason: '上课前左侧是 ic_upcoming（时钟）');
    expect(textMatching(RegExp(r'^\d+分钟$')), findsOneWidget,
        reason: '上课前右侧只显示分钟数');
    // 课名 / 地点 / 秒级倒计时都不再进入摘要态胶囊
    expect(find.textContaining('高等数学'), findsNothing);
    expect(find.textContaining('三教-401'), findsNothing);
    expect(find.textContaining('距上课'), findsNothing);
  });

  testWidgets('小米系 + 开启自定义标签：左侧渲染标签文字，右侧仍是分钟数', (tester) async {
    await pumpPreview(
      tester,
      displayConfig: display(
        enableMiuiIslandLabelImage: true,
        miuiIslandLabelContent: MiuiIslandLabelContent.courseName,
      ),
      isXiaomiFamilyDevice: true,
    );

    expect(find.text('高等数学'), findsOneWidget,
        reason: '左侧图标位显示自定义标签（纯文字样式）');
    expect(find.byIcon(Icons.access_time), findsNothing,
        reason: '开启自定义标签后不再画阶段图标');
    expect(textMatching(RegExp(r'^\d+分钟$')), findsOneWidget);
  });

  testWidgets('非小米系（ColorOS / 原生 Android 16）：即使开关打开也只画时钟图标',
      (tester) async {
    await pumpPreview(
      tester,
      displayConfig: display(
        enableMiuiIslandLabelImage: true,
        miuiIslandLabelContent: MiuiIslandLabelContent.courseName,
      ),
      // isXiaomiFamilyDevice 取默认 false，即 ColorOS / 原生 Android 16。
    );

    // 原生 resolveIslandLabelBitmap() 对非小米系返回 null，本机画的是
    // ic_upcoming；预览必须一致，否则展示的是真机上不存在的样式。
    expect(find.text('高等数学'), findsNothing,
        reason: '非小米系不按该开关绘制左图');
    expect(find.byIcon(Icons.access_time), findsOneWidget,
        reason: '非小米系仍是阶段图标（ic_upcoming）');
    expect(textMatching(RegExp(r'^\d+分钟$')), findsOneWidget);
  });
}
