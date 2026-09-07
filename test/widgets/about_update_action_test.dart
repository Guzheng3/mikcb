import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/screens/about_screen.dart';

void main() {
  test('Android with a download URL uses in-app download', () {
    expect(
      resolveAboutUpdatePrimaryAction(
        isAndroid: true,
        downloadUrl: 'https://withu.example.com/uploads/app.apk',
      ),
      AboutUpdatePrimaryAction.downloadInApp,
    );
  });

  test('non-Android opens the direct download link', () {
    expect(
      resolveAboutUpdatePrimaryAction(
        isAndroid: false,
        downloadUrl: 'https://withu.example.com/uploads/app.apk',
      ),
      AboutUpdatePrimaryAction.openDownloadLink,
    );
  });

  test('missing download URL falls back to the release page', () {
    expect(
      resolveAboutUpdatePrimaryAction(isAndroid: true, downloadUrl: null),
      AboutUpdatePrimaryAction.openReleasePage,
    );
  });
}
