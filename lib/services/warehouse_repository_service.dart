import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/service_message_localizer.dart';
import '../logging/app_debug_log.dart';
import '../models/timetable_settings.dart';
import '../models/warehouse_repository_models.dart';
import '../utils/async_utils.dart';

typedef WarehouseAssetLoader = Future<List<int>> Function(String assetPath);

class _BuiltInWarehouseAdapter {
  final WarehouseSchoolEntry school;
  final String adapterId;
  final String adapterIndexAssetPath;
  final String scriptAssetPath;

  const _BuiltInWarehouseAdapter({
    required this.school,
    required this.adapterId,
    required this.adapterIndexAssetPath,
    required this.scriptAssetPath,
  });
}

/// 兼容层：远程适配仓已移除，本类型不再参与任何取值决策。
///
/// 调用方仍可传入（`fetchRootIndex` / `fetchAdaptersIndex` / `fetchAdapterScript`
/// 都保留了 `options` 参数以维持既有签名），但内容会被完全忽略。
class WarehouseFetchOptions {
  final AppUpdateDownloadSource downloadSource;
  final AppUpdateMirrorPreset mirrorPreset;
  final String customMirrorUrlPrefix;

  const WarehouseFetchOptions({
    required this.downloadSource,
    required this.mirrorPreset,
    required this.customMirrorUrlPrefix,
  });

  /// 兼容层：远程适配仓已移除，返回值不再参与任何取值决策。
  ///
  /// 保留工厂以便 `WarehouseFetchOptions.fromSettings(settings)` 的既有调用
  /// 继续编译，但下载源 / 镜像配置对导入流程不再有任何影响。
  factory WarehouseFetchOptions.fromSettings(TimetableSettings settings) {
    return WarehouseFetchOptions(
      downloadSource: AppUpdateDownloadSourceX.fromValue(
        settings.appUpdateDownloadSource,
      ),
      mirrorPreset: AppUpdateMirrorPresetX.fromValue(
        settings.appUpdateMirrorPreset,
      ),
      customMirrorUrlPrefix: settings.appUpdateMirrorUrlPrefix,
    );
  }
}

/// 教务适配资源服务。
///
/// 只从打包进应用的 assets 读取学校索引、适配器索引与适配脚本：
/// 不发起任何网络请求，因此不存在镜像回退、投毒镜像或远程仓不可达的失败面。
/// 目前内置学校为 [builtInSchoolEntries]（SCUEC / MYSY），
/// 索引文件为 `assets/warehouse/root_index.yaml` 与
/// `assets/warehouse/<学校>/adapters.yaml`。
class WarehouseRepositoryService {
  static const String builtInSchoolId = 'SCUEC';
  static const WarehouseSchoolEntry builtInSchoolEntry = WarehouseSchoolEntry(
    id: builtInSchoolId,
    name: '中南民族大学',
    initial: 'Z',
    resourceFolder: builtInSchoolId,
  );
  static const WarehouseSchoolEntry mysySchoolEntry = WarehouseSchoolEntry(
    id: 'MYSY',
    name: '绵阳师范学院',
    initial: 'M',
    resourceFolder: 'MYSY',
  );
  static const List<WarehouseSchoolEntry> builtInSchoolEntries = [
    builtInSchoolEntry,
    mysySchoolEntry,
  ];
  static const String _builtInRootIndexAssetPath =
      'assets/warehouse/root_index.yaml';
  static const Map<String, _BuiltInWarehouseAdapter> _builtInWarehouseAdapters =
      {
        'SCUEC': _BuiltInWarehouseAdapter(
          school: builtInSchoolEntry,
          adapterId: 'SCUEC',
          adapterIndexAssetPath: 'assets/warehouse/SCUEC/adapters.yaml',
          scriptAssetPath: 'assets/warehouse/SCUEC/scuec.js',
        ),
        'MYSY': _BuiltInWarehouseAdapter(
          school: mysySchoolEntry,
          adapterId: 'MYSY',
          adapterIndexAssetPath: 'assets/warehouse/MYSY/adapters.yaml',
          scriptAssetPath: 'assets/warehouse/MYSY/mysy.js',
        ),
      };

  final WarehouseAssetLoader _assetLoader;

  WarehouseRepositoryService({
    WarehouseAssetLoader? assetLoader,
  }) : _assetLoader = assetLoader ?? _loadBundledAsset;

  static Future<List<int>> _loadBundledAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static void _log(String message) {
    appDebugLog('WarehouseService', '${formatLogTimestamp()} $message');
  }

  /// 读取内置学校列表。
  ///
  /// [source] 与 [options] 仅为兼容既有调用签名保留，不再被使用：
  /// 学校列表永远来自打包 assets。
  Future<WarehouseRootIndex> fetchRootIndex(
    WarehouseRepositorySource source, {
    WarehouseFetchOptions? options,
  }) async {
    _log('读取内置学校列表 assets=$_builtInRootIndexAssetPath');
    return _withBuiltInSchools(
      _parseRootIndex(await _loadAssetText(_builtInRootIndexAssetPath)),
    );
  }

  /// 读取指定学校的适配器列表；仅内置学校有索引，其余返回
  /// `warehouse_no_adapters`。
  Future<WarehouseAdaptersIndex> fetchAdaptersIndex(
    WarehouseRepositorySource source,
    WarehouseSchoolEntry school, {
    WarehouseFetchOptions? options,
  }) async {
    final builtInAdapter = _builtInAdapterForSchool(school);
    if (builtInAdapter == null) {
      _log('${school.name} 无内置适配器索引');
      throw WarehouseRepositoryException(
        encodeServiceMessage('warehouse_no_adapters', {
          'schoolName': school.name,
        }),
      );
    }
    _log('读取 ${school.name} 内置适配器索引');
    return _parseAdaptersIndex(
      await _loadAssetText(builtInAdapter.adapterIndexAssetPath),
      schoolName: school.name,
    );
  }

  /// 读取适配脚本；仅内置适配器有脚本，其余返回
  /// `warehouse_no_adapters`。
  Future<String> fetchAdapterScript(
    WarehouseRepositorySource source, {
    required WarehouseSchoolEntry school,
    required WarehouseAdapterEntry adapter,
    WarehouseFetchOptions? options,
  }) async {
    final builtInAdapter = _builtInAdapterForSchool(school);
    if (builtInAdapter == null ||
        !_isBuiltInAdapter(builtInAdapter, adapter)) {
      _log('${school.name}/${adapter.adapterId} 无内置适配脚本');
      throw WarehouseRepositoryException(
        encodeServiceMessage('warehouse_no_adapters', {
          'schoolName': school.name,
        }),
      );
    }
    _log('读取 ${school.name} 内置适配脚本');
    return _decodeAdapterScript(
      await _assetLoader(builtInAdapter.scriptAssetPath),
      adapter,
    );
  }

  WarehouseRootIndex _withBuiltInSchools(WarehouseRootIndex index) {
    final schoolIds = index.schools
        .map((school) => school.id.toUpperCase())
        .toSet();
    final missingSchools = builtInSchoolEntries
        .where((school) => !schoolIds.contains(school.id.toUpperCase()))
        .toList(growable: false);
    if (missingSchools.isEmpty) {
      return index;
    }
    return WarehouseRootIndex(schools: [...index.schools, ...missingSchools]);
  }

  _BuiltInWarehouseAdapter? _builtInAdapterForSchool(
    WarehouseSchoolEntry school,
  ) {
    final byId = _builtInWarehouseAdapters[school.id.toUpperCase()];
    if (byId != null) {
      return byId;
    }
    final resourceFolder = school.resourceFolder.toUpperCase();
    for (final adapter in _builtInWarehouseAdapters.values) {
      if (adapter.school.resourceFolder.toUpperCase() == resourceFolder) {
        return adapter;
      }
    }
    return null;
  }

  bool _isBuiltInAdapter(
    _BuiltInWarehouseAdapter builtInAdapter,
    WarehouseAdapterEntry adapter,
  ) {
    final scriptFileName = builtInAdapter.scriptAssetPath.split('/').last;
    return adapter.adapterId.toUpperCase() ==
            builtInAdapter.adapterId.toUpperCase() &&
        adapter.assetJsPath.toLowerCase() == scriptFileName.toLowerCase();
  }

  Future<String> _loadAssetText(String assetPath) async {
    return utf8.decode(await _assetLoader(assetPath));
  }

  String _decodeAdapterScript(List<int> bytes, WarehouseAdapterEntry adapter) {
    // 完整性闸门保留：索引里声明了 sha256 就必须与脚本字节一致。
    // 脚本与索引现在都来自打包 assets，该校验退化为一致性断言，
    // 但仍能挡住打包流程把索引与脚本对错版本的回归。
    final declared = adapter.sha256.trim().toLowerCase();
    if (declared.isNotEmpty) {
      final actual = sha256.convert(bytes).toString();
      if (actual != declared) {
        _log('脚本 SHA-256 校验失败：声明 $declared，实际 $actual');
        throw const WarehouseRepositoryException(
          'warehouse_script_checksum_failed',
        );
      }
    }
    return utf8.decode(bytes);
  }
}

WarehouseRootIndex _parseRootIndex(String content) {
  final maps = _parseYamlListMaps(content, topLevelKey: 'schools');
  final schools = maps
      .map(
        (item) => WarehouseSchoolEntry(
          id: item['id'] ?? '',
          name: item['name'] ?? '',
          initial: item['initial'] ?? '',
          resourceFolder: item['resource_folder'] ?? '',
        ),
      )
      .where(
        (item) =>
            item.id.isNotEmpty &&
            item.name.isNotEmpty &&
            item.resourceFolder.isNotEmpty,
      )
      .toList(growable: false);
  if (schools.isEmpty) {
    throw const WarehouseRepositoryException('warehouse_no_schools_index');
  }
  return WarehouseRootIndex(schools: schools);
}

WarehouseAdaptersIndex _parseAdaptersIndex(
  String content, {
  required String schoolName,
}) {
  final maps = _parseYamlListMaps(content, topLevelKey: 'adapters');
  final adapters = maps
      .map(
        (item) => WarehouseAdapterEntry(
          adapterId: item['adapter_id'] ?? '',
          adapterName: item['adapter_name'] ?? '',
          category: item['category'] ?? '',
          assetJsPath: item['asset_js_path'] ?? '',
          importUrl: item['import_url'] ?? '',
          maintainer: item['maintainer'] ?? '',
          description: item['description'] ?? '',
          sha256: item['sha256'] ?? '',
        ),
      )
      .where((item) => item.adapterId.isNotEmpty && item.assetJsPath.isNotEmpty)
      .toList(growable: false);
  if (adapters.isEmpty) {
    throw WarehouseRepositoryException(
      encodeServiceMessage('warehouse_no_adapters', {'schoolName': schoolName}),
    );
  }
  return WarehouseAdaptersIndex(adapters: adapters);
}

List<Map<String, String>> _parseYamlListMaps(
  String content, {
  required String topLevelKey,
}) {
  final lines = content.split(RegExp(r'\r?\n'));
  final items = <Map<String, String>>[];
  var inTargetSection = false;
  Map<String, String>? current;

  for (final rawLine in lines) {
    final normalizedLine = rawLine.replaceAll('\t', '  ');
    final trimmed = normalizedLine.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    if (!inTargetSection) {
      if (trimmed == '$topLevelKey:') {
        inTargetSection = true;
      }
      continue;
    }

    final indent = normalizedLine.length - normalizedLine.trimLeft().length;
    if (indent == 0 && trimmed.endsWith(':')) {
      break;
    }

    if (indent == 2 && trimmed.startsWith('- ')) {
      if (current != null && current.isNotEmpty) {
        items.add(current);
      }
      current = <String, String>{};
      final pair = trimmed.substring(2).trim();
      if (pair.isNotEmpty) {
        final entry = _parseYamlPair(pair);
        if (entry != null) {
          current[entry.key] = entry.value;
        }
      }
      continue;
    }

    if (indent >= 4 && current != null) {
      final entry = _parseYamlPair(trimmed);
      if (entry != null) {
        current[entry.key] = entry.value;
      }
    }
  }

  if (current != null && current.isNotEmpty) {
    items.add(current);
  }

  return items;
}

MapEntry<String, String>? _parseYamlPair(String line) {
  final separatorIndex = line.indexOf(': ');
  if (separatorIndex <= 0) {
    return null;
  }
  final key = line.substring(0, separatorIndex).trim();
  var value = line.substring(separatorIndex + 2).trim();
  value = _stripInlineComment(value);
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    value = value.substring(1, value.length - 1);
  }
  return MapEntry(key, _decodeEscapedYamlText(value.trim()));
}

String _stripInlineComment(String value) {
  if (value.isEmpty || !value.contains('#')) {
    return value;
  }
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
    } else if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
    }
    if (char == '#' && !inSingleQuote && !inDoubleQuote) {
      break;
    }
    buffer.write(char);
  }
  return buffer.toString().trimRight();
}

String _decodeEscapedYamlText(String value) {
  return value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t');
}
