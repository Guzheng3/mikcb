
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/models/course.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh'));

  Course build({
    required List<int>? customWeeks,
    bool isOddWeek = false,
    bool isEvenWeek = false,
    int startWeek = 1,
    int endWeek = 16,
  }) {
    return Course(
      id: 'c',
      name: '测试课',
      teacher: '老师',
      location: 'A101',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      startTime: '08:00',
      endTime: '09:40',
      startWeek: startWeek,
      endWeek: endWeek,
      isOddWeek: isOddWeek,
      isEvenWeek: isEvenWeek,
      customWeeks: customWeeks,
    );
  }

  test('双周展开序列折叠为「第2-16周 双周」', () {
    final course = build(customWeeks: [2, 4, 6, 8, 10, 12, 14, 16]);
    expect(course.weekDescription(l10n), '第2-16周 双周');
  });

  test('单周展开序列折叠为「第1-7周 单周」', () {
    final course = build(customWeeks: [1, 3, 5, 7]);
    expect(course.weekDescription(l10n), '第1-7周 单周');
  });

  test('中南民大「9-16周 双」形态折叠为「第10-16周 双周」', () {
    expect(build(customWeeks: [10, 12, 14, 16]).weekDescription(l10n), '第10-16周 双周');
  });

  test('中南民大真实形态：1-16 周双周（2、4、…、16）', () {
    final course = build(customWeeks: [2, 4, 6, 8, 10, 12, 14, 16]);
    final text = course.weekDescription(l10n);
    expect(text, contains('双周'));
    expect(text, isNot(contains('、')));
  });

  test('不足四项的奇偶序列保持列表形式', () {
    expect(build(customWeeks: [2, 4]).weekDescription(l10n), '第2、4周');
    expect(build(customWeeks: [2]).weekDescription(l10n), '第2周');
    expect(build(customWeeks: [2, 4, 6]).weekDescription(l10n), '第2、4、6周');
  });

  test('非等差数列（含连续周）不折叠，仍走区间压缩', () {
    expect(
      build(customWeeks: [1, 2, 3, 5, 7, 8, 9]).weekDescription(l10n),
      '第1-3、5、7-9周',
    );
    expect(build(customWeeks: [2, 4, 6, 9]).weekDescription(l10n), '第2、4、6、9周');
  });

  test('无自定义周时沿用单双周标记路径', () {
    expect(build(customWeeks: null, isEvenWeek: true).weekDescription(l10n), '第1-16周 双周');
    expect(build(customWeeks: null, isOddWeek: true).weekDescription(l10n), '第1-16周 单周');
    expect(build(customWeeks: null).weekDescription(l10n), '第1-16周');
  });
}
