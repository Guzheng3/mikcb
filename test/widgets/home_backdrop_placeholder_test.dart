import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/utils/home_page_background.dart';

Future<File> _writeWallpaper(Directory dir) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 100, 100),
    Paint()..color = const Color(0xFF333333),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${dir.path}/wallpaper.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

void main() {
  testWidgets(
    'backdrop shows splash-colored background before the image decodes',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('mikcb_backdrop_');
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Temp cleanup is best-effort.
        }
      });
      final wallpaper = await tester.runAsync(() => _writeWallpaper(dir));
      final settings = TimetableSettings.defaults().copyWith(
        homePageWallpaperPath: wallpaper!.path,
      );

      await tester.binding.setSurfaceSize(const Size(200, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          themeMode: ThemeMode.dark,
          darkTheme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: homePageBackdropImageWidget(settings: settings)!,
          ),
        ),
      );
      await tester.pump();

      final placeholder = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(Image),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(placeholder.color, const Color(0xFF121212));
    },
  );
}
