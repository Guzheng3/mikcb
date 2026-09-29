import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/utils/course_color_palette.dart';
import 'package:university_timetable/utils/import_random_course_colors.dart';

Course _sampleCourse({
  required String id,
  required String name,
  String teacher = '',
  String color = '#2196F3',
}) {
  return Course(
    id: id,
    name: name,
    teacher: teacher,
    location: 'A101',
    dayOfWeek: 1,
    startSection: 1,
    endSection: 2,
    startTime: '08:00',
    endTime: '09:40',
    color: color,
  );
}

void main() {
  group('applyRandomImportCourseColors', () {
    test('returns empty list for empty input', () {
      expect(applyRandomImportCourseColors(const []), isEmpty);
    });

    test('same name and teacher share one color', () {
      final colored = applyRandomImportCourseColors([
        _sampleCourse(id: '1', name: '高等数学', teacher: '张三', color: '#111111'),
        _sampleCourse(id: '2', name: '高等数学', teacher: '张三', color: '#222222'),
        _sampleCourse(id: '3', name: '线性代数', teacher: '李四', color: '#333333'),
      ], random: Random(42));

      expect(colored[0].color, colored[1].color);
      expect(colored[0].color, isNot(colored[2].color));
      expect(kRandomCourseColorHexes, contains(colored[0].color));
      expect(kRandomCourseColorHexes, contains(colored[2].color));
    });

    test('whitespace in name or teacher is normalized for grouping', () {
      final colored = applyRandomImportCourseColors([
        _sampleCourse(id: '1', name: '  高等数学 ', teacher: '张  三'),
        _sampleCourse(id: '2', name: '高等数学', teacher: '张 三'),
      ], random: Random(7));

      expect(colored[0].color, colored[1].color);
    });

    test('overrides spreadsheet-provided colors', () {
      final colored = applyRandomImportCourseColors([
        _sampleCourse(id: '1', name: 'A', teacher: 'T', color: '#AABBCC'),
      ], random: Random(1));

      expect(colored.single.color, isNot('#AABBCC'));
      expect(kRandomCourseColorHexes, contains(colored.single.color));
    });

    test('uses fixed seed for deterministic palette order', () {
      final first = applyRandomImportCourseColors([
        _sampleCourse(id: '1', name: 'A', teacher: '1'),
        _sampleCourse(id: '2', name: 'B', teacher: '2'),
      ], random: Random(99));
      final second = applyRandomImportCourseColors([
        _sampleCourse(id: '1', name: 'A', teacher: '1'),
        _sampleCourse(id: '2', name: 'B', teacher: '2'),
      ], random: Random(99));

      expect(
        first.map((course) => course.color).toList(),
        second.map((course) => course.color).toList(),
      );
    });
  });

  group('orderPaletteByMaxSeparation', () {
    test('返回同一批色值的排列，不缺不重', () {
      final ordered = orderPaletteByMaxSeparation(
        kRandomCourseColorHexes,
        Random(1),
      );
      expect(ordered, hasLength(kRandomCourseColorHexes.length));
      expect(ordered.toSet(), kRandomCourseColorHexes.toSet());
    });

    test('同一种子顺序逐项一致（种子批次可重放）', () {
      expect(
        orderPaletteByMaxSeparation(kRandomCourseColorHexes, Random(7)),
        orderPaletteByMaxSeparation(kRandomCourseColorHexes, Random(7)),
      );
    });

    test('单色 / 空色板原样返回', () {
      expect(orderPaletteByMaxSeparation(const [], Random(1)), isEmpty);
      expect(orderPaletteByMaxSeparation(const ['#EF4444'], Random(1)), [
        '#EF4444',
      ]);
    });

    /// 用户诉求：「同一次抽取尽量不要抽取颜色相近的」。只与上一个取色比
    /// 不够——greedy 链会把 #A855F7 与 #8B5CF6 这两支几乎同色的紫放在隔
    /// 两位的位置（ΔE≈10）。这里断言整段前 10 色两两拉开，实测最小
    /// ΔE≈25（30 色全量两两最小只有 9）。
    test('前 10 色两两 ΔE ≥ 20，同一次导入不出现近似色', () {
      for (var seed = 0; seed < 30; seed++) {
        final firstTen = orderPaletteByMaxSeparation(
          kRandomCourseColorHexes,
          Random(seed),
        ).take(10).toList();
        for (var i = 0; i < firstTen.length; i++) {
          for (var j = i + 1; j < firstTen.length; j++) {
            final distance = courseColorPerceptualDistance(
              firstTen[i],
              firstTen[j],
            );
            expect(
              distance,
              greaterThanOrEqualTo(20.0),
              reason: 'seed=$seed：${firstTen[i]} 与 ${firstTen[j]} 仅差 $distance',
            );
          }
        }
      }
    });
  });

  group('buildImportCourseColorGroupKey', () {
    test('joins normalized name and teacher', () {
      expect(
        buildImportCourseColorGroupKey(name: ' 高数 ', teacher: ' 张三 '),
        '高数\u0000张三',
      );
    });
  });
}
