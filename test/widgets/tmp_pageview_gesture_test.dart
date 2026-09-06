import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page-root tap detector preserves pageview drag', (tester) async {
    final controller = PageController();
    var taps = 0;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PageView.builder(
          controller: controller,
          pageSnapping: false,
          itemCount: 3,
          itemBuilder: (context, index) => GestureDetector(
            key: const ValueKey('page-detector'),
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: ColoredBox(
              color: const Color(0xFFFFFF00),
              child: Center(child: Text('page $index')),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(PageView));
    await tester.dragFrom(rect.center, const Offset(-500, 0));
    await tester.pumpAndSettle();
    debugPrint('taps=$taps page=${controller.page}');
    expect(taps, 0);
  });
}
