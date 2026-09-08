import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/screens/timetable_screen.dart';
import 'package:university_timetable/screens/timetable_profiles_screen.dart';
import 'package:university_timetable/services/storage_service.dart';
import 'package:university_timetable/services/withu_couple_auth_service.dart';
import 'package:university_timetable/services/withu_couple_session_store.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';
import '../helpers_test_app.dart';

Future<void> _pumpTimetableFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// 内存版安全存储：预置 withU 凭证，让会话恢复走 MockClient 的 bootstrap。
class _FakeSecureStorage extends WithuCoupleSecureStorage {
  _FakeSecureStorage(Map<String, String> initial) : _values = initial;

  final Map<String, String> _values;

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}

/// 预置 withU 登录态的会话 Provider：bootstrap 返回双方昵称（小明/小红）。
WithuCoupleSessionProvider createLoggedInTestSession() {
  final authService = WithuCoupleAuthService(
    client: MockClient((request) async {
      // 中文昵称必须走 UTF-8 字节（http.Response(String) 默认 Latin-1）。
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'success': true,
            'logged_in': true,
            'user': {
              'id': 1,
              'username': 'me',
              'nickname': '小明',
              'role': 'user1',
            },
            'partner': {
              'id': 2,
              'username': 'her',
              'nickname': '小红',
              'role': 'user2',
            },
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
    sessionStore: WithuCoupleSessionStore(
      storage: _FakeSecureStorage(_seededSessionValues()),
    ),
  );
  return WithuCoupleSessionProvider(authService: authService);
}

Map<String, String> _seededSessionValues() => {
  'withu_couple_username': 'me',
  'withu_couple_phpsessid': 'session-id',
  'withu_couple_csrf_token': 'csrf-token',
};

void _seedInitializedPrefs() {
  final now = DateTime(2026, 4, 12);
  // These tests cover the classic profile switcher.
  final settings = TimetableSettings.defaults().copyWith(
    coupleTimetableOverlayEnabled: false,
  );
  final profile = TimetableProfile(
    id: 'profile-1',
    name: '默认课表',
    courses: const [],
    settings: settings,
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
    // 情侣标题登录态恢复会读 withU 配置；预置合法 baseUrl。
    'withu_couple_config_v1': jsonEncode({
      'baseUrl': 'https://withu.example.com',
    }),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const homeWidgetChannel = MethodChannel('com.mutx163.qingyu/home_widget');
  const analyticsChannel = MethodChannel('com.mutx163.qingyu/umeng_analytics');
  const liveChannel = MethodChannel('com.mutx163.qingyu/miui_live');

  setUp(() {
    StorageService().resetForTesting();
    _seedInitializedPrefs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidgetChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidgetChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(analyticsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(liveChannel, null);
  });

  testWidgets('home screen can quick switch profiles from title trigger', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);
    final defaultProfileId = provider.activeProfileId!;
    await runRealAsync(tester, () async {
      await provider.createProfile(name: '秋季课表');
    });
    await runRealAsync(tester, () async {
      await provider.switchProfile(defaultProfileId);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const TestApp(home: TimetableScreen(enableProgressTimer: false)),
      ),
    );
    await _pumpTimetableFrame(tester);

    expect(
      find.byKey(const ValueKey('profile_switcher_trigger')),
      findsOneWidget,
    );
    expect(find.text('轻屿课表'), findsOneWidget);
    expect(find.text('默认课表'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('profile_switcher_trigger')));
    await _pumpTimetableFrame(tester);

    expect(find.text('切换课表'), findsOneWidget);
    expect(find.text('秋季课表'), findsOneWidget);

    await tester.tap(find.text('秋季课表'));
    await runRealAsync(tester, () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await _pumpTimetableFrame(tester);

    expect(provider.activeProfile?.name, '秋季课表');
    expect(find.text('秋季课表'), findsNothing);
  });

  testWidgets('brand title style shows active profile name on home', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);
    await runRealAsync(tester, () async {
      await provider.updateTimetableSettings(
        provider.settings.copyWith(homeTitleStyle: HomeTitleStyle.brand),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const TestApp(home: TimetableScreen(enableProgressTimer: false)),
      ),
    );
    await _pumpTimetableFrame(tester);

    expect(
      find.byKey(const ValueKey('profile_switcher_trigger')),
      findsOneWidget,
    );
    expect(find.text('默认课表'), findsOneWidget);
  });

  testWidgets('logged-in couple session shows nickname heart nickname title', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);
    await runRealAsync(tester, () async {
      await provider.updateTimetableSettings(
        provider.settings.copyWith(coupleTimetableOverlayEnabled: true),
      );
    });
    final sessionProvider = createLoggedInTestSession();
    await runRealAsync(tester, sessionProvider.restoreSession);
    expect(sessionProvider.isLoggedIn, isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: TestApp(
          sessionProvider: sessionProvider,
          home: const TimetableScreen(enableProgressTimer: false),
        ),
      ),
    );
    await _pumpTimetableFrame(tester);

    expect(
      find.byKey(const ValueKey('profile_switcher_trigger')),
      findsOneWidget,
    );
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final heartCenter = tester.getCenter(find.byIcon(Icons.favorite_rounded));
    expect(heartCenter.dx, closeTo(screenWidth / 2, 0.5));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('小红'), findsOneWidget);
    expect(find.byKey(const ValueKey('withu_couple_login_chip')), findsNothing);
  });

  testWidgets('home overflow menu omits timetable management entry', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const TestApp(home: TimetableScreen(enableProgressTimer: false)),
      ),
    );
    await _pumpTimetableFrame(tester);

    // ⋮ 菜单由设置分流：默认 list=锚定小弹窗，grid=八宫格底部弹层。
    // 本用例校验溢出菜单不含课表管理（课表管理在标题切换器里），
    // 为可断言固定八宫格，显式切到 grid 并注入 v2.0.5.5 默认全排列。
    await runRealAsync(tester, () async {
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          homeMenuStyle: HomeMenuStyle.grid,
          homeGridMenuActions: List<String>.of(HomeGridMenu.defaultActions),
        ),
      );
    });

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await _pumpTimetableFrame(tester);

    // 弹层确已打开（避免下面的 findsNothing 空转通过）。
    expect(find.byType(HyperosSheetFrame), findsOneWidget);
    // 课表管理入口不在 ⋮ 弹层中，而在标题切换器里（见下方用例）。
    expect(find.text('课表管理'), findsNothing);
    expect(find.text('课程总览'), findsOneWidget);
  });

  testWidgets('profile switch sheet can open timetable management screen', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const TestApp(home: TimetableScreen(enableProgressTimer: false)),
      ),
    );
    await _pumpTimetableFrame(tester);

    await tester.tap(find.byKey(const ValueKey('profile_switcher_trigger')));
    await _pumpTimetableFrame(tester);

    await tester.tap(find.text('课表管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TimetableProfilesScreen), findsOneWidget);
  });

  testWidgets('profile actions use transparent dialog rows in frosted sheet', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const TestApp(home: TimetableProfilesScreen()),
      ),
    );
    await _pumpTimetableFrame(tester);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await _pumpTimetableFrame(tester);

    final sheet = find.byType(HyperosSheet);
    final actionTiles = find.descendant(
      of: sheet,
      matching: find.byType(HyperosChoiceTile),
    );

    expect(sheet, findsOneWidget);
    expect(actionTiles, findsWidgets);
    expect(
      tester
          .widgetList<HyperosChoiceTile>(actionTiles)
          .every((tile) => tile.variant == HyperosChoiceVariant.dialog),
      isTrue,
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(HyperosChoiceGroup)),
      findsNothing,
    );
  });

  testWidgets('switching profiles restores each profile timetable view state', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);
    final defaultProfileId = provider.activeProfileId!;

    await runRealAsync(tester, () async {
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          timetableHomeViewMode: TimetableHomeViewMode.day,
          timetableLastViewedDayOfWeek: 3,
        ),
      );
    });
    await runRealAsync(tester, () async {
      await provider.setCurrentWeek(2);
    });

    await runRealAsync(tester, () async {
      await provider.createProfile(name: '周视图课表');
    });
    final weekProfileId = provider.activeProfileId!;
    await runRealAsync(tester, () async {
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          timetableHomeViewMode: TimetableHomeViewMode.week,
        ),
      );
    });

    await runRealAsync(tester, () async {
      await provider.switchProfile(defaultProfileId);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const TestApp(home: TimetableScreen(enableProgressTimer: false)),
      ),
    );
    await _pumpTimetableFrame(tester);

    expect(
      find.byKey(const ValueKey('timetable-day-view-2-3')),
      findsOneWidget,
    );

    await runRealAsync(tester, () async {
      await provider.switchProfile(weekProfileId);
    });
    await _pumpTimetableFrame(tester);

    expect(find.byKey(const ValueKey('timetable-day-view-1-3')), findsNothing);

    await runRealAsync(tester, () async {
      await provider.switchProfile(defaultProfileId);
    });
    await _pumpTimetableFrame(tester);

    expect(
      find.byKey(const ValueKey('timetable-day-view-2-3')),
      findsOneWidget,
    );
  });
}
