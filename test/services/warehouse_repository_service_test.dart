import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/models/warehouse_repository_models.dart';
import 'package:university_timetable/services/warehouse_repository_service.dart';

/// 远程适配仓已移除：本文件只验证「一切来自打包 assets」，
/// 不再构造任何 HTTP 客户端 —— 服务本身已无网络依赖。
void main() {
  const rootIndexYaml = '''
schools:
  - id: "SCUEC"
    name: "中南民族大学"
    initial: "Z"
    resource_folder: "SCUEC"

  - id: "MYSY"
    name: "绵阳师范学院"
    initial: "M"
    resource_folder: "MYSY"
''';

  const scuecAdaptersYaml = '''
adapters:
  - adapter_id: "SCUEC"
    adapter_name: "中南民族大学教务系统"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "scuec.js"
    import_url: "https://webvpn.scuec.edu.cn/"
    maintainer: "Zellon0w0"
    description: "中南民族大学课程表导入适配"
''';

  const mysyAdaptersYaml = '''
adapters:
  - adapter_id: "MYSY"
    adapter_name: "绵阳师范学院教务系统"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "mysy.js"
    import_url: "http://jw.mtc.edu.cn/"
    maintainer: "Guzheng3"
    description: "适配绵阳师范学院正方教务系统"
''';

  WarehouseRepositoryService serviceWith(Map<String, String> assets) {
    return WarehouseRepositoryService(
      assetLoader: (assetPath) async {
        final content = assets[assetPath];
        if (content == null) {
          throw StateError('missing asset: $assetPath');
        }
        return utf8.encode(content);
      },
    );
  }

  WarehouseRepositoryService defaultService({
    String scuecAdapters = scuecAdaptersYaml,
    String scuecScript = 'console.log("scuec");',
  }) {
    return serviceWith({
      'assets/warehouse/root_index.yaml': rootIndexYaml,
      'assets/warehouse/SCUEC/adapters.yaml': scuecAdapters,
      'assets/warehouse/MYSY/adapters.yaml': mysyAdaptersYaml,
      'assets/warehouse/SCUEC/scuec.js': scuecScript,
      'assets/warehouse/MYSY/mysy.js': 'console.log("mysy");',
    });
  }

  // 服务签名仍保留 source / options，这里用最小实例保证既有调用形态可用。
  const source = WarehouseRepositorySource(
    owner: 'Mutx163',
    repo: 'qingyu_warehouse',
  );

  test('学校列表完全来自打包 assets，并包含内置学校', () async {
    final rootIndex = await defaultService().fetchRootIndex(source);

    expect(rootIndex.schools, hasLength(2));
    expect(
      rootIndex.schools.map((school) => school.id),
      containsAll(['SCUEC', 'MYSY']),
    );
    expect(rootIndex.schools.first.name, '中南民族大学');
  });

  test('内置学校缺失时会补进学校列表', () async {
    const partialRootYaml = '''
schools:
  - id: "SCUEC"
    name: "中南民族大学"
    initial: "Z"
    resource_folder: "SCUEC"
''';
    final service = serviceWith({
      'assets/warehouse/root_index.yaml': partialRootYaml,
      'assets/warehouse/SCUEC/adapters.yaml': scuecAdaptersYaml,
      'assets/warehouse/MYSY/adapters.yaml': mysyAdaptersYaml,
      'assets/warehouse/SCUEC/scuec.js': 'console.log("scuec");',
      'assets/warehouse/MYSY/mysy.js': 'console.log("mysy");',
    });

    final rootIndex = await service.fetchRootIndex(source);

    expect(rootIndex.schools, hasLength(2));
    expect(
      rootIndex.schools.map((school) => school.id),
      containsAll(['SCUEC', 'MYSY']),
    );
  });

  test('SCUEC 适配器索引来自 assets', () async {
    final adapters = await defaultService().fetchAdaptersIndex(
      source,
      WarehouseRepositoryService.builtInSchoolEntry,
    );

    expect(adapters.adapters, hasLength(1));
    expect(adapters.adapters.single.adapterId, 'SCUEC');
    expect(adapters.adapters.single.adapterName, contains('中南民族大学'));
    expect(adapters.adapters.single.importUrl, 'https://webvpn.scuec.edu.cn/');
  });

  test('MYSY 适配器索引来自 assets', () async {
    final adapters = await defaultService().fetchAdaptersIndex(
      source,
      WarehouseRepositoryService.mysySchoolEntry,
    );

    expect(adapters.adapters, hasLength(1));
    expect(adapters.adapters.single.adapterId, 'MYSY');
    expect(adapters.adapters.single.adapterName, contains('绵阳师范学院'));
  });

  test('非内置学校没有适配器索引', () async {
    const school = WarehouseSchoolEntry(
      id: 'CQU',
      name: '重庆大学',
      initial: 'C',
      resourceFolder: 'CQU',
    );

    await expectLater(
      defaultService().fetchAdaptersIndex(source, school),
      throwsA(
        isA<WarehouseRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('warehouse_no_adapters'),
        ),
      ),
    );
  });

  test('SCUEC 适配脚本来自 assets', () async {
    final script = await defaultService().fetchAdapterScript(
      source,
      school: WarehouseRepositoryService.builtInSchoolEntry,
      adapter: const WarehouseAdapterEntry(
        adapterId: 'SCUEC',
        adapterName: '中南民族大学教务系统',
        category: 'BACHELOR_AND_ASSOCIATE',
        assetJsPath: 'scuec.js',
        importUrl: 'https://webvpn.scuec.edu.cn/',
        maintainer: 'Zellon0w0',
        description: '中南民族大学课程表导入适配',
      ),
    );

    expect(script, contains('scuec'));
  });

  test('非内置适配脚本会被拒绝', () async {
    await expectLater(
      defaultService().fetchAdapterScript(
        source,
        school: WarehouseRepositoryService.builtInSchoolEntry,
        adapter: const WarehouseAdapterEntry(
          adapterId: 'CQU_01',
          adapterName: '重庆大学教务',
          category: 'BACHELOR_AND_ASSOCIATE',
          assetJsPath: 'cqu_01.js',
          importUrl: 'https://example.com/login',
          maintainer: 'Mutx',
          description: '测试适配器',
        ),
      ),
      throwsA(isA<WarehouseRepositoryException>()),
    );
  });

  test('索引声明 sha256 时会校验内置脚本一致性', () async {
    const scriptBody = 'console.log("verified");';
    final digest = sha256.convert(utf8.encode(scriptBody)).toString();
    final service = defaultService(
      scuecAdapters: '''
adapters:
  - adapter_id: "SCUEC"
    adapter_name: "中南民族大学教务系统"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "scuec.js"
    import_url: "https://webvpn.scuec.edu.cn/"
    maintainer: "Zellon0w0"
    description: "中南民族大学课程表导入适配"
    sha256: "${digest.toUpperCase()}"
''',
      scuecScript: scriptBody,
    );

    final adapters = await service.fetchAdaptersIndex(
      source,
      WarehouseRepositoryService.builtInSchoolEntry,
    );
    expect(adapters.adapters.single.sha256, digest.toUpperCase());

    final script = await service.fetchAdapterScript(
      source,
      school: WarehouseRepositoryService.builtInSchoolEntry,
      adapter: adapters.adapters.single,
    );
    expect(script, scriptBody);
  });

  test('索引与脚本不匹配时阻断执行', () async {
    final service = defaultService(
      scuecAdapters: '''
adapters:
  - adapter_id: "SCUEC"
    adapter_name: "中南民族大学教务系统"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "scuec.js"
    import_url: "https://webvpn.scuec.edu.cn/"
    maintainer: "Zellon0w0"
    description: "中南民族大学课程表导入适配"
    sha256: "${sha256.convert(utf8.encode('console.log("trusted");')).toString()}"
''',
    );

    await expectLater(
      service.fetchAdapterScript(
        source,
        school: WarehouseRepositoryService.builtInSchoolEntry,
        adapter: const WarehouseAdapterEntry(
          adapterId: 'SCUEC',
          adapterName: '中南民族大学教务系统',
          category: 'BACHELOR_AND_ASSOCIATE',
          assetJsPath: 'scuec.js',
          importUrl: 'https://webvpn.scuec.edu.cn/',
          maintainer: 'Zellon0w0',
          description: '中南民族大学课程表导入适配',
          sha256: '0000000000000000000000000000000000000000000000000000000000000000',
        ),
      ),
      throwsA(
        isA<WarehouseRepositoryException>().having(
          (error) => error.message,
          'message',
          'warehouse_script_checksum_failed',
        ),
      ),
    );
  });

  test('WarehouseFetchOptions 仍可构造，但不再影响取值', () async {
    const options = WarehouseFetchOptions(
      downloadSource: AppUpdateDownloadSource.original,
      mirrorPreset: AppUpdateMirrorPreset.ghfast,
      customMirrorUrlPrefix: defaultAppUpdateMirrorUrlPrefix,
    );

    final rootIndex = await defaultService().fetchRootIndex(
      source,
      options: options,
    );

    expect(rootIndex.schools, hasLength(2));
  });

  testWidgets('内置 SCUEC / MYSY 资源已注册进 Flutter assets', (tester) async {
    final service = WarehouseRepositoryService();

    final adapters = await service.fetchAdaptersIndex(
      source,
      WarehouseRepositoryService.builtInSchoolEntry,
    );
    final script = await service.fetchAdapterScript(
      source,
      school: WarehouseRepositoryService.builtInSchoolEntry,
      adapter: adapters.adapters.single,
    );

    expect(script, contains('runImportFlow'));
    expect(script, contains('中南民族大学'));

    final mysyAdapters = await service.fetchAdaptersIndex(
      source,
      WarehouseRepositoryService.mysySchoolEntry,
    );
    final mysyScript = await service.fetchAdapterScript(
      source,
      school: WarehouseRepositoryService.mysySchoolEntry,
      adapter: mysyAdapters.adapters.single,
    );

    expect(mysyScript, contains('runImportFlow'));
    expect(mysyScript, contains('绵阳师范学院'));
  });
}
