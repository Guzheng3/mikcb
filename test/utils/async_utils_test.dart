import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/utils/async_utils.dart';

void main() {
  group('buildMirrorCandidateUrls', () {
    test('puts the selected mirror first and keeps the original last', () {
      final candidates = buildMirrorCandidateUrls(
        'github.com/Guzheng3/mikcb',
        selectedMirrorPrefix: 'https://mirror.example.com/',
      );

      expect(
        candidates.first,
        'https://mirror.example.com/github.com/Guzheng3/mikcb',
      );
      expect(candidates.last, 'github.com/Guzheng3/mikcb');
    });

    test('does not duplicate mirror candidates', () {
      final prefix = allBuiltinMirrorUrlPrefixes.first;
      final candidates = buildMirrorCandidateUrls(
        'github.com/Guzheng3/mikcb',
        selectedMirrorPrefix: prefix,
      );

      expect(candidates.where((url) => url.startsWith(prefix)).length, 1);
    });
  });
}
