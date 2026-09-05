import 'package:flutter/foundation.dart';

/// In-memory cache for bundled raster assets used across the app.
///
/// [BundledAssetImage] populates it at render time so later frames can reuse
/// the decoded bytes without async [Image.asset] resolution races.
class BundledAssets {
  BundledAssets._();

  static const launcherIcon = 'assets/branding/launcher_icon.png';

  static final Map<String, Uint8List> _bytesByPath = {};

  static Uint8List? bytesFor(String assetPath) => _bytesByPath[assetPath];

  static void remember(String assetPath, Uint8List bytes) {
    _bytesByPath[assetPath] = bytes;
  }
}
