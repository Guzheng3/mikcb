class WarehouseRepositoryException implements Exception {
  final String message;

  const WarehouseRepositoryException(this.message);

  @override
  String toString() => 'WarehouseRepositoryException: $message';
}

/// 适配资源的对外地址来源。
///
/// 应用当前只读取打包进 assets 的适配资源，不发起任何网络请求；这里仅用于
/// 拼出对外可访问的脚本地址（调试页的「复制脚本地址」）。
class WarehouseRepositorySource {
  static const String defaultBaseUrl = 'https://gzr.xjy.xn--6qq986b3xl';

  final String baseUrl;

  const WarehouseRepositorySource({this.baseUrl = defaultBaseUrl});

  Uri buildFileUri(String relativePath) {
    final normalizedPath = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base/$normalizedPath');
  }

  String get repositoryUrl => baseUrl;
}

class WarehouseSchoolEntry {
  final String id;
  final String name;
  final String initial;
  final String resourceFolder;

  const WarehouseSchoolEntry({
    required this.id,
    required this.name,
    required this.initial,
    required this.resourceFolder,
  });
}

class WarehouseRootIndex {
  final List<WarehouseSchoolEntry> schools;

  const WarehouseRootIndex({required this.schools});
}

class WarehouseAdapterEntry {
  final String adapterId;
  final String adapterName;
  final String category;
  final String assetJsPath;
  final String importUrl;
  final String maintainer;
  final String description;

  /// 适配器脚本的 SHA-256（小写十六进制），由仓库 adapters.yaml 声明。
  /// 为空表示索引未提供校验和（旧版索引），拉取时跳过完整性校验。
  final String sha256;

  const WarehouseAdapterEntry({
    required this.adapterId,
    required this.adapterName,
    required this.category,
    required this.assetJsPath,
    required this.importUrl,
    required this.maintainer,
    required this.description,
    this.sha256 = '',
  });
}

class WarehouseAdaptersIndex {
  final List<WarehouseAdapterEntry> adapters;

  const WarehouseAdaptersIndex({required this.adapters});
}
