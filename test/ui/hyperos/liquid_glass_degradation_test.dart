import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/ui/hyperos/frosted/liquid_glass_degradation.dart';

void main() {
  group('LiquidGlassDegradation.shouldDegradeFor', () {
    const base = MediaQueryData();

    test('false by default (no accessibility flags)', () {
      expect(LiquidGlassDegradation.shouldDegradeFor(base), isFalse);
    });

    test(
      'false under accessibleNavigation (MIUI screenshot false positive)',
      () {
      // MIUI/HyperOS 截图悬浮窗会打开系统 touch exploration，引擎误报
      // accessibleNavigation=true（flutter/flutter#128409），玻璃不随该信号
      // 降级，否则截图预览悬浮窗存在期间全部玻璃回落实体。
      expect(
        LiquidGlassDegradation.shouldDegradeFor(
          base.copyWith(accessibleNavigation: true),
        ),
        isFalse,
      );
      },
    );

    test('true under disableAnimations (system "remove animations")', () {
      expect(
        LiquidGlassDegradation.shouldDegradeFor(
          base.copyWith(disableAnimations: true),
        ),
        isTrue,
      );
    });

    test('true under highContrast', () {
      expect(
        LiquidGlassDegradation.shouldDegradeFor(
          base.copyWith(highContrast: true),
        ),
        isTrue,
      );
    });

    test('true when any flag is set among several', () {
      expect(
        LiquidGlassDegradation.shouldDegradeFor(
          base.copyWith(accessibleNavigation: false, highContrast: true),
        ),
        isTrue,
      );
    });

    test('false again once all flags clear', () {
      expect(
        LiquidGlassDegradation.shouldDegradeFor(
          base.copyWith(highContrast: true).copyWith(highContrast: false),
        ),
        isFalse,
      );
    });
  });
}
