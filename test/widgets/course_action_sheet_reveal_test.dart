import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/widgets/course_action_sheet_reveal.dart';

void main() {
  testWidgets('reveals visible content and waits for offscreen content', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_RevealHost(controller: controller));
    await tester.pumpAndSettle();

    expect(_opacity(tester, _firstRevealKey), 1);
    expect(_opacity(tester, _secondRevealKey), 0);

    controller.jumpTo(1000);
    await tester.pumpAndSettle();

    expect(_opacity(tester, _secondRevealKey), 1);

    controller.jumpTo(0);
    await tester.pumpAndSettle();

    expect(_opacity(tester, _secondRevealKey), 0);
  });

  testWidgets('shows content immediately when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 100),
                  CourseDetailReveal(
                    key: _firstRevealKey,
                    child: Container(
                      key: _firstKey,
                      height: 50,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(_firstKey), findsOneWidget);
  });
}

const _firstKey = ValueKey('reveal-first');
const _secondKey = ValueKey('reveal-second');
const _firstRevealKey = ValueKey('reveal-widget-first');
const _secondRevealKey = ValueKey('reveal-widget-second');

class _RevealHost extends StatelessWidget {
  const _RevealHost({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              const SizedBox(height: 100),
              CourseDetailReveal(
                key: _firstRevealKey,
                child: Container(
                  key: _firstKey,
                  height: 50,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 1200),
              CourseDetailReveal(
                key: _secondRevealKey,
                child: Container(
                  key: _secondKey,
                  height: 50,
                  color: Colors.deepOrange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _opacity(WidgetTester tester, Key key) {
  final fade = tester.widget<FadeTransition>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(FadeTransition))
        .first,
  );
  return fade.opacity.value;
}
