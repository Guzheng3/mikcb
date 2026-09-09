import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'home_page_background.dart';

/// Owns pre-decoded home wallpaper images for synchronous first-frame paint.
final class HomePageBackdropImageStore {
  HomePageBackdropImageStore._();

  static const Duration decodeBudget = Duration(seconds: 8);

  static final HomePageBackdropImageStore instance =
      HomePageBackdropImageStore._();

  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image?>> _loading = {};

  ui.Image? imageFor(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    return _images[path];
  }

  Future<ui.Image?> load(String? path, {Duration? timeout}) {
    if (path == null || path.isEmpty) {
      return Future<ui.Image?>.value();
    }
    final cached = _images[path];
    if (cached != null) {
      return Future<ui.Image?>.value(cached);
    }
    return _loading.putIfAbsent(path, () => _decode(path, timeout));
  }

  Future<ui.Image?> _decode(String path, Duration? timeout) async {
    try {
      final wallpaperFuture = _decodeWallpaper(path);
      final image = timeout == null
          ? await wallpaperFuture
          : await wallpaperFuture.timeout(timeout);
      if (image != null) {
        _images[path] = image;
      }
      return image;
    } catch (_) {
      return null;
    } finally {
      _loading.remove(path);
    }
  }

  Future<ui.Image?> _decodeWallpaper(String path) async {
    final assetName = bundledHomePageWallpaperAssetName(path);
    final ui.ImmutableBuffer buffer;
    if (assetName != null) {
      final data = await rootBundle.load(assetName);
      buffer = await ui.ImmutableBuffer.fromUint8List(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } else {
      if (!File(path).existsSync()) {
        return null;
      }
      buffer = await ui.ImmutableBuffer.fromFilePath(path);
    }

    // instantiateImageCodecFromBuffer owns and disposes the buffer.
    final codec = await ui.instantiateImageCodecFromBuffer(
      buffer,
      targetWidth: homePageBackdropDecodeWidth(),
      allowUpscaling: false,
    );

    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  void evict(String? path) {
    if (path == null || path.isEmpty) {
      return;
    }
    _loading.remove(path);
    _images.remove(path)?.dispose();
  }
}
