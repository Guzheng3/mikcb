import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/services/memory_stats_service.dart';
import 'package:university_timetable/widgets/home_menu_catalog.dart';

void main() {
  test('catalog ids are unique and non-empty', () {
    final ids = kHomeMenuCatalog.map((entry) => entry.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'id 重复会导致瓷贴互相顶替');
    expect(ids.every((id) => id.isNotEmpty), isTrue);
  });

  test('default order resolves entirely from catalog', () {
    for (final id in HomeMenuDefaults.defaultActions) {
      expect(homeMenuEntryById(id), isNotNull, reason: '默认排列含未知 id: $id');
    }
  });

  test('couple login entry leads the top menu only while the switch is on', () {
    // 开关默认开启：登录入口置顶。
    final enabled = resolveHomeTopMenuEntries(TimetableSettings.defaults());
    expect(enabled.first.id, 'withuCoupleLogin');

    // 开关关闭：登录入口从右上角菜单消失。
    final disabled = resolveHomeTopMenuEntries(
      TimetableSettings.defaults().copyWith(
        coupleTimetableOverlayEnabled: false,
      ),
    );
    expect(
      disabled.map((entry) => entry.id),
      isNot(contains('withuCoupleLogin')),
    );

    // 登录入口是瞬态条目，不进持久化候选目录。
    expect(
      kHomeMenuCatalog.map((entry) => entry.id),
      isNot(contains('withuCoupleLogin')),
    );
  });

  test('memory stats entry is hidden for release users', () {
    final memoryEntry = homeMenuEntryById('memoryStats');
    expect(memoryEntry, isNotNull);

    // 诊断入口不进默认菜单排列，仅玻璃坞/设置页开发者组可达。
    expect(HomeMenuDefaults.defaultActions, isNot(contains('memoryStats')));

    // 正式版（非诊断包名）：条目不可见。
    MemoryStatsService.debugSetCachedDiagnosticsBuild(false);
    addTearDown(() => MemoryStatsService.debugSetCachedDiagnosticsBuild(null));
    expect(memoryEntry!.visible(), isFalse);
    expect(resolveHomeMenuEntries().map((e) => e.id), isNot(contains('memoryStats')));

    // 调试/性能版（诊断包名）：条目恢复可见。
    MemoryStatsService.debugSetCachedDiagnosticsBuild(true);
    expect(memoryEntry.visible(), isTrue);
  });

  test('resolver returns exactly the visible default actions in order', () {
    final resolved = resolveHomeMenuEntries();
    final expected = [
      for (final id in HomeMenuDefaults.defaultActions)
        if (homeMenuEntryById(id)!.visible()) id,
    ];
    expect(resolved.map((e) => e.id), expected);
  });
}
