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
  const analyticsChannel = MethodChannel('vip.qinghan.withu/umeng_analytics');
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
      expect(
        tester.getCenter(outgoingDeck).dx,
        closeTo(viewportCenter.dx, 1.0),
      );
      expect(
        tester.getCenter(incomingDeck).dx,
        closeTo(viewportCenter.dx, 1.0),
      );

      await gesture.up();
      for (var frame = 0; frame < 24; frame++) {
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
      expect(tester.getCenter(outgoing).dx, closeTo(viewportCenter.dx, 1.0));
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
      for (var frame = 0; frame < 24; frame++) {
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

  testWidgets('fast follow-up swipe retargets the deck start page', (
    tester,
  ) async {
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
    final first = await tester.startGesture(viewportCenter);
    await first.moveBy(const Offset(-760, 0));
    await tester.pump();
    await first.up();

    // Start the next swipe before the first spring settles. The deck must
    // rebase on the fractional landing page, not keep the original page 0.
    final second = await tester.startGesture(viewportCenter);
    await second.moveBy(const Offset(-80, 0));
    await tester.pump();

    expect(find.byKey(const ValueKey('week-page-3')).last, findsOneWidget);
    await second.up();
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
  });

  testWidgets('backward pager recedes outgoing while left neighbor stays centered', (
    tester,
  ) async {
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
    expect(tester.getCenter(incoming).dx, closeTo(viewportCenter.dx, 1.0));
    final viewportSize = tester.getRect(pageViewFinder).size;
    final outgoingSize = tester.getRect(outgoing).size;
    final incomingSize = tester.getRect(incoming).size;
    expect(outgoingSize.width / viewportSize.width, closeTo(0.967, 0.03));
    expect(outgoingSize.height / viewportSize.height, closeTo(0.967, 0.03));
    expect(incomingSize.width / viewportSize.width, closeTo(1.0, 0.02));
    expect(incomingSize.height / viewportSize.height, closeTo(1.0, 0.02));

    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.getRect(incoming).width / viewportSize.width,
      closeTo(1.0, 0.02),
    );
  });
}
