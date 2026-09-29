import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/utils/course_color_palette.dart';
import 'package:university_timetable/utils/hex_color.dart';

void main() {
  group('kPresetCourseColorHexes', () {
    test('数量达到 100，手动调色盘可选范围足够大', () {
      expect(kPresetCourseColorHexes.length, greaterThanOrEqualTo(100));
    });

    test('全部是合法 6 位大写 hex 且可解析', () {
      final pattern = RegExp(r'^#[0-9A-F]{6}$');
      for (final hex in kPresetCourseColorHexes) {
        expect(pattern.hasMatch(hex), isTrue, reason: '非法色值: $hex');
        expect(tryParseHexColor(hex), isNotNull, reason: '解析失败: $hex');
      }
    });

    test('无重复色值（大小写不敏感）', () {
      final seen = <String>{};
      for (final hex in kPresetCourseColorHexes) {
        final key = hex.toUpperCase();
        expect(seen.add(key), isTrue, reason: '重复色值: $hex');
      }
    });

    test('新建课程默认色 #2196F3 仍在预设内', () {
      expect(kPresetCourseColorHexes, contains('#2196F3'));
    });
  });

  group('kCourseColorQuickPickHexes', () {
    test('非空且都是全量色板的子集', () {
      expect(kCourseColorQuickPickHexes, isNotEmpty);
      for (final hex in kCourseColorQuickPickHexes) {
        expect(
          kPresetCourseColorHexes,
          contains(hex),
          reason: '快捷色 $hex 不在全量色板中',
        );
      }
    });

    test('快捷行首色是默认色 #2196F3（新建课程初值显示为预设而非自定义）', () {
      expect(kCourseColorQuickPickHexes.first, '#2196F3');
    });

    test('无重复色值', () {
      expect(
        kCourseColorQuickPickHexes.map((hex) => hex.toUpperCase()).toSet(),
        hasLength(kCourseColorQuickPickHexes.length),
      );
    });
  });

  group('kRandomCourseColorHexes（随机配色唯一色板）', () {
    test('恰好 30 色，全部合法可解析且无重复', () {
      expect(kRandomCourseColorHexes, hasLength(30));
      final pattern = RegExp(r'^#[0-9A-F]{6}$');
      final seen = <String>{};
      for (final hex in kRandomCourseColorHexes) {
        expect(pattern.hasMatch(hex), isTrue, reason: '非法色值: $hex');
        expect(tryParseHexColor(hex), isNotNull, reason: '解析失败: $hex');
        expect(seen.add(hex.toUpperCase()), isTrue, reason: '重复色值: $hex');
      }
    });

    test('全部 ⊆ 手动调色盘全量色板（随机抽到的色都能手动再现）', () {
      final fullPalette = kPresetCourseColorHexes
          .map((hex) => hex.toUpperCase())
          .toSet();
      for (final hex in kRandomCourseColorHexes) {
          expect(
            fullPalette,
          contains(hex.toUpperCase()),
          reason: '$hex 不在全量色板中',
          );
        }
    });

    test('不含灰黑中性色（随机抽到的色都带明显色相）', () {
      for (final hex in kRandomCourseColorHexes) {
      expect(
          courseCardInkIsNeutral(tryParseHexColor(hex)!),
          isFalse,
          reason: '$hex 是灰黑中性色',
      );
        }
      });

    test('每色按最佳黑白墨对比度 ≥ 3:1（随机导入后守卫必能配出可读墨色）', () {
      for (final hex in kRandomCourseColorHexes) {
          final card = tryParseHexColor(hex)!;
          expect(
          courseCardContrastRatio(bestContrastCourseCardInk(card), card),
            greaterThanOrEqualTo(3.0),
          reason: '$hex 黑白墨均不可读',
          );
        }
      });
    });

  group('bestContrastCourseCardInk', () {
    test('浅色底回落近黑墨，深色底回落白墨（预览与实心卡隐身线回落同款）', () {
      expect(
        bestContrastCourseCardInk(const Color(0xFFFDE047)), // yellow-300
        const Color(0xFF1A1A1A),
      );
      expect(
        bestContrastCourseCardInk(const Color(0xFF1D4ED8)), // blue-700
        const Color(0xFFFFFFFF),
      );
    });
  });
}
