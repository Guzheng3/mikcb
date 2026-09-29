import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/providers/withu_couple_session_provider.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';
import 'package:university_timetable/widgets/home_menu_catalog.dart';
import 'package:university_timetable/widgets/home_top_menu.dart';

import '../helpers_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home action menu renders resolved entries as Miuix list rows '
      'without per-row blur', (tester) async {
    final anchorKey = GlobalKey();
    final entries = resolveHomeMenuEntries();

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

    // 默认排列固定 6 项，任务清单不在其中。
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
    final entries = resolveHomeMenuEntries();

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
      ..debugSetStatus(WithuCoupleLoginStatus.connected)
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
      ..debugSetStatus(WithuCoupleLoginStatus.staleOffline)
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
      ..debugSetStatus(WithuCoupleLoginStatus.connected)
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

  testWidgets('menu anchors its single popup with legibility fill', (
    tester,
  ) async {
    final anchorKey = GlobalKey();
    const gaussianAppearance = FrostedAppearance(
      sheetBlurSigma: 15,
      sheetTintAlpha: 0.7,
      sheetBarrierAlpha: 0.2,
    );

    await tester.pumpWidget(
      TestApp(
        home: FrostedAppearanceScope(
          appearance: gaussianAppearance,
          // Keep the appearance scope above this nested navigator so the
          // dialog route can resolve the same glass settings as the
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
                      entries: resolveHomeMenuEntries(),
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

    // 锚定弹窗只拥有一个玻璃面（跟随当前玻璃模式统一材质），
    // 列表移动时不逐行加模糊。
    expect(find.byType(HyperosSelectPopupGlass), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
