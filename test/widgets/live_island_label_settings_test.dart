import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/screens/live_settings_subpages.dart';
import 'package:university_timetable/screens/timetable_settings_screen.dart';
import '../helpers_test_app.dart';

/// 岛左侧文字图标 / 展开态图标只对小米系生效：原生 `resolveIslandLabelBitmap()`
/// 与 `applyExpandedLargeIcon()` 对非小米系直接返回，所以设置入口也只在小米系
/// 出现。这组测试锁住「ColorOS 上不显示、小米上可配置」这条产品约定。
const MethodChannel _liveChannel = MethodChannel('vip.qinghan.withu/miui_live');

void _mockBrand(WidgetTester tester, {required bool isXiaomi}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _liveChannel,
    (call) async {
      if (call.method == 'isXiaomiFamilyDevice') return isXiaomi;
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _liveChannel,
      null,
    );
  });
}

/// Provider 初始化会读 SharedPreferences，测试里必须先塞好 mock 值。
void _seedInitializedPrefs() {
  final now = DateTime(2026, 4, 12);
  final profile = TimetableProfile(
    id: 'profile-1',
    name: '默认课表',
    courses: const [],
    settings: TimetableSettings.defaults(),
    currentWeek: 1,
    createdAt: now,
    lastUsedAt: now,
  );
  SharedPreferences.setMockInitialValues({
    'did_migrate_app_logs_default': true,
    'did_migrate_live_hide_prefix_default': true,
    'timetable_profiles': jsonEncode([profile.toJson()]),
    'active_timetable_profile_id': profile.id,
    'time_schemes': '[]',
  });
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  _seedInitializedPrefs();
  final provider = await createInitializedTestProvider(tester);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(value: provider, child: TestApp(home: home)),
  );
  // 品牌查询是异步回来的，多推一帧让入口按结果重建。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('小米系：提醒设置页出现「左侧图标与展开态」入口', (tester) async {
    _mockBrand(tester, isXiaomi: true);
    await _pump(tester, createLiveSettingsScreen());

    expect(find.text('左侧图标与展开态'), findsWidgets,
        reason: '小米系应能看到该入口');
  });

  testWidgets('非小米系（ColorOS / 原生 Android 16）：不出现该入口', (tester) async {
    _mockBrand(tester, isXiaomi: false);
    await _pump(tester, createLiveSettingsScreen());

    expect(find.text('左侧图标与展开态'), findsNothing,
        reason: '非小米系上这几项原生侧直接返回，入口不该露出');
  });

  testWidgets('子页可渲染：开关与展开态图标都在', (tester) async {
    _mockBrand(tester, isXiaomi: true);
    await _pump(tester, const LiveIslandLabelSettingsScreen());

    expect(find.text('左侧图标与展开态'), findsWidgets,
        reason: '页面标题（也复用同一文案）');
    expect(find.text('小米岛左侧文字图标'), findsOneWidget,
        reason: '左图总开关');
    expect(find.text('展开态大图标'), findsWidgets,
        reason: '展开态图标那张卡片');
  });

  testWidgets('左图关闭时不展开内容/样式子项', (tester) async {
    _mockBrand(tester, isXiaomi: true);
    await _pump(tester, const LiveIslandLabelSettingsScreen());

    // enableMiuiIslandLabelImage 默认关闭，样式子项应随之为隐藏。
    expect(find.text('左侧文字内容'), findsNothing);
    expect(find.text('左侧图标样式'), findsNothing);
  });
}
