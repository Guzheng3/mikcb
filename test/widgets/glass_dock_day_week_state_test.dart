import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers_test_app.dart';

void _seedInitializedPrefs() {
  final now = DateTime(2026, 4, 12);
  final profile = TimetableProfile(
    id: 'profile-1',
    name: '默认课表',
    courses: const [],
    settings: TimetableSettings.defaults().copyWith(
      homeNavigationForm: HomeNavigationForm.glassDock,
    ),
    currentWeek: 5,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    StorageService().resetForTesting();
    _seedInitializedPrefs();
  });

  testWidgets('glass dock: closing day view keeps the visible week', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TimetableProvider>.value(value: provider),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
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
    await tester.pump(const Duration(milliseconds: 400));

    final today = DateTime.now().weekday;
    final week5Header = find.byKey(ValueKey('weekday-header-5-$today'));
    expect(week5Header, findsOneWidget);

    await tester.tap(find.text('日课表').last);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('timetable-day-view-panel')),
      findsOneWidget,
    );

    await tester.tap(find.text('周课表').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(week5Header, findsOneWidget);
    expect(provider.currentWeek, 5);
  });

  testWidgets('glass dock: back button keeps the visible week', (tester) async {
    final provider = await createInitializedTestProvider(tester);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TimetableProvider>.value(value: provider),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
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
    await tester.pump(const Duration(milliseconds: 400));

    final today = DateTime.now().weekday;
    final week5Header = find.byKey(ValueKey('weekday-header-5-$today'));
    expect(week5Header, findsOneWidget);

    tester.widget<GlassTabBar>(find.byType(GlassTabBar)).onTabSelected(0);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('timetable-day-view-panel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('back-to-week-view-button')));
    await _pumpTimetableFrame(tester);

    expect(week5Header, findsOneWidget);
    expect(provider.currentWeek, 5);
  });

  testWidgets('glass dock: pending week settle survives day close', (
    tester,
  ) async {
    final provider = await createInitializedTestProvider(tester);
    await runRealAsync(tester, () async {
      await provider.updateTimetableSettings(
        provider.settings.copyWith(
          homeNavigationForm: HomeNavigationForm.glassDock,
          semesterStartDate: DateTime(2026, 8, 31),
          semesterWeekCount: 20,
        ),
      );
    });
    await runRealAsync(tester, () async {
      await provider.setCurrentWeek(1);
    });

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
    await tester.pump(const Duration(milliseconds: 400));

    await tester.drag(
      find.byKey(const ValueKey('week-page-view')),
      const Offset(-900, 0),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('日课表').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const ValueKey('timetable-day-view-panel')),
      findsOneWidget,
    );

    tester.widget<GlassTabBar>(find.byType(GlassTabBar)).onTabSelected(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final today = DateTime.now().weekday;
    expect(find.byKey(ValueKey('weekday-header-2-$today')), findsOneWidget);
    expect(provider.currentWeek, 2);
  });
}

Future<void> _pumpTimetableFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
