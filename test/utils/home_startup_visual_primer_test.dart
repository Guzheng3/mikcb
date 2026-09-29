import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/utils/home_page_background.dart';
import 'package:university_timetable/utils/home_page_backdrop_image_store.dart';
import 'package:university_timetable/utils/home_startup_visual_primer.dart';

void main() {
  group('HomeStartupVisualPrimer.prime', () {
    testWidgets('warms the bundled default wallpaper into the image cache', (
      tester,
    ) async {
      PaintingBinding.instance.imageCache.clear();
      final settings = TimetableSettings.defaults();

      await tester.runAsync(() => HomeStartupVisualPrimer.prime(settings));

      expect(
        resolveHomePageBackdropImagePath(settings),
        startsWith('asset://'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: homePageBackdropImageWidget(settings: settings)),
        ),
      );
      await tester.pump();

      final path = resolveHomePageBackdropImagePath(settings);
      expect(HomePageBackdropImageStore.instance.imageFor(path), isNotNull);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        find.descendant(
          of: find.byType(Image),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });

    test('无壁纸路径时立即返回且不产生种子亮度带', () async {
      await HomeStartupVisualPrimer.prime(TimetableSettings.defaults());
      expect(HomeStartupVisualPrimer.seededBandsFor(null), isNull);
      expect(HomeStartupVisualPrimer.seededBandsFor('/any/path.png'), isNull);
    });

    test('壁纸文件不存在时立即返回且不产生种子亮度带', () async {
      const missing = r'C:\__definitely_missing_wallpaper__.png';
      await HomeStartupVisualPrimer.prime(
        TimetableSettings.defaults().copyWith(homePageWallpaperPath: missing),
      );
      expect(HomeStartupVisualPrimer.seededBandsFor(missing), isNull);
    });

    test('seededBandsFor 仅对预热时的同一路径返回采样带', () {
      const bands = (top: 0.1, weekday: 0.2, body: 0.3);
      HomeStartupVisualPrimer.debugSeedBands('/w.png', bands);

      expect(HomeStartupVisualPrimer.seededBandsFor('/w.png'), bands);
      expect(HomeStartupVisualPrimer.seededBandsFor('/other.png'), isNull);
      expect(HomeStartupVisualPrimer.seededBandsFor(null), isNull);
    });
  });
}
