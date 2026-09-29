import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/utils/course_color_palette.dart';

void main() {
  group('courseCardContrastRatio', () {
    test('identical colors have ratio 1', () {
      expect(
        courseCardContrastRatio(
          const Color(0xFF808080),
          const Color(0xFF808080),
        ),
        closeTo(1.0, 0.001),
      );
    });

    test('black on white is the maximum 21:1', () {
      expect(
        courseCardContrastRatio(
          const Color(0xFF000000),
          const Color(0xFFFFFFFF),
        ),
        closeTo(21.0, 0.01),
      );
    });

    test('is symmetric', () {
      const a = Color(0xFF0D47A1);
      const b = Color(0xFF90CAF9);
      expect(
        courseCardContrastRatio(a, b),
        closeTo(courseCardContrastRatio(b, a), 0.0001),
      );
    });
  });

  group('resolveReadableCourseCardTitleColor keeps the user choice', () {
    // Regression: the previous implementation forced pure white whenever the
    // card hue luminance was below 0.62, which threw away the deliberate deep
    // ink of nearly every preset pastel pairing.
    test('preset deep ink survives on its own pastel card', () {
      for (final pair in kPresetCourseColorPairs) {
        final card = parseHex(pair.cardHex);
        final ink = parseHex(pair.textHex);
          final resolved = resolveReadableCourseCardTitleColor(
            preferred: ink,
            cardColor: card,
          );
          expect(
            resolved,
            ink,
          reason: 'preset ${pair.textHex} on ${pair.cardHex} must not be '
              'overridden',
          );
        }
    });

    test('keeps a mid-tone ink that clears the contrast bar', () {
      // Dark navy on a pale card: clearly readable, must be preserved.
      const card = Color(0xFFE3F2FD);
      const ink = Color(0xFF0D47A1);
      expect(
        resolveReadableCourseCardTitleColor(preferred: ink, cardColor: card),
        ink,
      );
    });
  });

  group('resolveReadableCourseCardTitleColor falls back when unreadable', () {
    test('dark ink on a dark card is replaced', () {
      const card = Color(0xFF1B1B1B);
      const ink = Color(0xFF222222);
      final resolved = resolveReadableCourseCardTitleColor(
        preferred: ink,
        cardColor: card,
      );
      expect(resolved, isNot(ink));
      expect(
        courseCardContrastRatio(resolved, card),
        greaterThanOrEqualTo(courseCardMinContrastRatio),
      );
    });

    test('the override bar is the critical one, not the advisory one', () {
      // #E65100 on #FFCC80 is a shipped preset at ~2.56:1 — under WCAG AA
      // large (3.0) but well above the invisibility bar (2.0). It must be
      // warned about, never silently rewritten.
      const card = Color(0xFFFFCC80);
      const ink = Color(0xFFE65100);
      final ratio = courseCardContrastRatio(ink, card);
      expect(ratio, lessThan(courseCardMinContrastRatio));
      expect(ratio, greaterThan(courseCardCriticalContrastRatio));
      expect(
        resolveReadableCourseCardTitleColor(preferred: ink, cardColor: card),
        ink,
      );
    });

    test('white ink on a white card falls back to dark, not to white', () {
      const card = Color(0xFFFFFFFF);
      const ink = Color(0xFFFFFFFF);
      final resolved = resolveReadableCourseCardTitleColor(
        preferred: ink,
        cardColor: card,
      );
      expect(resolved, isNot(const Color(0xFFFFFFFF)));
      expect(resolved.computeLuminance(), lessThan(0.2));
    });

    test('a near-card-tone ink is covered too', () {
      const card = Color(0xFFFAFAFA);
      const ink = Color(0xFFF7F7F7);
      expect(
        resolveReadableCourseCardTitleColor(preferred: ink, cardColor: card),
        isNot(ink),
      );
    });
  });

  group('courseCardUnreadablePresetCardHexes', () {
    test('a readable ink reports no failures', () {
      expect(
        courseCardUnreadablePresetCardHexes(ink: const Color(0xFF000000)),
        isEmpty,
      );
    });

    test('a near-card-tone ink reports failures so the user is warned', () {
      final failing = courseCardUnreadablePresetCardHexes(
        // Same family/lightness as the pastel cards themselves.
        ink: const Color(0xFFA5D6A7),
      );
      expect(failing, isNotEmpty);
    });
  });

  group('detail color', () {
    test('is derived from the resolved title ink, softened', () {
      const card = Color(0xFF90CAF9);
      const ink = Color(0xFF0D47A1);
      final title = resolveReadableCourseCardTitleColor(
        preferred: ink,
        cardColor: card,
      );
      final detail = resolveReadableCourseCardDetailColor(
        preferred: ink,
        resolvedTitleInk: title,
        cardColor: card,
      );
      expect(detail.r, closeTo(ink.r, 0.001));
      expect(detail.g, closeTo(ink.g, 0.001));
      expect(detail.b, closeTo(ink.b, 0.001));
      expect(detail.a, lessThan(1.0));
    });
  });

  group('detail color polarity (solid surfaces)', () {
    // 回归：白标题（#FF9800 上对比度 2.16 ≥ 2.0 被保留）曾与同样达标的
    // 黑简介（9.7:1）同卡混色——详情墨必须跟随标题墨的明暗极性。
    test('opposite-polarity detail follows the kept white title', () {
      const card = Color(0xFFFF9800);
      final title = resolveReadableCourseCardTitleColor(
        preferred: const Color(0xFFFFFFFF),
        cardColor: card,
      );
      expect(title, const Color(0xFFFFFFFF)); // advisory 区间内保留用户白墨
      final detail = resolveReadableCourseCardDetailColor(
        preferred: const Color(0xFF000000),
        resolvedTitleInk: title,
        cardColor: card,
      );
      expect(detail.r, closeTo(1.0, 0.001));
      expect(detail.g, closeTo(1.0, 0.001));
      expect(detail.b, closeTo(1.0, 0.001));
      expect(detail.a, closeTo(0.7, 0.01));
    });

    test('reverse divergence also snaps to the title ink', () {
      const card = Color(0xFFFF9800);
      final title = resolveReadableCourseCardTitleColor(
        preferred: const Color(0xFF000000),
        cardColor: card,
      );
      expect(title, const Color(0xFF000000)); // 9.7:1 保留
      final detail = resolveReadableCourseCardDetailColor(
        preferred: const Color(0xFFFFFFFF),
        resolvedTitleInk: title,
        cardColor: card,
      );
      expect(detail.r, closeTo(0.0, 0.001));
      expect(detail.a, closeTo(0.7, 0.01));
    });

    test('same-polarity detail keeps its guarded ink (pastel flips both)', () {
      const card = Color(0xFF90CAF9); // 白字 1.75 < 2.0 → 标题翻近黑
      final title = resolveReadableCourseCardTitleColor(
        preferred: const Color(0xFFFFFFFF),
        cardColor: card,
      );
      expect(title.computeLuminance(), lessThan(0.5));
      final detail = resolveReadableCourseCardDetailColor(
        preferred: const Color(0xFF000000),
        resolvedTitleInk: title,
        cardColor: card,
      );
      // 黑墨本就达标（12:1）且与标题同极性 → 保留纯黑，不并入标题墨。
      expect(detail.r, closeTo(0.0, 0.001));
      expect(detail.a, closeTo(0.7, 0.01));
    });
  });

  group('courseCardInkIsNeutral', () {
    test('white / black / greys and near-black deep inks are neutral', () {
      for (final hex in [
        '#FFFFFF',
        '#000000',
        '#1F1F1F',
        '#1A1A1A',
        '#808080',
        '#0D0D14',
      ]) {
        expect(courseCardInkIsNeutral(parseHex(hex)), isTrue, reason: hex);
      }
    });

    test('hue-bearing inks are not neutral', () {
      for (final hex in [
        '#FF9800',
        '#B34700',
        '#0D47A1',
        '#F48FB1',
        '#90CAF9',
      ]) {
        expect(courseCardInkIsNeutral(parseHex(hex)), isFalse, reason: hex);
      }
    });
  });

  group('userChosenInk on the solid surface', () {
    // 回归：设置页字色/单课自带字色是显式选择，实心卡上一律照用；同一套设置
    // 下浅底卡变黑字、深底卡保留白字的「有的黑有的白」由此消除。
    const paleCard = Color(0xFFFFCC80);

    test('white ink survives on a pale card when it is user-chosen', () {
      expect(
        resolveReadableCourseCardTitleColor(
        preferred: const Color(0xFFFFFFFF),
          cardColor: paleCard,
          userChosenInk: true,
        ),
        const Color(0xFFFFFFFF),
      );
    });

    test('the same white ink still auto-flips when it is not user-chosen', () {
      expect(
        resolveReadableCourseCardTitleColor(
        preferred: const Color(0xFFFFFFFF),
          cardColor: paleCard,
        ),
        const Color(0xFF1A1A1A),
      );
    });

    test('detail keeps the user ink and only matches the title polarity', () {
      final title = resolveReadableCourseCardTitleColor(
        preferred: const Color(0xFFFFFFFF),
        cardColor: paleCard,
        userChosenInk: true,
      );
      final detail = resolveReadableCourseCardDetailColor(
        preferred: const Color(0xFF000000),
        resolvedTitleInk: title,
        cardColor: paleCard,
        userChosenInk: true,
      );
      // 黑详情不再被对比度守卫改写，但极性仍跟随白标题。
      expect(detail.r, closeTo(1.0, 0.001));
      expect(detail.a, closeTo(0.7, 0.01));
    });
  });
}

Color parseHex(String hex) {
  final value = hex.replaceFirst('#', '');
  return Color(int.parse('FF$value', radix: 16));
}
