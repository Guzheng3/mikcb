import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release network security config allows the MYSY HTTP portal', () {
    final xml = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    final campusBlock = RegExp(
      r'<!-- HTTP-only campus portals \(course import WebView\)\. -->.*?'
      r'</domain-config>',
      dotAll: true,
    ).firstMatch(xml);

    expect(campusBlock, isNotNull, reason: 'campus portal block is missing');
    expect(
      campusBlock!.group(0),
      contains('<domain includeSubdomains="true">mtc.edu.cn</domain>'),
      reason:
          'jw.mtc.edu.cn must be allowed for the bundled MYSY adapter; '
          'otherwise its HTTP portal fails with ERR_CLEARTEXT_NOT_PERMITTED',
    );
  });
}
