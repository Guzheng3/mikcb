import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/providers/timetable_provider.dart';
import 'package:university_timetable/screens/timetable_screen.dart';
import 'package:university_timetable/ui/hyperos/frosted/frosted_appearance.dart';

void main() {
  testWidgets(
    'classic auto-fit time axis follows course cards and animates week swipes',
    (tester) async {
      final provider = TimetableProvider(autoInitialize: false);
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

      final motion = tester.widget<Transform>(
        find.byKey(const ValueKey('timetable-time-column-motion')),
      );
      final movingTranslation = motion.transform.getTranslation();
      expect(movingTranslation.x, lessThan(-8));

      await gesture.up();
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
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
      final provider = TimetableProvider(autoInitialize: false);
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

      final outgoing = find.byKey(const ValueKey('week-page-1'));
      final incoming = find.byKey(const ValueKey('week-page-2'));
      expect(outgoing, findsOneWidget);
      expect(incoming, findsOneWidget);
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
      expect(incomingSize.width / viewportSize.width, closeTo(0.944, 0.03));
      expect(incomingSize.height / viewportSize.height, closeTo(0.944, 0.03));
      expect(incomingSize.width / viewportSize.width, lessThan(0.96));
      expect(incomingSize.height / viewportSize.height, lessThan(0.96));

      await gesture.up();
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(
        tester.widgetList<Opacity>(
          find.ancestor(of: incoming, matching: find.byType(Opacity)),
        ),
        isEmpty,
      );
      expect(
        find.ancestor(of: incoming, matching: find.byType(ImageFiltered)),
        findsWidgets,
      );
      expect(
        tester.getRect(incoming).width / viewportSize.width,
        closeTo(1.0, 0.02),
      );
    },
  );
}
