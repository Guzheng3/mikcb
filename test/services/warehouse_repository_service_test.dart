import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:university_timetable/models/timetable_settings.dart';
import 'package:university_timetable/models/warehouse_repository_models.dart';
import 'package:university_timetable/services/warehouse_repository_service.dart';

class _FakeClient extends http.BaseClient {
  final Map<String, http.Response> responses;
  final List<String> requestedUrls = [];

  _FakeClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url.toString());
    final response = responses[request.url.toString()];
    if (response == null) {
      return http.StreamedResponse(Stream.value(utf8.encode('not found')), 404);
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  test('parse GitHub source and build raw URLs', () {
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );

    expect(source.owner, 'Mutx163');
    expect(source.repo, 'qingyu_warehouse');
    expect(
      source.buildRawFileUri('index/root_index.yaml').toString(),
      'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/index/root_index.yaml',
    );
  });

  test('fetch root index and adapters index', () async {
    const rootYaml = '''
schools:
  - id: "CQU"
    name: "重庆大学"
    initial: "C"
    resource_folder: "CQU"
''';
    const adaptersYaml = '''
adapters:
  - adapter_id: "CQU_01"
    adapter_name: "重庆大学教务"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "cqu_01.js"
    import_url: "https://example.com/login"
    maintainer: "Mutx"
    description: "测试适配器"
''';
    const scriptBody = 'console.log("hello");';

    final client = _FakeClient({
      'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/index/root_index.yaml':
          http.Response.bytes(utf8.encode(rootYaml), 200),
      'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/resources/CQU/adapters.yaml':
          http.Response.bytes(utf8.encode(adaptersYaml), 200),
      'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/resources/CQU/cqu_01.js':
          http.Response(scriptBody, 200),
    });
    final service = WarehouseRepositoryService(client: client);
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );
    const options = WarehouseFetchOptions(
      downloadSource: AppUpdateDownloadSource.original,
      mirrorPreset: AppUpdateMirrorPreset.ghfast,
      customMirrorUrlPrefix: defaultAppUpdateMirrorUrlPrefix,
    );

    final rootIndex = await service.fetchRootIndex(source, options: options);
    expect(rootIndex.schools, hasLength(3));
    expect(rootIndex.schools.first.name, '重庆大学');
    expect(
      rootIndex.schools.map((school) => school.id),
      containsAll(['SCUEC', 'MYSY']),
    );

    final adapters = await service.fetchAdaptersIndex(
      source,
      rootIndex.schools.first,
      options: options,
    );
    expect(adapters.adapters, hasLength(1));
    expect(adapters.adapters.first.adapterId, 'CQU_01');

    final script = await service.fetchAdapterScript(
      source,
      school: rootIndex.schools.first,
      adapter: adapters.adapters.first,
      options: options,
    );
    expect(script, contains('console.log'));
  });

  test('adapters index parses declared sha256 for integrity gate', () async {
    const adaptersYaml = '''
adapters:
  - adapter_id: "CQU_01"
    adapter_name: "重庆大学教务"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "cqu_01.js"
    import_url: "https://example.com/login"
    maintainer: "Mutx"
    description: "测试适配器"
    sha256: "ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
''';
    final client = _FakeClient({
      'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/resources/CQU/adapters.yaml':
          http.Response.bytes(utf8.encode(adaptersYaml), 200),
    });
    final service = WarehouseRepositoryService(client: client);
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );
    const school = WarehouseSchoolEntry(
      id: 'CQU',
      name: '重庆大学',
      initial: 'C',
      resourceFolder: 'CQU',
    );

    final adapters = await service.fetchAdaptersIndex(source, school);
    // Declared checksums are stored verbatim; case is normalized when compared.
    expect(
      adapters.adapters.single.sha256,
      'ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
    );
  });

  test('fetchAdapterScript accepts bytes matching declared sha256', () async {
    const scriptBody = 'console.log("verified");';
    final digest = sha256.convert(utf8.encode(scriptBody)).toString();
    final adapter = WarehouseAdapterEntry(
      adapterId: 'CQU_01',
      adapterName: '重庆大学教务',
      category: 'BACHELOR_AND_ASSOCIATE',
      assetJsPath: 'cqu_01.js',
      importUrl: 'https://example.com/login',
      maintainer: 'Mutx',
      description: '测试适配器',
      sha256: digest.toUpperCase(),
    );
    final client = _FakeClient({
      'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/resources/CQU/cqu_01.js':
          http.Response(scriptBody, 200),
    });
    final service = WarehouseRepositoryService(client: client);
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );
    const school = WarehouseSchoolEntry(
      id: 'CQU',
      name: '重庆大学',
      initial: 'C',
      resourceFolder: 'CQU',
    );

    final script = await service.fetchAdapterScript(
      source,
      school: school,
      adapter: adapter,
    );
    expect(script, scriptBody);
  });

  test(
    'fetchAdapterScript rejects tampered script when sha256 declared',
    () async {
      const servedBody = 'alert("tampered");// poisoned mirror payload';
      final adapter = WarehouseAdapterEntry(
        adapterId: 'CQU_01',
        adapterName: '重庆大学教务',
        category: 'BACHELOR_AND_ASSOCIATE',
        assetJsPath: 'cqu_01.js',
        importUrl: 'https://example.com/login',
        maintainer: 'Mutx',
        description: '测试适配器',
        sha256: sha256
            .convert(utf8.encode('console.log("trusted");'))
            .toString(),
      );
      final client = _FakeClient({
        'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/resources/CQU/cqu_01.js':
            http.Response(servedBody, 200),
      });
      final service = WarehouseRepositoryService(client: client);
      final source = WarehouseRepositorySource.fromGitHubUrl(
        'https://github.com/Mutx163/qingyu_warehouse',
      );
      const school = WarehouseSchoolEntry(
        id: 'CQU',
        name: '重庆大学',
        initial: 'C',
        resourceFolder: 'CQU',
      );

      await expectLater(
        service.fetchAdapterScript(source, school: school, adapter: adapter),
        throwsA(
          isA<WarehouseRepositoryException>().having(
            (error) => error.message,
            'message',
            'warehouse_script_checksum_failed',
          ),
        ),
      );
    },
  );

  test(
    'fetchAdapterScript skips verification for legacy indexes without sha256',
    () async {
      const scriptBody = 'console.log("legacy");';
      const adapter = WarehouseAdapterEntry(
        adapterId: 'CQU_01',
        adapterName: '重庆大学教务',
        category: 'BACHELOR_AND_ASSOCIATE',
        assetJsPath: 'cqu_01.js',
        importUrl: 'https://example.com/login',
        maintainer: 'Mutx',
        description: '测试适配器',
      );
      final client = _FakeClient({
        'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/resources/CQU/cqu_01.js':
            http.Response(scriptBody, 200),
      });
      final service = WarehouseRepositoryService(client: client);
      final source = WarehouseRepositorySource.fromGitHubUrl(
        'https://github.com/Mutx163/qingyu_warehouse',
      );
      const school = WarehouseSchoolEntry(
        id: 'CQU',
        name: '重庆大学',
        initial: 'C',
        resourceFolder: 'CQU',
      );

      final script = await service.fetchAdapterScript(
        source,
        school: school,
        adapter: adapter,
      );
      expect(script, scriptBody);
    },
  );

  test('root index falls back to bundled entries when remote fails', () async {
    const rootYaml = '''
schools:
  - id: "SCUEC"
    name: "中南民族大学"
    initial: "Z"
    resource_folder: "SCUEC"
''';
    final client = _FakeClient(const {});
    final service = WarehouseRepositoryService(
      client: client,
      assetLoader: (assetPath) async => utf8.encode(rootYaml),
    );
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );

    final rootIndex = await service.fetchRootIndex(source);

    expect(rootIndex.schools, hasLength(2));
    expect(
      rootIndex.schools.map((school) => school.id),
      containsAll(['SCUEC', 'MYSY']),
    );
    expect(rootIndex.schools.first.name, '中南民族大学');
    expect(client.requestedUrls, isNotEmpty);
  });

  test('remote root index always includes bundled entries', () async {
    const remoteRootYaml = '''
schools:
  - id: "CQU"
    name: "重庆大学"
    initial: "C"
    resource_folder: "CQU"
''';
    const localRootYaml = '''
schools:
  - id: "SCUEC"
    name: "中南民族大学"
    initial: "Z"
    resource_folder: "SCUEC"
''';
    final client = _FakeClient({
      'https://raw.githubusercontent.com/Mutx163/qingyu_warehouse/main/index/root_index.yaml':
          http.Response.bytes(utf8.encode(remoteRootYaml), 200),
    });
    final service = WarehouseRepositoryService(
      client: client,
      assetLoader: (assetPath) async => utf8.encode(localRootYaml),
    );
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );
    const options = WarehouseFetchOptions(
      downloadSource: AppUpdateDownloadSource.original,
      mirrorPreset: AppUpdateMirrorPreset.ghfast,
      customMirrorUrlPrefix: defaultAppUpdateMirrorUrlPrefix,
    );

    final rootIndex = await service.fetchRootIndex(source, options: options);

    expect(rootIndex.schools, hasLength(3));
    expect(
      rootIndex.schools.map((school) => school.id),
      containsAll(['SCUEC', 'MYSY']),
    );
  });

  test('SCUEC adapter index is loaded from assets without HTTP', () async {
    const adaptersYaml = '''
adapters:
  - adapter_id: "SCUEC"
    adapter_name: "中南民族大学教务系统"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "scuec.js"
    import_url: "https://webvpn.scuec.edu.cn/"
    maintainer: "Zellon0w0"
    description: "中南民族大学课程表导入适配"
''';
    final client = _FakeClient(const {});
    final service = WarehouseRepositoryService(
      client: client,
      assetLoader: (assetPath) async => utf8.encode(adaptersYaml),
    );
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );

    final adapters = await service.fetchAdaptersIndex(
      source,
      WarehouseRepositoryService.builtInSchoolEntry,
    );

    expect(adapters.adapters, hasLength(1));
    expect(adapters.adapters.single.adapterId, 'SCUEC');
    expect(adapters.adapters.single.adapterName, contains('中南民族大学'));
    expect(client.requestedUrls, isEmpty);
  });

  test('SCUEC script is loaded from assets without HTTP', () async {
    const scriptBody = 'console.log("scuec"); // 中南民族大学';
    final client = _FakeClient(const {});
    final service = WarehouseRepositoryService(
      client: client,
      assetLoader: (assetPath) async => utf8.encode(scriptBody),
    );
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );
    const adapter = WarehouseAdapterEntry(
      adapterId: 'SCUEC',
      adapterName: '中南民族大学教务系统',
      category: 'BACHELOR_AND_ASSOCIATE',
      assetJsPath: 'scuec.js',
      importUrl: 'https://webvpn.scuec.edu.cn/',
      maintainer: 'Zellon0w0',
      description: '中南民族大学课程表导入适配',
    );

    final script = await service.fetchAdapterScript(
      source,
      school: WarehouseRepositoryService.builtInSchoolEntry,
      adapter: adapter,
    );

    expect(script, scriptBody);
    expect(client.requestedUrls, isEmpty);
  });

  test('MYSY adapter index is loaded from assets without HTTP', () async {
    const adaptersYaml = '''
adapters:
  - adapter_id: "MYSY"
    adapter_name: "绵阳师范学院教务系统"
    category: "BACHELOR_AND_ASSOCIATE"
    asset_js_path: "mysy.js"
    import_url: "http://jw.mtc.edu.cn/"
    maintainer: "Guzheng3"
    description: "适配绵阳师范学院正方教务系统"
''';
    final client = _FakeClient(const {});
    final service = WarehouseRepositoryService(
      client: client,
      assetLoader: (assetPath) async => utf8.encode(adaptersYaml),
    );
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );

    final adapters = await service.fetchAdaptersIndex(
      source,
      WarehouseRepositoryService.mysySchoolEntry,
    );

    expect(adapters.adapters, hasLength(1));
    expect(adapters.adapters.single.adapterId, 'MYSY');
    expect(adapters.adapters.single.adapterName, contains('绵阳师范学院'));
    expect(client.requestedUrls, isEmpty);
  });

  test('MYSY script is loaded from assets without HTTP', () async {
    const scriptBody = 'console.log("mysy"); // 绵阳师范学院';
    final client = _FakeClient(const {});
    final service = WarehouseRepositoryService(
      client: client,
      assetLoader: (assetPath) async => utf8.encode(scriptBody),
    );
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );
    const adapter = WarehouseAdapterEntry(
      adapterId: 'MYSY',
      adapterName: '绵阳师范学院教务系统',
      category: 'BACHELOR_AND_ASSOCIATE',
      assetJsPath: 'mysy.js',
      importUrl: 'http://jw.mtc.edu.cn/',
      maintainer: 'Guzheng3',
      description: '适配绵阳师范学院正方教务系统',
    );

    final script = await service.fetchAdapterScript(
      source,
      school: WarehouseRepositoryService.mysySchoolEntry,
      adapter: adapter,
    );

    expect(script, scriptBody);
    expect(client.requestedUrls, isEmpty);
  });

  testWidgets('bundled SCUEC and MYSY assets are registered with Flutter', (
    tester,
  ) async {
    final client = _FakeClient(const {});
    final service = WarehouseRepositoryService(client: client);
    final source = WarehouseRepositorySource.fromGitHubUrl(
      'https://github.com/Mutx163/qingyu_warehouse',
    );

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
    expect(client.requestedUrls, isEmpty);
  });
}
