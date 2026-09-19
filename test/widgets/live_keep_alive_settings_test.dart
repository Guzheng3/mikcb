import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/screens/live_settings_subpages.dart';
import '../helpers_test_app.dart';

/// ColorOS 一系（OPPO / realme / 一加）会在应用退到后台后冻结整个进程，通知里的
/// 倒计时随之停在最后一帧 —— 只在这一档，保活页要给出「耗电管理 → 允许完全后台
/// 行为」的指引。这组测试锁住「ColorOS 上出现、其它品牌不出现」这条约定，以及
/// 入口真的把用户送去系统设置页。
const MethodChannel _liveChannel = MethodChannel('vip.qinghan.withu/miui_live');

int _openSettingsCalls = 0;

void _mockNative(WidgetTester tester, {required bool isColorOs}) {
  _openSettingsCalls = 0;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _liveChannel,
    (call) async {
      switch (call.method) {
        case 'isColorOsFamilyDevice':
          return isColorOs;
        case 'openBackgroundRestrictionSettings':
          _openSettingsCalls++;
          return true;
      }
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

Future<void> _pumpKeepAlive(WidgetTester tester, {required bool isColorOs}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  _seedInitializedPrefs();
  _mockNative(tester, isColorOs: isColorOs);
  final provider = await createInitializedTestProvider(tester);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: const TestApp(home: LiveKeepAliveSettingsScreen()),
    ),
  );
  // 品牌查询异步回来后再推一帧，让指引按结果重建。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('ColorOS：保活页给出「允许完全后台行为」的指引', (tester) async {
    await _pumpKeepAlive(tester, isColorOs: true);

    expect(find.text('系统后台限制'), findsOneWidget);
    expect(find.text('打开耗电管理'), findsOneWidget);

    await tester.ensureVisible(find.text('打开耗电管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开耗电管理'));
    await tester.pump();

    expect(_openSettingsCalls, 1);
  });

  testWidgets('非 ColorOS：不显示该指引', (tester) async {
    await _pumpKeepAlive(tester, isColorOs: false);

    expect(find.text('系统后台限制'), findsNothing);
    expect(find.text('打开耗电管理'), findsNothing);
  });
}
