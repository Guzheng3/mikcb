import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';
import 'package:university_timetable/ui/hyperos/liquid/hyperos_liquid_glass_surface.dart';
import 'package:university_timetable/widgets/home_menu_catalog.dart';
import 'package:university_timetable/widgets/home_top_menu.dart';

import '../helpers_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home action menu renders resolved entries as Miuix list rows '
      'without per-row blur', (tester) async {
    final anchorKey = GlobalKey();
    final entries = resolveHomeGridMenuEntries(TimetableSettings.defaults());

    await tester.pumpWidget(
      TestApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  showHomeTopMenuSheet(
                    context,
                    entries: entries,
                    anchorKey: anchorKey,
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 与八宫格共享同一份自定义排列（默认 6 项，任务清单不在其中）。
    // The anchored popup owns exactly one glass surface — no row adds its
    // own blur while the list moves.
    expect(find.byType(HyperosPressableRow), findsNWidgets(6));
    expect(find.byType(HyperosSelectPopupGlass), findsOneWidget);
    expect(tester.getSize(find.byType(HyperosSelectPopupGlass)).width, 131.4);
    final rowHeights = tester
        .widgetList<HyperosPressableRow>(find.byType(HyperosPressableRow))
        .map((row) => tester.getSize(find.byWidget(row)).height)
        .toList();
    expect(rowHeights, List<double>.filled(6, 43.8));
    expect(
      find.byKey(const ValueKey('hyperos_list_popup_divider')),
      findsNWidgets(5),
    );

    for (final title in const [
      '课程总览',
      '课程统计',
      '添加课程',
      '考试安排',
      '导入课程',
      '课表设置',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('任务清单'), findsNothing);
  });

  testWidgets('home action menu rows remain tappable', (tester) async {
    final anchorKey = GlobalKey();
    late Future<String?> menuResult;
    final entries = resolveHomeGridMenuEntries(TimetableSettings.defaults());

    await tester.pumpWidget(
      TestApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  menuResult = showHomeTopMenuSheet(
                    context,
                    entries: entries,
                    anchorKey: anchorKey,
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('课程总览'));
    await tester.pumpAndSettle();

    expect(await menuResult, 'overview');
  });

  testWidgets('logged-in couple login menu row shows paired avatars', (
    tester,
  ) async {
    final anchorKey = GlobalKey();
    late Future<String?> menuResult;
    final sessionProvider = WithuCoupleSessionProvider()
      ..isLoggedIn = true
      ..serverBaseUrl = 'https://withu.example.com'
      ..userAvatarPath = 'cached-me.png'
      ..partnerAvatarPath = 'cached-partner.svg';
    final entries = [
      coupleLoginHomeMenuEntry,
      HomeMenuEntry(
        id: 'overview',
        title: (_) => 'Overview',
        icon: Icons.dashboard_rounded,
        category: HomeMenuEntryCategory.features,
        open: (_) async {},
      ),
    ];

    await tester.pumpWidget(
      TestApp(
        sessionProvider: sessionProvider,
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  menuResult = showHomeTopMenuSheet(
                    context,
                    entries: entries,
                    anchorKey: anchorKey,
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('withu_couple_login_menu_avatar')),
      findsOneWidget,
    );
    final avatarRowHeights = tester
        .widgetList<HyperosPressableRow>(find.byType(HyperosPressableRow))
        .map((row) => tester.getSize(find.byWidget(row)).height)
        .toList();
    expect(avatarRowHeights, const [56.0, 43.8]);
    expect(
      find.byKey(const ValueKey('hyperos_list_popup_divider')),
      findsOneWidget,
    );
    expect(find.text('账号登录'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('withu_couple_login_menu_avatar')),
    );
    await tester.pumpAndSettle();

    expect(await menuResult, 'withuCoupleLogin');
  });

  testWidgets('stored couple session menu row shows paired avatars', (
    tester,
  ) async {
    final anchorKey = GlobalKey();
    final sessionProvider = WithuCoupleSessionProvider()
      ..hasStoredSession = true
      ..serverBaseUrl = 'https://withu.example.com'
      ..userAvatarPath = 'cached-me.png'
      ..partnerAvatarPath = 'cached-partner.svg';
    final entries = [
      coupleLoginHomeMenuEntry,
      HomeMenuEntry(
        id: 'overview',
        title: (_) => 'Overview',
        icon: Icons.dashboard_rounded,
        category: HomeMenuEntryCategory.features,
        open: (_) async {},
      ),
    ];

    await tester.pumpWidget(
      TestApp(
        sessionProvider: sessionProvider,
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  showHomeTopMenuSheet(
                    context,
                    entries: entries,
                    anchorKey: anchorKey,
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('withu_couple_login_menu_avatar')),
      findsOneWidget,
    );
    expect(find.text('\u8d26\u53f7\u767b\u5f55'), findsNothing);
  });

  testWidgets('logged-in couple menu action opens the couple center', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final timetableProvider = await createInitializedTestProvider(tester);
    final sessionProvider = WithuCoupleSessionProvider()
      ..isLoggedIn = true
      ..userNickname = 'Ming'
      ..partnerNickname = 'Xiao';

    await tester.pumpWidget(
      TestApp(
        sessionProvider: sessionProvider,
        home: ChangeNotifierProvider<TimetableProvider>.value(
          value: timetableProvider,
          child: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => coupleLoginHomeMenuEntry.open(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('情侣中心'), findsOneWidget);
    expect(find.text('立即同步课表'), findsOneWidget);
    expect(find.text('账号登录'), findsNothing);
  });

  testWidgets('logged-out couple menu action opens the login sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final timetableProvider = await createInitializedTestProvider(tester);
    final sessionProvider = WithuCoupleSessionProvider();

    await tester.pumpWidget(
      TestApp(
        sessionProvider: sessionProvider,
        home: ChangeNotifierProvider<TimetableProvider>.value(
          value: timetableProvider,
          child: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => coupleLoginHomeMenuEntry.open(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('账号登录'), findsOneWidget);
    expect(find.text('情侣中心'), findsNothing);
  });

  testWidgets('home action menu uses fixed width with centered labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final anchorKey = GlobalKey();
    final entries = [
      HomeMenuEntry(
        id: 'overview',
        title: (_) => 'Overview',
        icon: Icons.dashboard_rounded,
        category: HomeMenuEntryCategory.features,
        open: (_) async {},
      ),
    ];

    await tester.pumpWidget(
      TestApp(
        home: Builder(
          builder: (context) {
            return Align(
              alignment: Alignment.topRight,
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  showHomeTopMenuSheet(
                    context,
                    entries: entries,
                    anchorKey: anchorKey,
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(HyperosSelectPopupGlass), findsOneWidget);

    final popupBox = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(HyperosSelectPopupGlass),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    final popupSize = tester.getSize(find.byType(HyperosSelectPopupGlass));
    expect(popupBox.constraints.minWidth, 131.4);
    expect(popupBox.constraints.maxWidth, 131.4);
    expect(popupSize.width, 131.4);
    expect(
      tester.widget<Text>(find.text('Overview')).textAlign,
      TextAlign.center,
    );
  });

  testWidgets(
    'home action menu honors custom order and groups rows by category',
    (tester) async {
      final anchorKey = GlobalKey();
      late Future<String?> menuResult;
      final entries = resolveHomeGridMenuEntries(
        TimetableSettings.defaults().copyWith(
          // copyWith 会钉住 settings，这里断言的是自定义排列顺序本身；
          // tasks(courseRecolor 属 features) → settings(preferences)
          // 的分类交界处应插一个分组间隔。
          homeGridMenuActions: ['tasks', 'courseRecolor', 'settings'],
        ),
      );

      await tester.pumpWidget(
        TestApp(
          home: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  key: anchorKey,
                  onPressed: () {
                    menuResult = showHomeTopMenuSheet(
                      context,
                      entries: entries,
                      anchorKey: anchorKey,
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // 只渲染用户选择的入口，顺序与持久化一致。
      expect(find.text('任务清单'), findsOneWidget);
      expect(find.text('课表重新配色'), findsOneWidget);
      expect(find.text('课表设置'), findsOneWidget);

      await tester.tap(find.text('任务清单'));
      await tester.pumpAndSettle();

      expect(await menuResult, 'tasks');
    },
  );

  testWidgets('liquid menu anchors its single popup with legibility fill', (
    tester,
  ) async {
    final anchorKey = GlobalKey();
    const liquidAppearance = FrostedAppearance(
      sheetBlurSigma: 15,
      sheetTintAlpha: 0.7,
      sheetBarrierAlpha: 0.2,
      glassMode: FrostedGlassMode.liquidGlass,
    );

    await tester.pumpWidget(
      TestApp(
        home: FrostedAppearanceScope(
          appearance: liquidAppearance,
          // Keep the appearance scope above this nested navigator so the
          // dialog route can resolve the same liquid-glass settings as the
          // page chrome. The outer TestApp navigator would otherwise place
          // the dialog above this scope.
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: anchorKey,
                  onPressed: () {
                    showHomeTopMenuSheet(
                      context,
                      entries: resolveHomeGridMenuEntries(
                        TimetableSettings.defaults(),
                      ),
                      anchorKey: anchorKey,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final outerGlass = tester.widget<HyperosLiquidGlassSurface>(
      find.byType(HyperosLiquidGlassSurface),
    );
    expect(outerGlass.role, HyperosLiquidGlassRole.modal);
    // 152cd9b4 起弹窗与 Sheet 的液态玻璃不再叠加可读性衬底，保持通透材质
    // 与首页标题/星期栏统一（选择弹窗同为 contentLegibilityFill=false）。
    expect(outerGlass.contentLegibilityFill, isFalse);
    expect(find.byType(HyperosLiquidGlassSurface), findsOneWidget);
  });

  testWidgets('grid menu renders default six tiles without tasks entry', (
    tester,
  ) async {
    final anchorKey = GlobalKey();
    late Future<String?> menuResult;

    await tester.pumpWidget(
      TestApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  menuResult = showHomeTopGridMenuSheet(
                    context,
                    entries: resolveHomeGridMenuEntries(
                      TimetableSettings.defaults(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 默认排列：6 个瓷贴，任务清单不在其中（列表菜单独有）。
    for (final title in const [
      '课程总览',
      '课程统计',
      '添加课程',
      '考试安排',
      '导入课程',
      '课表设置',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('任务清单'), findsNothing);
    expect(find.byIcon(Icons.dashboard_customize_rounded), findsOneWidget);

    await tester.tap(find.text('课程总览'));
    await tester.pumpAndSettle();

    expect(await menuResult, 'overview');
  });

  testWidgets('grid menu honors custom order', (tester) async {
    final anchorKey = GlobalKey();
    late Future<String?> menuResult;

    await tester.pumpWidget(
      TestApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  menuResult = showHomeTopGridMenuSheet(
                    context,
                    entries: resolveHomeGridMenuEntries(
                      TimetableSettings.defaults().copyWith(
                        homeMenuStyle: HomeMenuStyle.grid,
                        // copyWith 会钉住 settings，这里断言的是自定义
                        // 排列顺序本身，settings 在尾部不影响本例。
                        homeGridMenuActions: ['tasks', 'courseRecolor'],
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 自定义排列只渲染用户选择的入口，顺序与持久化一致。
    expect(find.text('任务清单'), findsOneWidget);
    expect(find.text('课表重新配色'), findsOneWidget);

    await tester.tap(find.text('任务清单'));
    await tester.pumpAndSettle();

    expect(await menuResult, 'tasks');
  });

  testWidgets('grid menu tile icons follow the theme seed color', (
    tester,
  ) async {
    final anchorKey = GlobalKey();

    await tester.pumpWidget(
      TestApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: anchorKey,
                onPressed: () {
                  showHomeTopGridMenuSheet(
                    context,
                    entries: resolveHomeGridMenuEntries(
                      TimetableSettings.defaults(),
                    ),
                    themeSeedHex: '#1447E6',
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 可读的主题 seed 直接作为瓷贴图标色（默认蓝）。
    expect(
      tester.widget<Icon>(find.byIcon(Icons.dashboard_customize_rounded)).color,
      const Color(0xFF1447E6),
    );
  });

  testWidgets(
    'grid menu tile icons fall back to chrome ink for unreadable seeds',
    (tester) async {
      final anchorKey = GlobalKey();

      await tester.pumpWidget(
        TestApp(
          home: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  key: anchorKey,
                  onPressed: () {
                    showHomeTopGridMenuSheet(
                      context,
                      entries: resolveHomeGridMenuEntries(
                        TimetableSettings.defaults(),
                      ),
                      // 亮黄在浅色磨砂瓷贴上不可读，回落玻璃墨色。
                      themeSeedHex: '#FCC800',
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final iconContext = tester.element(
        find.byIcon(Icons.dashboard_customize_rounded),
      );
      expect(
        tester
            .widget<Icon>(find.byIcon(Icons.dashboard_customize_rounded))
            .color,
        Theme.of(iconContext).colorScheme.onSurface,
      );
    },
  );
}
