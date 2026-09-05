import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('branding bitmaps are bundled', () async {
    for (final path in [
      'assets/branding/launcher_icon.png',
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(100), reason: path);
    }
  });
}
