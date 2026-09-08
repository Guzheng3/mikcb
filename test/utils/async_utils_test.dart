import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetable/utils/async_utils.dart';

void main() {
  group('buildMirrorCandidateUrls', () {
    test('puts the selected mirror first and keeps the original last', () {
      final candidates = buildMirrorCandidateUrls(
        'github.com/Mutx163/qingyu_warehouse',
        selectedMirrorPrefix: 'https://mirror.example.com/',
      );

      expect(
        candidates.first,
        'https://mirror.example.com/github.com/Mutx163/qingyu_warehouse',
      );
      expect(candidates.last, 'github.com/Mutx163/qingyu_warehouse');
    });

    test('does not duplicate mirror candidates', () {
      final prefix = allBuiltinMirrorUrlPrefixes.first;
      final candidates = buildMirrorCandidateUrls(
        'github.com/Mutx163/qingyu_warehouse',
        selectedMirrorPrefix: prefix,
      );

      expect(candidates.where((url) => url.startsWith(prefix)).length, 1);
    });
  });
}
