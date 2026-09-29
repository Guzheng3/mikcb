import 'dart:math';

import '../models/course.dart';
import 'course_color_palette.dart';

/// Assigns preset colors to imported courses, grouping by name + teacher.
///
/// Same name+teacher share one color. Distinct groups walk [palette] in the
/// order produced by [orderPaletteByMaxSeparation], so neighbouring groups get
/// perceptually distant colors in a single draw.
/// [groupKeyBuilder] overrides the grouping key (e.g. name-only for the
/// post-import recolor, where the app invariant is "same name, same color").
List<Course> applyRandomImportCourseColors(
  List<Course> courses, {
  Random? random,
  List<String> palette = kRandomCourseColorHexes,
  bool assignMatchingTextColor = false,
  String Function(Course course)? groupKeyBuilder,
}) {
  if (courses.isEmpty || palette.isEmpty) {
    return List<Course>.from(courses);
  }

  final resolveGroupKey =
      groupKeyBuilder ??
      (course) => buildImportCourseColorGroupKey(
            name: course.name,
            teacher: course.teacher,
          );
  final randomSource = random ?? Random();
  final orderedPalette = orderPaletteByMaxSeparation(palette, randomSource);

  final groupColorByKey = <String, String>{};
  var nextGroupIndex = 0;

  return courses
      .map((course) {
        final groupKey = resolveGroupKey(course);
        final assignedColor = groupColorByKey.putIfAbsent(groupKey, () {
          final colorHex =
              orderedPalette[nextGroupIndex % orderedPalette.length];
          nextGroupIndex += 1;
          return colorHex;
        });
        return course.copyWith(
          color: assignedColor,
          textColor: assignMatchingTextColor
              ? matchingCourseTextColorHex(assignedColor)
              : null,
        );
      })
      .toList(growable: false);
}

/// Orders [palette] so that each new entry sits as far as possible from
/// *everything already ordered*: a farthest-point traversal (k-center greedy) in
/// CIELAB (ΔE76).
///
/// [applyRandomImportCourseColors] walks the palette in order, one entry per
/// course-name group, so the order *is* the answer to "how different are the
/// cards of one draw". A plain `shuffle` happily puts same-hue steps next to each
/// other (`#22C55E` / `#10B981`), which reads as one flat block across the week.
/// Only comparing against the *previous* pick is not enough either: the greedy
/// chain picks `#A855F7` and then `#8B5CF6` two steps later (ΔE 10), which is the
/// same near-duplicate purple. Taking the minimum distance over the whole chosen
/// set instead keeps the early picks far apart — with [kRandomCourseColorHexes]
/// the first 10 entries are pairwise ≥ 25 ΔE, the first 20 ≥ 14.
///
/// Deterministic for a given [random] seed, so a seed batch replays identically.
/// Palettes longer than the distance model can separate (duplicate hexes) still
/// return every entry: ties resolve by original order.
List<String> orderPaletteByMaxSeparation(List<String> palette, Random random) {
  if (palette.length <= 1) {
    return List<String>.from(palette);
  }
  final labs = palette.map(_labFromHex).toList(growable: false);
  final remaining = <int>[for (var i = 0; i < palette.length; i++) i];
  final ordered = <int>[];

  // 随机起点：换个种子就是另一套整体观感，同时保证可复现。
  ordered.add(remaining.removeAt(random.nextInt(remaining.length)));

  while (remaining.isNotEmpty) {
    var bestSlot = 0;
    var bestSeparation = -1.0;
    for (var slot = 0; slot < remaining.length; slot++) {
      // 与已选出全部颜色的最小距离——只和上一个取色比会漏掉「和更早的
      // 某一色几乎同色」的情况。
      var nearest = double.infinity;
      for (final chosen in ordered) {
        final distance = _labDistance(labs[chosen], labs[remaining[slot]]);
        if (distance < nearest) {
          nearest = distance;
        }
      }
      if (nearest > bestSeparation) {
        bestSeparation = nearest;
        bestSlot = slot;
      }
    }
    ordered.add(remaining.removeAt(bestSlot));
  }
  return [for (final index in ordered) palette[index]];
}

/// CIELAB coordinates of an sRGB hex, D65 white point.
class _Lab {
  const _Lab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;
}

_Lab _labFromHex(String hex) {
  final value = hex.replaceFirst('#', '').trim();
  final rgb = value.length == 6 ? int.tryParse(value, radix: 16) ?? 0 : 0;
  final red = _linearize(((rgb >> 16) & 0xFF) / 255);
  final green = _linearize(((rgb >> 8) & 0xFF) / 255);
  final blue = _linearize((rgb & 0xFF) / 255);

  // sRGB → XYZ (D65)
  final x = red * 0.4124564 + green * 0.3575761 + blue * 0.1804375;
  final y = red * 0.2126729 + green * 0.7151522 + blue * 0.0721750;
  final z = red * 0.0193339 + green * 0.1191920 + blue * 0.9503041;

  // XYZ → Lab (D65 white point)
  final fx = _labCurve(x / 0.95047);
  final fy = _labCurve(y);
  final fz = _labCurve(z / 1.08883);
  return _Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

double _linearize(double channel) {
  return channel <= 0.04045
      ? channel / 12.92
      : pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

double _labCurve(double t) {
  const delta = 6 / 29;
  return t > delta * delta * delta
      ? pow(t, 1 / 3).toDouble()
      : t / (3 * delta * delta) + 4 / 29;
}

double _labDistance(_Lab a, _Lab b) {
  final dl = a.l - b.l;
  final da = a.a - b.a;
  final db = a.b - b.b;
  return sqrt(dl * dl + da * da + db * db);
}

/// 两个色值在 CIELAB 下的感知距离（ΔE76）。
///
/// 抽色排序所用的度量。公开是为了让测试能独立断言「同一次抽取取出的颜色
/// 互不相近」这一行为，而不是把阈值写进实现里。非法色值按黑色处理（与
/// [_labFromHex] 的兜底一致）。
double courseColorPerceptualDistance(String hexA, String hexB) =>
    _labDistance(_labFromHex(hexA), _labFromHex(hexB));

String buildImportCourseColorGroupKey({
  required String name,
  required String teacher,
}) {
  return '${_normalizeImportColorKeyPart(name)}\u0000${_normalizeImportColorKeyPart(teacher)}';
}

String _normalizeImportColorKeyPart(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Picks a legible text color hex (near-black or white) for [backgroundHex]
/// based on its perceived luminance (ITU-R BT.601).
String matchingCourseTextColorHex(String backgroundHex) {
  final hex = backgroundHex.replaceAll('#', '').trim();
  if (hex.length < 6) {
    return '#FFFFFF';
  }
  final r = int.tryParse(hex.substring(0, 2), radix: 16) ?? 0;
  final g = int.tryParse(hex.substring(2, 4), radix: 16) ?? 0;
  final b = int.tryParse(hex.substring(4, 6), radix: 16) ?? 0;
  final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.6 ? '#1F1F1F' : '#FFFFFF';
}
