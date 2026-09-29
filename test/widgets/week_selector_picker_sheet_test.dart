import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/ui/hyperos/hyperos.dart';
import 'package:university_timetable/widgets/week_selector_picker_sheet.dart';

import '../helpers_test_app.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    int visibleWeek = 2,
    int? currentSemesterWeek = 2,
    EdgeInsets mediaQueryPadding = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      FrostedAppearanceScope(
        appearance: const FrostedAppearance(
          sheetBlurSigma: 15,
          sheetTintAlpha: 0.7,
          sheetBarrierAlpha: 0.2,
        ),
        child: MediaQuery(
          data: MediaQueryData(padding: mediaQueryPadding),
          child: TestApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showWeekSelectorPickerSheet(
                  context,
                  availableWeeks: const [1, 2, 3, 4],
                  visibleWeek: visibleWeek,
                  currentSemesterWeek: currentSemesterWeek,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Material cellMaterial(WidgetTester tester, String label) {
    return tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
  }

  Ink? cellInk(WidgetTester tester, String label) {
    final ink = find
        .ancestor(of: find.text(label), matching: find.byType(Ink));
    return ink.evaluate().isEmpty
        ? null
        : tester.widget<Ink>(ink.first);
  }

  Color cellTextColor(WidgetTester tester, String label) {
    return tester.widget<Text>(find.text(label)).style!.color!;
  }

  testWidgets('frosted mode: legacy flat Miuix chip is unchanged', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(cellMaterial(tester, '第 1 周').color, const Color(0xFFE8E8E8));
    expect(cellTextColor(tester, '第 1 周'), const Color(0xFF303030));
    expect(cellInk(tester, '第 1 周')!.decoration, isNull);

    expect(find.byType(HyperosSectionDescription), findsOneWidget);
  });

  testWidgets('selected week gets solid highlight, current week gets tint', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      // 浏览第 1 周、实际身处第 3 周：两格须同时可辨。
      visibleWeek: 1,
      currentSemesterWeek: 3,
    );

    // 正在查看的周：实底主题色 + 白字（最强标识）。
    expect(cellMaterial(tester, '第 1 周').color, const Color(0xFF3482FF));
    expect(cellTextColor(tester, '第 1 周'), const Color(0xFFFFFFFF));
    expect(cellInk(tester, '第 1 周')!.decoration, isNull);

    // 实际所在周：主题色浅井 + 主题色字（弱一档）。
    expect(
      cellMaterial(tester, '第 3 周').color,
      const Color(0xFF3482FF).withValues(alpha: 0.12),
    );
    expect(cellTextColor(tester, '第 3 周'), const Color(0xFF3482FF));

    // 无关格子维持平涂。
    expect(cellMaterial(tester, '第 2 周').color, const Color(0xFFE8E8E8));
  });

  testWidgets('grid ignores ambient MediaQuery padding (status bar inset)', (
    tester,
  ) async {
    // 真机回归锚点：弹窗路由在根 Navigator 上能看到未消费的状态栏 inset，
    // 曾被 ScrollView 自动 padding 吃掉变成格子顶上 ~50dp 透明空隙。
    await pumpSheet(
      tester,
      mediaQueryPadding: const EdgeInsets.only(top: 51, bottom: 17),
    );

    final descBottom = tester.getRect(find.text('共 4 周')).bottom;
    final gridTop = tester.getTopLeft(find.byType(GridView)).dy;
    expect(gridTop - descBottom, 16.0);
  });
}
