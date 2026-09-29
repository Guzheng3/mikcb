import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/screens/timetable_screen.dart';
import 'package:university_timetable/services/storage_service.dart';
import 'package:university_timetable/ui/hyperos/frosted/frosted_appearance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const homeWidgetChannel = MethodChannel('vip.qinghan.withu/home_widget');
  const analyticsChannel = MethodChannel('vip.qinghan.withu/app_diagnostics');
  const liveChannel = MethodChannel('vip.qinghan.withu/miui_live');
  final defaultProfile = TimetableProfile(
    id: 'profile-1',
    name: '默认课表',
    courses: const [],
    settings: TimetableSettings.defaults(),
    currentWeek: 1,
    createdAt: DateTime(2026, 9, 7),
    lastUsedAt: DateTime(2026, 9, 7),
  );

  setUp(() {
    StorageService().resetForTesting();
    SharedPreferences.setMockInitialValues({
      'timetable_profiles': jsonEncode([defaultProfile.toJson()]),
      'active_timetable_profile_id': defaultProfile.id,
    });
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

  testWidgets(
    'classic auto-fit time axis stays fixed while centered week cards animate',
    (tester) async {
      final provider = TimetableProvider(
        autoInitialize: false,
        enableLiveActivitySync: false,
      );
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          homeNavigationForm: HomeNavigationForm.classic,
          timetableAutoFitSectionHeight: true,
          homePageWallpaperPath: '',
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TimetableProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('zh'),
            home: FrostedAppearanceScope(
              appearance: FrostedAppearance.defaults,
              child: TimetableScreen(enableProgressTimer: false),
            ),
          ),
        ),
      );
      await tester.pump();

      final scrollFinder = find.byKey(
        const PageStorageKey<String>('week-scroll-1'),
      );
      expect(scrollFinder, findsOneWidget);
      final scrollView = tester.widget<SingleChildScrollView>(scrollFinder);
      expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
      final columnFinder = find.byKey(const ValueKey('timetable-time-column'));
      final axisTopBefore = tester.getTopLeft(columnFinder).dy;

      await tester.drag(scrollFinder, const Offset(0, -120));
      await tester.pump();
      final axisTopAfter = tester.getTopLeft(columnFinder).dy;
      expect(axisTopAfter, closeTo(axisTopBefore, 0.5));
      expect(scrollView.controller!.offset, 0);

      final pageViewFinder = find.byKey(const ValueKey('week-page-view'));
      final gesture = await tester.startGesture(
        tester.getCenter(pageViewFinder),
      );
      await gesture.moveBy(const Offset(-64, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-48, 0));
      await tester.pump();

      final viewportCenter = tester.getCenter(pageViewFinder);
      final outgoingDeck = find.byKey(const ValueKey('week-page-1')).last;
      final incomingDeck = find.byKey(const ValueKey('week-page-2')).last;
      // 前向滑动：当前页随手势 1:1 位移（累计 64+48=112），目标页在视口中心原位揭示。
      expect(
        tester.getCenter(outgoingDeck).dx,
        closeTo(viewportCenter.dx - 112, 1.0),
      );
      expect(
        tester.getCenter(incomingDeck).dx,
        closeTo(viewportCenter.dx, 1.0),
      );

      await gesture.up();
      // 观察窗口盖满 0.52s 弹簧的整个回弹过程（48 × 32ms = 1536ms），
      // 否则断言会在弹簧仍在运行时就判定「已稳定」。
      for (var frame = 0; frame < 48; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
        // The deck card, fixed axis, or restored pager axis must cover every
        // settle frame. A missing axis here appears on device as a blink.
        expect(
          find.byKey(const ValueKey('timetable-time-column')),
          findsWidgets,
        );
      }
      final settledMotion = tester.widget<Transform>(
        find.byKey(const ValueKey('timetable-time-column-motion')),
      );
      final settledTranslation = settledMotion.transform.getTranslation();
      expect(settledTranslation.x, closeTo(0, 0.5));
    },
  );

  testWidgets(
    'forward pager reveals a centered card while outgoing stays full scale',
    (tester) async {
      final provider = TimetableProvider(
        autoInitialize: false,
        enableLiveActivitySync: false,
      );
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          homeNavigationForm: HomeNavigationForm.classic,
          timetableAutoFitSectionHeight: true,
          homePageWallpaperPath: '',
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TimetableProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('zh'),
            home: FrostedAppearanceScope(
              appearance: FrostedAppearance.defaults,
              child: TimetableScreen(enableProgressTimer: false),
            ),
          ),
        ),
      );
      await tester.pump();

      final pageViewFinder = find.byKey(const ValueKey('week-page-view'));
      final viewportCenter = tester.getCenter(pageViewFinder);
      final gesture = await tester.startGesture(viewportCenter);
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();

      final outgoing = find.byKey(const ValueKey('week-page-1')).last;
      final incoming = find.byKey(const ValueKey('week-page-2')).last;
      expect(outgoing, findsOneWidget);
      expect(incoming, findsOneWidget);
      // 前向滑动：当前页随手势位移 400，目标页在中心原位揭示。
      expect(
        tester.getCenter(outgoing).dx,
        closeTo(viewportCenter.dx - 400, 1.0),
      );
      expect(tester.getCenter(incoming).dx, closeTo(viewportCenter.dx, 1.0));
      final viewportSize = tester.getRect(pageViewFinder).size;
      final outgoingSize = tester.getRect(outgoing).size;
      final incomingSize = tester.getRect(incoming).size;
      expect(outgoingSize.width / viewportSize.width, closeTo(1.0, 0.02));
      expect(outgoingSize.height / viewportSize.height, closeTo(1.0, 0.02));
      expect(incomingSize.width / viewportSize.width, greaterThan(0.86));
      expect(incomingSize.height / viewportSize.height, greaterThan(0.86));
      expect(incomingSize.width / viewportSize.width, lessThan(0.96));
      expect(incomingSize.height / viewportSize.height, lessThan(0.96));

      await gesture.up();
      for (var frame = 0; frame < 48; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(of: incoming, matching: find.byType(Opacity)),
            )
            .every((opacity) => opacity.opacity == 1.0),
        isTrue,
      );
      // Settle shuts the deck down: the real pager card must render without
      // the transition filter (no lingering ghost of the old week).
      expect(
        find.ancestor(of: incoming, matching: find.byType(ImageFiltered)),
        findsNothing,
      );
      expect(
        tester.getRect(incoming).width / viewportSize.width,
        closeTo(1.0, 0.02),
      );
    },
  );

  testWidgets(
    'fast follow-up swipe keeps the settle motion and follows the finger',
    (tester) async {
      final provider = TimetableProvider(
        autoInitialize: false,
        enableLiveActivitySync: false,
      );
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          homeNavigationForm: HomeNavigationForm.classic,
          timetableAutoFitSectionHeight: true,
          homePageWallpaperPath: '',
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TimetableProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('zh'),
            home: FrostedAppearanceScope(
              appearance: FrostedAppearance.defaults,
              child: TimetableScreen(enableProgressTimer: false),
            ),
          ),
        ),
      );
      await tester.pump();

      final pageViewFinder = find.byKey(const ValueKey('week-page-view'));
      final controller = tester.widget<PageView>(pageViewFinder).controller!;
      final pageUnit = tester.getRect(pageViewFinder).width;
      final viewportCenter = tester.getCenter(pageViewFinder);
      final first = await tester.startGesture(viewportCenter);
      await first.moveBy(const Offset(-200, 0));
      await tester.pump();
      await first.up();
      // 弹簧：第一帧只对齐 ticker 起算时间，第二帧才开始位移。
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      expect(controller.page, lessThan(1.0));

      // 让弹簧走到半页附近（速度仍可观）新手指再按下：这是「连续滑动」的
      // 典型时机，也是旧的纯 1:1 实现里接手即冻结的场景。
      for (var frame = 0; frame < 48 && controller.page! < 0.45; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final pendingPage = controller.page!;
      expect(pendingPage, greaterThan(0.44));

      // 上一次滑动还没落定就被新手指按下：弹簧被拖拽接管，位置冻在接手那一帧
      // （补速曲线要等第一帧真实拖拽位移才起跑，规避 DragScrollActivity 的
      // lastDetails 断言）。
      final second = await tester.startGesture(viewportCenter);
      await tester.pump(const Duration(milliseconds: 32));
      expect(controller.page, closeTo(pendingPage, 0.0001));

      // 首帧真实拖拽：手指走 30px 页面就走 30px（补速首帧只对齐 ticker 起算）。
      final beforeMove = controller.page!;
      await second.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(controller.page! - beforeMove, closeTo(30 / pageUnit, 0.003));

      // 手指按住不动的 192ms 里，剩余行程按弹簧自己的速度继续补完（速度连续）：
      // 位置仍在明显前进——「连着上一张的动作继续，不要暂停」——但没有火箭式
      // 一步到位。
      final afterMove = controller.page!;
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(controller.page! - afterMove, greaterThan(12 / pageUnit));
      // 补完停在整页前半像素（保持分数页，deck 不交回），不精确落页。
      expect(controller.page, lessThan(1.0));

      // 手指不抬，继续滑过整页：deck 锚点推进，切换连续到下一页；抬手后落在
      // 再下一整页（snap 基准已随锚点推进，而不是 round 回刚跨过的这一页）。
      await second.moveBy(Offset(-pageUnit * 0.45, 0));
      await tester.pump();
      await second.up();
      for (var frame = 0; frame < 48; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(controller.page, closeTo(2.0, 0.001));
    },
  );

  testWidgets(
    'backward pager recedes outgoing while left neighbor stays centered',
    (tester) async {
      final provider = TimetableProvider(
        autoInitialize: false,
        enableLiveActivitySync: false,
      );
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          homeNavigationForm: HomeNavigationForm.classic,
          timetableAutoFitSectionHeight: true,
          homePageWallpaperPath: '',
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TimetableProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('zh'),
            home: FrostedAppearanceScope(
              appearance: FrostedAppearance.defaults,
              child: TimetableScreen(enableProgressTimer: false),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final pageViewFinder = find.byKey(const ValueKey('week-page-view'));
      tester.widget<PageView>(pageViewFinder).controller!.jumpToPage(1);
      await tester.pump();
      final viewportCenter = tester.getCenter(pageViewFinder);
      final gesture = await tester.startGesture(viewportCenter);
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump(const Duration(milliseconds: 16));

      final outgoing = find.byKey(const ValueKey('week-page-2')).last;
      final incoming = find.byKey(const ValueKey('week-page-1')).last;
      expect(outgoing, findsOneWidget);
      expect(incoming, findsOneWidget);
      expect(tester.getCenter(outgoing).dx, closeTo(viewportCenter.dx, 1.0));
      // 仅当前页保持居中；后向滑动时左邻页按 pager 位移（-页宽 + 手势 200）。
      expect(
        tester.getCenter(incoming).dx,
        closeTo(
          viewportCenter.dx - tester.getRect(pageViewFinder).size.width + 200,
          1.0,
        ),
      );
      final viewportSize = tester.getRect(pageViewFinder).size;
      final outgoingSize = tester.getRect(outgoing).size;
      final incomingSize = tester.getRect(incoming).size;
      expect(outgoingSize.width / viewportSize.width, closeTo(0.967, 0.03));
      expect(outgoingSize.height / viewportSize.height, closeTo(0.967, 0.03));
      // 后向滑动时左邻页缩小到 ~0.87 并随 pager 位移（当前页保持居中全尺寸）。
      expect(incomingSize.width / viewportSize.width, closeTo(0.87, 0.03));
      expect(incomingSize.height / viewportSize.height, closeTo(0.87, 0.03));

      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      // 手势仅 200px（<页宽一半），释放后 pager 回弹到当前页，
      // 左邻页保持缩放态而非放大到满宽。
      expect(
        tester.getRect(incoming).width / viewportSize.width,
        closeTo(0.87, 0.03),
      );
    },
  );
}
