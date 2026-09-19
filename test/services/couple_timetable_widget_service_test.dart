import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/services/couple_timetable_widget_service.dart';

void main() {
  // 这些字符串是 Dart 与原生之间的约定：原生 CoupleWidgetStatus.from 按它们解析。
  // 拼错不会报错，只会静默退化成「可用」，卡片变成一张没有课程也没有文案的空卡。
  // 原生侧 CoupleWidgetStatusTest 锁同一份字符串，两端改动必须成对。
  group('CoupleTimetableWidgetStatusX.value', () {
    test('emits the wire strings the native side parses', () {
      expect(CoupleTimetableWidgetStatus.ok.value, 'ok');
      expect(CoupleTimetableWidgetStatus.coupleModeOff.value, 'couple_mode_off');
      expect(CoupleTimetableWidgetStatus.notLoggedIn.value, 'not_logged_in');
      expect(CoupleTimetableWidgetStatus.notBound.value, 'not_bound');
    });

    test('gives every status a distinct wire string', () {
      final wireValues = CoupleTimetableWidgetStatus.values
          .map((status) => status.value)
          .toSet();
      expect(wireValues, hasLength(CoupleTimetableWidgetStatus.values.length));
    });
  });
}
