import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/models/course.dart';
import 'package:university_timetable/widgets/course_card.dart';

import '../helpers_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('invalid course color does not crash course card', (
    tester,
  ) async {
    final course = Course(
      id: 'course-1',
      name: '高等数学',
      teacher: '张老师',
      location: 'A101',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      startTime: '08:00',
      endTime: '09:40',
      color: 'broken',
    );

    await tester.pumpWidget(TestApp(home: CourseCard(course: course)));

    expect(find.text('高等数学'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('solid card keeps title and description on the same polarity', (
    tester,
  ) async {
    // 回归：白标题在饱和色卡上对比度达标被保留，而黑简介同样达标被保留，
    // 同卡混色；详情墨必须跟随标题墨。
    final course = Course(
      id: 'course-2',
      name: '数据结构',
      teacher: '',
      location: '',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      startTime: '08:00',
      endTime: '09:40',
      color: '#FF9800',
      description: '线性表与树',
    );

    await tester.pumpWidget(
      TestApp(
        home: CourseCard(
          course: course,
          showTeacher: false,
          showLocation: false,
          showDescription: true,
          titleColorHex: '#FFFFFF',
          detailColorHex: '#000000',
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('数据结构'));
    expect(title.style?.color, const Color(0xFFFFFFFF));

    final description = tester.widget<Text>(find.text('线性表与树'));
    final detailInk = description.style!.color!;
    expect(detailInk.r, closeTo(1.0, 0.001)); // 跟随白标题，不再用黑
    expect(detailInk.g, closeTo(1.0, 0.001));
    expect(detailInk.b, closeTo(1.0, 0.001));
    expect(detailInk.a, closeTo(0.7, 0.01));
  });

  testWidgets('solid card keeps an explicitly configured white ink on a pale '
      'card', (tester) async {
    // 回归：设置页「课程字体颜色」统一设成白色时，浅色/粉彩卡底对比度不足
    // 会被自动翻成近黑字，同一套设置下有的卡白字有的卡黑字。用户显式选定的
    // 字色在实心卡上一律原样生效。
    final course = Course(
      id: 'course-4',
      name: '大学物理',
      teacher: '',
      location: '',
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      startTime: '08:00',
      endTime: '09:40',
      color: '#FFCC80',
      description: '力学',
    );

    await tester.pumpWidget(
      TestApp(
        home: CourseCard(
          course: course,
          showTeacher: false,
          showLocation: false,
          showDescription: true,
          titleColorHex: '#FFFFFF',
          detailColorHex: '#FFFFFF',
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('大学物理'));
    expect(title.style?.color, const Color(0xFFFFFFFF));

    final description = tester.widget<Text>(find.text('力学'));
    final detailInk = description.style!.color!;
    expect(detailInk.r, closeTo(1.0, 0.001));
    expect(detailInk.g, closeTo(1.0, 0.001));
    expect(detailInk.b, closeTo(1.0, 0.001));
    expect(detailInk.a, closeTo(0.7, 0.01));
  });
}
