import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/utils/home_page_background.dart';
import 'package:university_timetable/utils/home_page_backdrop_image_store.dart';
import 'package:university_timetable/utils/home_startup_visual_primer.dart';
import 'package:university_timetable/widgets/preblurred_wallpaper_glass.dart';

void main() {
  group('resolveHomePreblurSigma', () {
    test('高斯课程卡优先决定 sigma', () {
      expect(
        resolveHomePreblurSigma(
          gaussianCardsDrive: true,
          liquidGlassChrome: true,
          sheetBlurSigma: 15,
          liquidGlassTunedBlur: 8,
        ),
        15,
      );
    });

    test('液态玻璃 chrome 使用调校值并夹紧到 2-24', () {
      expect(
        resolveHomePreblurSigma(
          gaussianCardsDrive: false,
          liquidGlassChrome: true,
          sheetBlurSigma: 15,
          liquidGlassTunedBlur: 0.5,
        ),
        2.0,
      );
      expect(
        resolveHomePreblurSigma(
          gaussianCardsDrive: false,
          liquidGlassChrome: true,
          sheetBlurSigma: 15,
          liquidGlassTunedBlur: 99,
        ),
        24.0,
      );
    });

    test('无高斯卡且非液态玻璃时回退 sheet sigma', () {
      expect(
        resolveHomePreblurSigma(
          gaussianCardsDrive: false,
          liquidGlassChrome: false,
          sheetBlurSigma: 12,
          liquidGlassTunedBlur: null,
        ),
        12,
      );
      // 液态玻璃但无调校值：同样回退 sheet sigma（与首页内联逻辑一致）。
      expect(
        resolveHomePreblurSigma(
          gaussianCardsDrive: false,
          liquidGlassChrome: true,
          sheetBlurSigma: 9,
          liquidGlassTunedBlur: null,
        ),
        9,
      );
    });
  });

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
