import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_timetable/services/withu_couple_avatar_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'keeps serving the cached file while remote bytes are unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mikcb_avatar_cache',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });

      var bytes = <int>[1, 2, 3];
      final requests = <http.Request>[];
      final cache = WithuCoupleAvatarCache(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(bytes, 200);
        }),
        directoryFactory: () async => directory,
      );
      addTearDown(cache.dispose);
      final uri = Uri.parse('https://withu.example.com/avatars/me.png');

      final first = await cache.refresh(uri);
      expect(first?.changed, isTrue);
      expect(File(first!.path!).readAsBytesSync(), bytes);

      final second = await cache.refresh(uri);
      expect(second?.changed, isFalse);
      expect(second?.path, first.path);
      expect(File(second!.path!).readAsBytesSync(), bytes);

      bytes = <int>[8, 9];
      final third = await cache.refresh(uri);
      expect(third?.changed, isTrue);
      expect(third?.path, first.path);
      expect(File(third!.path!).readAsBytesSync(), bytes);
      expect(await cache.cachedPath(uri), first.path);
    },
  );

  test('uses HTTP validators and keeps the image on a 304 response', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mikcb_avatar_cache',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    const etag = '"avatar-v1"';
    var returnNotModified = false;
    final requests = <http.Request>[];
    final cache = WithuCoupleAvatarCache(
      client: MockClient((request) async {
        requests.add(request);
        if (returnNotModified) {
          return http.Response('', 304);
        }
        return http.Response.bytes(
          const <int>[4, 5, 6],
          200,
          headers: {'etag': etag},
        );
      }),
      directoryFactory: () async => directory,
    );
    addTearDown(cache.dispose);
    final uri = Uri.parse('https://withu.example.com/avatars/partner.png');

    final first = await cache.refresh(uri);
    expect(first?.changed, isTrue);
    expect(requests.single.headers['if-none-match'], isNull);

    returnNotModified = true;
    final second = await cache.refresh(uri);
    expect(second?.changed, isFalse);
    expect(second?.path, first!.path);
    expect(File(second!.path!).readAsBytesSync(), const <int>[4, 5, 6]);
    expect(requests.last.headers['if-none-match'], etag);
  });

  test('network failures preserve the previous cache entry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mikcb_avatar_cache',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    var failNetwork = false;
    final cache = WithuCoupleAvatarCache(
      client: MockClient((request) async {
        if (failNetwork) {
          throw http.ClientException('offline');
        }
        return http.Response.bytes(const <int>[7, 8], 200);
      }),
      directoryFactory: () async => directory,
    );
    addTearDown(cache.dispose);
    final uri = Uri.parse('https://withu.example.com/avatars/old.png');

    final first = await cache.refresh(uri);
    expect(first?.changed, isTrue);

    failNetwork = true;
    final second = await cache.refresh(uri);
    expect(second?.changed, isFalse);
    expect(second?.path, first!.path);
    expect(File(second!.path!).readAsBytesSync(), const <int>[7, 8]);
  });
}
