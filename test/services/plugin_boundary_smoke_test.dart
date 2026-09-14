import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:university_timetable/services/app_migration_service.dart';
import 'package:university_timetable/utils/managed_image_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _FakeWebViewController extends PlatformWebViewController {
  // ignore: use_super_parameters, the platform interface requires a named protected constructor.
  _FakeWebViewController(PlatformWebViewControllerCreationParams params)
    : super.implementation(params);

  Uri? loadedUri;
  JavaScriptMode? javaScriptMode;
  String? userAgent;
  bool? zoomEnabled;

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loadedUri = params.uri;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    javaScriptMode = mode;
  }

  @override
  Future<void> setUserAgent(String? value) async {
    userAgent = value;
  }

  @override
  Future<void> enableZoom(bool enabled) async {
    zoomEnabled = enabled;
  }
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  // ignore: use_super_parameters, the platform interface requires a named protected constructor.
  _FakeWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(params);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey<String>('fake-webview'),
      color: Color(0xFF101820),
    );
  }
}

class _FakeWebViewPlatform extends WebViewPlatform {
  _FakeWebViewController? controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return controller = _FakeWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakeWebViewWidget(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'photo picker cancellation and byte reads use the platform seam',
    () async {
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      final documentsDirectory = await Directory.systemTemp.createTemp(
        'mikcb-plugin-smoke-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProviderChannel,
            (call) async => documentsDirectory.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        if (documentsDirectory.existsSync()) {
          await documentsDirectory.delete(recursive: true);
        }
      });

      var pickerCalls = 0;
      XFile? nextImage;
      Future<XFile?> pickImage() async {
        pickerCalls++;
        return nextImage;
      }

      final cancelled = await pickAndStoreManagedImage(
        directoryName: 'plugin-smoke-cancel',
        filePrefix: 'wallpaper',
        imagePicker: pickImage,
      );
      expect(cancelled, isNull);
      expect(pickerCalls, 1);

      final bytes = Uint8List.fromList([0, 1, 2, 3, 4]);
      final sourceFile = File(
        '${documentsDirectory.path}${Platform.pathSeparator}picked.JPG',
      );
      await sourceFile.writeAsBytes(bytes);
      nextImage = XFile(sourceFile.path);
      final directoryName =
          'plugin-smoke-${DateTime.now().microsecondsSinceEpoch}';
      final path = await pickAndStoreManagedImage(
        directoryName: directoryName,
        filePrefix: 'wallpaper',
        imagePicker: pickImage,
      );

      expect(path, isNotNull);
      final storedFile = File(path!);
      expect(storedFile.path.toLowerCase(), endsWith('.jpg'));
      expect(await storedFile.readAsBytes(), bytes);
      await storedFile.parent.delete(recursive: true);
    },
  );

  testWidgets('WebView controller loads through a replaceable platform', (
    tester,
  ) async {
    final fakePlatform = _FakeWebViewPlatform();
    WebViewPlatform.instance = fakePlatform;

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.enableZoom(true);
    await controller.setUserAgent('test-agent');
    await controller.loadRequest(Uri.parse('https://example.test/login'));

    expect(
      fakePlatform.controller?.javaScriptMode,
      JavaScriptMode.unrestricted,
    );
    expect(fakePlatform.controller?.zoomEnabled, isTrue);
    expect(fakePlatform.controller?.userAgent, 'test-agent');
    expect(
      fakePlatform.controller?.loadedUri,
      Uri.parse('https://example.test/login'),
    );

    await tester.pumpWidget(
      MaterialApp(home: WebViewWidget(controller: controller)),
    );
    expect(find.byKey(const ValueKey<String>('fake-webview')), findsOneWidget);
  });

  test('MethodChannel migration flow forwards arguments and results', () async {
    const channel = MethodChannel('vip.qinghan.withu/migration');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'findInstalledPackage' => 'com.example.legacy',
            'openPackage' => true,
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = AppMigrationService();
    expect(
      await service.findInstalledLegacyPackage(
        candidates: const ['com.example.legacy'],
      ),
      'com.example.legacy',
    );
    expect(await service.openPackage('com.example.legacy'), isTrue);
    expect(calls.map((call) => call.method), [
      'findInstalledPackage',
      'openPackage',
    ]);
    expect(calls.first.arguments, ['com.example.legacy']);
    expect(calls.last.arguments, 'com.example.legacy');
  });
}
