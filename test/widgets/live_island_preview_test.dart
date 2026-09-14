import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/widgets/live_island_preview.dart';

/// 实时活动摘要态胶囊预览与原生 ColorOS 分支的一致性测试。
///
/// 摘要态胶囊按阶段分发内容（与 `LiveUpdateService.buildColorosIslandText()` 一致）：
/// * 上课前 = 左侧时钟图标 + 右侧分钟数（分钟粒度，不逐秒刷新）；
/// * 上课中 = 左侧书图标 + 右侧「上课中」；
/// * 下课   = 左侧对勾图标 + 右侧「即将下课」。
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
    bool forDuringEnd = false,
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
            forDuringEnd: forDuringEnd,
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

  testWidgets('课中与下课岛：右侧分别是「上课中」与「即将下课」', (tester) async {
    await pumpPreview(
      tester,
      displayConfig: display(),
      forDuringEnd: true,
    );

    // 「上课中」既是阶段小标题也是课中胶囊文字，故出现两次
    expect(find.text('上课中'), findsNWidgets(2));
    expect(find.text('下课提醒'), findsOneWidget);
    expect(find.text('即将下课'), findsOneWidget);

    // 左侧图标分别对应 ic_course（书）与 ic_countdown（对勾）
    expect(find.byIcon(Icons.import_contacts), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    // 胶囊里不再有倒计时 / 课名 / 地点
    expect(textMatching(RegExp(r'\d+分钟')), findsNothing);
    expect(find.textContaining('高等数学'), findsNothing);
    expect(find.textContaining('三教-401'), findsNothing);
  });

  testWidgets('开启自定义标签：左侧渲染标签文字，右侧仍是分钟数', (tester) async {
    await pumpPreview(
      tester,
      displayConfig: display(
        enableMiuiIslandLabelImage: true,
        miuiIslandLabelContent: MiuiIslandLabelContent.courseName,
      ),
    );

    expect(find.text('高等数学'), findsOneWidget,
        reason: '左侧图标位显示自定义标签（纯文字样式）');
    expect(find.byIcon(Icons.access_time), findsNothing,
        reason: '开启自定义标签后不再画阶段图标');
    expect(textMatching(RegExp(r'^\d+分钟$')), findsOneWidget);
  });
}
