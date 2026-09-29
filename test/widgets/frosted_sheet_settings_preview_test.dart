import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/ui/hyperos/hyperos_blurred_header.dart';
import 'package:university_timetable/widgets/frosted_sheet_settings_preview.dart';
import 'package:university_timetable/widgets/home_page_region_blur.dart';

import '../helpers_test_app.dart';

/// 1x1 transparent PNG — a real decodable file for the wallpaper backdrop.
const _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
];

const _savedAppearance = FrostedAppearance(
  sheetBlurSigma: 15,
  sheetTintAlpha: 0.7,
  sheetBarrierAlpha: 0.2,
);

void main() {
  group('demo sheet rendering', () {
    testWidgets('renders the demo tiles without throwing', (tester) async {
      const appearance = FrostedAppearance(
          sheetBlurSigma: 15,
          sheetTintAlpha: 0.7,
          sheetBarrierAlpha: 0.2,
        );

        await tester.pumpWidget(
        const TestApp(
            home: FrostedAppearanceScope(
              appearance: appearance,
            child: FrostedSheetSettingsDemoSheet(),
            ),
          ),
        );
        await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('课程统计'), findsOneWidget);
      expect(find.text('课表设置'), findsOneWidget);
      expect(find.text('导入课程'), findsOneWidget);
      });

    testWidgets(
      'demo route keeps the draft appearance across the navigator boundary',
      (tester) async {
        const savedAppearance = _savedAppearance;
        const draftAppearance = FrostedAppearance(
          sheetBlurSigma: 15,
          sheetTintAlpha: 0.7,
          sheetBarrierAlpha: 0.2,
        );

        await tester.pumpWidget(
          TestApp(
            home: FrostedAppearanceScope(
              appearance: savedAppearance,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (context) => FrostedAppearanceScope(
                    appearance: draftAppearance,
                    child: Builder(
                      builder: (context) => ElevatedButton(
                        onPressed: () => showFrostedSheetSettingsDemo(context),
                        child: const Text('Open demo'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open demo'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('课程统计'), findsOneWidget);
        expect(find.text('课表设置'), findsOneWidget);
        expect(find.text('导入课程'), findsOneWidget);
      },
    );
  });

  group('grouped backdrop sampling for the chrome band', () {
    testWidgets(
      'preview band renders inside a BackdropGroup over the wallpaper '
      'capture',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('mikcb_preview_');
        final wallpaper = File('${dir.path}/wallpaper.png')
          ..writeAsBytesSync(_tinyPng);
        addTearDown(() {
          // Release the FileImage handle before deleting the temp dir
          // (Windows may hold it open past the last frame; a failed delete
          // is fine — the OS temp dir is swept anyway).
          PaintingBinding.instance.imageCache.clear();
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // ignored
          }
        });

        SharedPreferences.setMockInitialValues({});
        final settings = TimetableSettings(
          sections: const [
            SectionTime(startTime: '08:00', endTime: '08:45'),
            SectionTime(startTime: '08:55', endTime: '09:40'),
            SectionTime(startTime: '10:00', endTime: '10:45'),
            SectionTime(startTime: '10:55', endTime: '11:40'),
            SectionTime(startTime: '14:00', endTime: '14:45'),
          ],
          homePageWallpaperPath: wallpaper.path,
          homePageHeaderBlurEnabled: true,
          homePageWeekdayBarBlurEnabled: true,
        );
        final provider = await createInitializedTestProvider(tester);

        await tester.pumpWidget(
          TestApp(
            home: FrostedSheetSettingsPreview(
              provider: provider,
              settings: settings,
              week: 1,
              blurSigma: 15,
              tintAlpha: 0.5,
              barrierAlpha: 0.2,
              blurEnabled: true,
              onOpenDemoSheet: () {},
            ),
          ),
        );
        // Let the wallpaper file decode and the luminance sample settle.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();

        expect(find.byType(BackdropGroup), findsOneWidget);
        expect(find.byType(UndimmedBackdropCapture), findsOneWidget);
        expect(find.byType(HomePageChromeGlassFill), findsOneWidget);
      },
    );
  });
}
