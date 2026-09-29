import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/ui/hyperos/hyperos_blurred_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HyperosBlurredHeader.modalBarrierColor', () {
    Future<Color> barrierOf(
      WidgetTester tester, {
      double sheetBarrierAlpha = 0.20,
    }) async {
      late Color barrier;
      await tester.pumpWidget(
        MaterialApp(
          home: FrostedAppearanceScope(
            appearance: FrostedAppearance(
              sheetBlurSigma: 15,
              sheetTintAlpha: 0.70,
              sheetBarrierAlpha: sheetBarrierAlpha,
            ),
            child: Builder(
              builder: (context) {
                barrier = HyperosBlurredHeader.modalBarrierColor(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return barrier;
    }

    testWidgets('uses configured sheet barrier alpha', (tester) async {
      final barrier = await barrierOf(tester);
      expect(barrier, Colors.black.withValues(alpha: 0.20));
    });
  });
}