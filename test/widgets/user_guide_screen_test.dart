import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/screens/user_guide_screen.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';
import 'package:university_timetable/services/storage_service.dart';
import '../helpers_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const liveChannel = MethodChannel('vip.qinghan.withu/miui_live');

  setUp(() {
    StorageService().resetForTesting();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, (call) async {
          switch (call.method) {
            case 'checkPromotedSupport':
              return {
                'androidVersion': 15,
                'hasNotificationPermission': true,
                'hasPromotedPermission': true,
                'canPostPromoted': true,
              };
            case 'checkNotificationPermission':
            case 'isIgnoringBatteryOptimizations':
            case 'isAutoStartEnabled':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, null);
  });

  Finder startButton() => find.text('开始使用').last;

  testWidgets('single-page guide shows permission checklist, no pager', (
    tester,
  ) async {
    await tester.pumpWidget(const TestApp(home: UserGuideScreen()));
    await tester.pumpAndSettle();

    // 单页引导：直接渲染权限清单，无分页进度、无隐私勾选。
    expect(find.text('系统权限设置'), findsOneWidget);
    expect(find.text('自启动'), findsOneWidget);
    expect(find.textContaining('已就绪'), findsOneWidget);
    expect(find.text('已开启'), findsNWidgets(2));
    expect(find.text('系统已允许'), findsOneWidget);
    expect(find.text('无限制'), findsOneWidget);
    // 无障碍保活项已移除，权限页不再有处于「未开启」状态的条目。
    expect(find.text('未开启'), findsNothing);

    expect(find.text('1 / 5'), findsNothing);
    expect(find.byType(HyperosCheckboxTile), findsNothing);
    expect(find.text('下一步'), findsNothing);
    expect(find.text('上一步'), findsNothing);
    expect(startButton(), findsOneWidget);
    expect(find.text('退出应用'), findsNothing);
    expect(find.text('我已阅读并同意上述隐私说明'), findsNothing);
  });

  testWidgets('collapsible header keeps guide content gap stable', (
    tester,
  ) async {
    await tester.pumpWidget(const TestApp(home: UserGuideScreen()));
    await tester.pumpAndSettle();

    RenderBox headerBox() =>
        tester
                .element(find.byType(HyperosCollapsibleTopAppBar))
                .findRenderObject()
            as RenderBox;
    RenderBox firstGroupBox() =>
        tester.element(find.byType(HyperosListGroup).first).findRenderObject()
            as RenderBox;
    double gap() {
      final header = headerBox();
      final group = firstGroupBox();
      return group.localToGlobal(Offset.zero).dy -
          (header.localToGlobal(Offset.zero).dy + header.size.height);
    }

    // 绝对间隙依赖头部实测高度（大标题字高在测试字体 Ahem 下被放大），
    // 不跨环境恒定；真正的回归点是滚动全程间隙不抖动。
    final list = find.byType(ListView).first;
    final baseline = gap();

    await tester.drag(list, const Offset(0, -38));
    await tester.pumpAndSettle();
    expect(gap(), closeTo(baseline, 0.5));

    await tester.drag(list, const Offset(0, 38));
    await tester.pumpAndSettle();
    expect(gap(), closeTo(baseline, 0.5));

    await tester.drag(list, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(gap(), closeTo(baseline, 0.5));
  });
}
