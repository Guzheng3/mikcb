import 'app_localizations.dart';
import '../models/course.dart';

String formatCourseWeekList(AppLocalizations l10n, List<int> weeks) {
  if (weeks.isEmpty) {
    return '';
  }
  final ranges = <String>[];
  var rangeStart = weeks.first;
  var previous = weeks.first;

  for (var index = 1; index < weeks.length; index++) {
    final current = weeks[index];
    if (current == previous + 1) {
      previous = current;
      continue;
    }
    ranges.add(
      rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous',
    );
    rangeStart = current;
    previous = current;
  }

  ranges.add(
    rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous',
  );
  return ranges.join(l10n.weekListSeparator);
}

/// 若 [weeks] 是「同奇偶、步长 2、且覆盖区间内全部同奇偶周」的序列（≥4 项），
/// 返回其区间与奇偶性；否则返回 null。
///
/// 用于把导入时被展开成具体周次的双周/单周课（如 [2, 4, 6, …, 16]）
/// 折叠回「第2-16周 双周」，而不是显示成「第2、4、6、…、16周」。
({int start, int end, bool isOdd})? _paritySeries(List<int> weeks) {
  if (weeks.length < 4) {
    return null;
  }
  for (var index = 1; index < weeks.length; index++) {
    if (weeks[index] - weeks[index - 1] != 2) {
      return null;
    }
  }
  final start = weeks.first;
  final end = weeks.last;
  if (start.isOdd != end.isOdd) {
    return null;
  }
  if ((end - start) ~/ 2 + 1 != weeks.length) {
    return null;
  }
  return (start: start, end: end, isOdd: start.isOdd);
}

String courseWeekDescription(AppLocalizations l10n, Course course) {
  final custom = course.normalizedCustomWeeks;
  if (custom != null) {
    final parity = _paritySeries(custom);
    if (parity != null) {
      final mode = parity.isOdd
          ? ' ${l10n.oddWeeksFilter}'
          : ' ${l10n.evenWeeksFilter}';
      return l10n.courseWeekRangeLabel(parity.start, parity.end, mode);
    }
    return l10n.courseWeekListLabel(formatCourseWeekList(l10n, custom));
  }

  final mode = course.isOddWeek
      ? ' ${l10n.oddWeeksFilter}'
      : course.isEvenWeek
      ? ' ${l10n.evenWeeksFilter}'
      : '';
  return l10n.courseWeekRangeLabel(course.startWeek, course.endWeek, mode);
}

String? courseSuspensionDescription(AppLocalizations l10n, Course course) {
  final suspended = course.normalizedSuspendedWeeks;
  if (suspended == null || suspended.isEmpty) {
    return null;
  }
  return l10n.courseWeekSuspendedLabel(
    formatCourseWeekList(l10n, suspended),
  );
}
