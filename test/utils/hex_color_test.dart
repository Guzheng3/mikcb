import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/utils/hex_color.dart';

void main() {
  group('Color parsing', () {
    test('should parse hex colors correctly', () {
      // 常见课程/主题用色的十六进制解析
      final testCases = [
        ('#171717', const Color(0xFF171717)),
        ('#18181B', const Color(0xFF18181B)),
        ('#0F172B', const Color(0xFF0F172B)),
        ('#1447E6', const Color(0xFF1447E6)),
        ('#5EA500', const Color(0xFF5EA500)),
        ('#F54A00', const Color(0xFFF54A00)),
        ('#E7000B', const Color(0xFFE7000B)),
        ('#EC003F', const Color(0xFFEC003F)),
        ('#7F22FE', const Color(0xFF7F22FE)),
        ('#FCC800', const Color(0xFFFCC800)),
      ];

      for (final (hex, expected) in testCases) {
        final result = tryParseHexColor(hex);
        expect(result, equals(expected), reason: 'Failed for $hex');
      }
    });

    test('should return null for invalid hex', () {
      expect(tryParseHexColor(null), isNull);
      expect(tryParseHexColor(''), isNull);
      expect(tryParseHexColor('#'), isNull);
      expect(tryParseHexColor('#12345'), isNull); // 5位
      expect(tryParseHexColor('#1234567'), isNull); // 7位
      expect(tryParseHexColor('invalid'), isNull);
    });

    test('should use fallback for invalid hex', () {
      const fallback = Color(0xFF2563EB);
      expect(parseHexColorOrFallback(null, fallback: fallback), equals(fallback));
      expect(parseHexColorOrFallback('', fallback: fallback), equals(fallback));
      expect(parseHexColorOrFallback('#12345', fallback: fallback), equals(fallback));
    });
  });
}
