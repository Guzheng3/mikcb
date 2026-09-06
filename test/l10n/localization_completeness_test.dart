import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/l10n/app_localizations_zh.dart';
import 'package:university_timetable/l10n/app_localizations_en.dart';
import 'package:university_timetable/l10n/app_localizations_ja.dart';
import 'package:university_timetable/l10n/app_localizations_ko.dart';

void main() {
  group('Localization completeness', () {
    test('withuCoupleUsernameLabel exists in all supported locales', () {
      final zh = AppLocalizationsZh();
      expect(
        zh.withuCoupleUsernameLabel,
        isNotEmpty,
        reason: 'zh: withuCoupleUsernameLabel should not be empty',
      );

      final en = AppLocalizationsEn();
      expect(
        en.withuCoupleUsernameLabel,
        isNotEmpty,
        reason: 'en: withuCoupleUsernameLabel should not be empty',
      );

      final ja = AppLocalizationsJa();
      expect(
        ja.withuCoupleUsernameLabel,
        isNotEmpty,
        reason: 'ja: withuCoupleUsernameLabel should not be empty',
      );

      final ko = AppLocalizationsKo();
      expect(
        ko.withuCoupleUsernameLabel,
        isNotEmpty,
        reason: 'ko: withuCoupleUsernameLabel should not be empty',
      );
    });

    test('ARB files contain withuCoupleUsernameLabel key', () {
      final arbFiles = [
        'lib/l10n/app_zh.arb',
        'lib/l10n/app_en.arb',
        'lib/l10n/app_ja.arb',
        'lib/l10n/app_ko.arb',
        'lib/l10n/app_zh_TW.arb',
        'lib/l10n/app_zh_HK.arb',
      ];

      for (final arbFile in arbFiles) {
        final file = File(arbFile);
        if (!file.existsSync()) {
          continue;
        }

        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(
          json.containsKey('withuCoupleUsernameLabel'),
          isTrue,
          reason: '$arbFile should contain withuCoupleUsernameLabel',
        );
        expect(
          json['withuCoupleUsernameLabel'],
          isNotEmpty,
          reason: '$arbFile: withuCoupleUsernameLabel should not be empty',
        );
      }
    });
  });
}
