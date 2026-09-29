import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/timetable_profile.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/services/storage_service.dart';
import 'package:university_timetable/ui/hyperos/frosted/frosted_appearance.dart';

import 'package:university_timetable/widgets/home_page_region_blur.dart';
import 'package:university_timetable/widgets/timetable_week_preview.dart';

import '../helpers_test_app.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    StorageService().resetForTesting();
    _seedInitializedPrefs();
  });

  Future<void> pumpPreview(
    WidgetTester tester, {
    required TimetableSettings settings,
    bool? applyHomePageBackdrop,
  }) async {
    final provider = await createInitializedTestProvider(tester);
    await tester.pumpWidget(
      TestApp(
        home: FrostedAppearanceScope(
          appearance: FrostedAppearance(
            sheetBlurSigma: settings.frostedSheetBlurSigma,
            sheetTintAlpha: settings.frostedSheetTintAlpha,
            sheetBarrierAlpha: settings.frostedSheetBarrierAlpha,
            blurEnabled: settings.frostedBlurEnabled,
          ),
          child: SizedBox(
            width: 360,
            height: 320,
            child: TimetableWeekPreview(
              provider: provider,
              settings: settings,
              week: provider.currentWeek,
              maxVisibleSections: 4,
              applyHomePageBackdrop: applyHomePageBackdrop ?? true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('applyHomePageBackdrop defaults to true', (tester) async {
    // Regression guard: the settings previews rely on the default to show the
    // wallpaper. Two of them used to render flat because no caller passed it.
    final provider = await createInitializedTestProvider(tester);
    final preview = TimetableWeekPreview(
      provider: provider,
      settings: TimetableSettings.defaults(),
      week: 1,
    );
    expect(preview.applyHomePageBackdrop, isTrue);
  });

  // 回归护栏：窄带玻璃条保持底边与可见带同边界，顶部/左右越界以藏掉
  // 上缘发丝缝与侧边接缝（不再有按带高比例封顶的厚度参数）。
  group('chrome glass band narrow strip keeps edge geometry', () {
    Future<File> writeOpaqueWallpaper() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1000000, 1000000),
        Paint()..color = const Color(0xFF6688AA),
      );
      final image = await recorder.endRecording().toImage(16, 16);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = await Directory.systemTemp.createTemp('weekbar_glass_test');
      return File('${dir.path}/wall.png')
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    testWidgets('isolated weekday strip overdraws edges and keeps bottom '
        'boundary', (tester) async {
      final wallpaper = (await tester.runAsync(writeOpaqueWallpaper))!;
      await pumpPreview(
        tester,
        settings: TimetableSettings.defaults().copyWith(
          homePageWallpaperPath: wallpaper.path,
          homePageWeekdayBarBlurEnabled: true,
        ),
      );

      expect(find.byType(HomePageChromeGlassFill), findsOneWidget);
      // 底边仍与可见带同边界（首页同款细窄包边），顶部/左右仍越界以
      // 藏掉上缘发丝缝与侧边接缝。
      final glassRect = tester.getRect(find.byType(HomePageChromeGlassFill));
      final previewRect = tester.getRect(find.byType(TimetableWeekPreview));
      const headerHeight = 40.0;
      expect(
        glassRect.top,
        lessThan(previewRect.top),
        reason: 'top still overdrawn to hide hairline seam',
      );
      expect(
        glassRect.bottom,
        closeTo(previewRect.top + headerHeight, 0.5),
        reason: 'bottom stays at band boundary for thin sheen',
      );
    });
  });
}
