import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_http_client.dart';
import 'withu_couple_config.dart';

class WithuCoupleAvatarCacheResult {
  const WithuCoupleAvatarCacheResult({
    required this.path,
    required this.changed,
  });

  final String? path;
  final bool changed;
}

/// Keeps withU avatars on disk so menus can render the previous image before
/// the next background check completes.
class WithuCoupleAvatarCache {
  WithuCoupleAvatarCache({
    http.Client? client,
    Future<Directory> Function()? directoryFactory,
  }) : _client = client ?? createAppHttpClient(),
       _directoryFactory =
           directoryFactory ?? getApplicationDocumentsDirectory {
    _ownsClient = client == null && !isSharedAppHttpClient(_client);
  }

  static const int _maxAvatarBytes = 8 * 1024 * 1024;

  final http.Client _client;
  final Future<Directory> Function() _directoryFactory;
  final Map<String, String> _cachedPaths = {};
  final Map<String, Future<WithuCoupleAvatarCacheResult?>> _pending = {};
  late final bool _ownsClient;
  Directory? _directory;

  static Uri resolveUri(String baseUrl, String? source) {
    final base =
        Uri.tryParse(baseUrl.trim()) ??
        Uri.parse(WithuCoupleConfig.defaultBaseUrl);
    final avatar = (source ?? '').trim();
    if (avatar.isEmpty) {
      return base.resolve('/assets/images/default-avatar.svg');
    }
    try {
      return base.resolve(avatar);
    } on FormatException {
      return base.resolve('/assets/images/default-avatar.svg');
    }
  }

  Future<String?> cachedPath(Uri? uri) async {
    if (uri == null) {
      return null;
    }

    final key = _keyFor(uri);
    final knownPath = _cachedPaths[key];
    if (knownPath != null) {
      return knownPath;
    }
    return _existingPath(uri, key);
  }

  Future<WithuCoupleAvatarCacheResult?> refresh(Uri? uri) {
    if (uri == null) {
      return Future<WithuCoupleAvatarCacheResult?>.value();
    }

    final key = _keyFor(uri);
    final pending = _pending[key];
    if (pending != null) {
      return pending;
    }

    final future = _refresh(uri, key).whenComplete(() {
      _pending.remove(key);
    });
    _pending[key] = future;
    return future;
  }

  Future<WithuCoupleAvatarCacheResult?> _refresh(Uri uri, String key) async {
    try {
      return await _fetch(uri, key);
    } catch (_) {
      // A failed avatar check keeps the last successfully downloaded image.
      String? path;
      try {
        path = await _existingPath(uri, key);
      } catch (_) {
        path = null;
      }
      return WithuCoupleAvatarCacheResult(path: path, changed: false);
    }
  }

  Future<WithuCoupleAvatarCacheResult?> _fetch(Uri uri, String key) async {
    final directory = await _ensureDirectory();
    final file = File('${directory.path}/$key');
    final existingBytes = await _readBytes(file);
    final validators = await _readValidators(key);

    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'image/*, image/svg+xml';
    final etag = validators['etag'];
    final lastModified = validators['lastModified'];
    if (etag != null && etag.isNotEmpty) {
      request.headers['If-None-Match'] = etag;
    }
    if (lastModified != null && lastModified.isNotEmpty) {
      request.headers['If-Modified-Since'] = lastModified;
    }

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 304 && existingBytes != null) {
      return WithuCoupleAvatarCacheResult(path: file.path, changed: false);
    }
    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty ||
        response.bodyBytes.length > _maxAvatarBytes) {
      return WithuCoupleAvatarCacheResult(
        path: existingBytes == null ? null : file.path,
        changed: false,
      );
    }

    final hasChanged =
        existingBytes == null ||
        !_bytesEqual(existingBytes, response.bodyBytes);
    if (!hasChanged) {
      await _writeValidators(key, response);
      return WithuCoupleAvatarCacheResult(path: file.path, changed: false);
    }

    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsBytes(response.bodyBytes, flush: true);
    await tempFile.rename(file.path);
    await _writeValidators(key, response);
    PaintingBinding.instance.imageCache.evict(FileImage(file));
    _cachedPaths[key] = file.path;
    return WithuCoupleAvatarCacheResult(path: file.path, changed: true);
  }

  Future<Directory> _ensureDirectory() async {
    final directory = _directory;
    if (directory != null) {
      return directory;
    }

    final baseDirectory = await _directoryFactory();
    final avatarDirectory = Directory('${baseDirectory.path}/withu_avatars');
    await avatarDirectory.create(recursive: true);
    _directory = avatarDirectory;
    return avatarDirectory;
  }

  Future<String?> _existingPath(Uri uri, String key) async {
    final directory = await _ensureDirectory();
    final file = File('${directory.path}/$key');
    if (!file.existsSync()) {
      return null;
    }
    _cachedPaths[key] = file.path;
    return file.path;
  }

  Future<Map<String, String>> _readValidators(String key) async {
    try {
      final directory = await _ensureDirectory();
      final file = File('${directory.path}/$key.json');
      if (!file.existsSync()) {
        return const <String, String>{};
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <String, String>{};
      }
      return {
        for (final entry in Map<String, dynamic>.from(decoded).entries)
          if (entry.value is String && (entry.value as String).isNotEmpty)
            entry.key: entry.value as String,
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<void> _writeValidators(String key, http.Response response) async {
    final validators = <String, String>{
      if (response.headers['etag']?.isNotEmpty ?? false)
        'etag': response.headers['etag']!,
      if (response.headers['last-modified']?.isNotEmpty ?? false)
        'lastModified': response.headers['last-modified']!,
    };
    if (validators.isEmpty) {
      return;
    }

    final directory = await _ensureDirectory();
    final file = File('${directory.path}/$key.json');
    await file.writeAsString(jsonEncode(validators), flush: true);
  }

  Future<List<int>?> _readBytes(File file) async {
    try {
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  String _keyFor(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
