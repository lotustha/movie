import 'package:flutter_test/flutter_test.dart';
import 'package:movie/app/services/update_service.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('compares dotted numbers, not strings', () {
      expect(UpdateService.isNewer('1.2.0', '1.1.0'), isTrue);
      expect(UpdateService.isNewer('1.10.0', '1.9.3'), isTrue);
      expect(UpdateService.isNewer('2.0', '1.9.9'), isTrue);
    });

    test('same or older is not an update', () {
      expect(UpdateService.isNewer('1.2.0', '1.2.0'), isFalse);
      expect(UpdateService.isNewer('1.2', '1.2.0'), isFalse);
      expect(UpdateService.isNewer('1.1.9', '1.2.0'), isFalse);
    });

    test('ignores build and pre-release suffixes', () {
      expect(UpdateService.isNewer('1.2.0+7', '1.2.0+3'), isFalse);
      expect(UpdateService.isNewer('v1.3.0-beta', '1.2.0'), isTrue);
    });
  });

  group('UpdateService.parseListing', () {
    // The shape mugenstream.fun/api/apps/noonflix answers with.
    Map<String, dynamic> listing(String version, List<Map<String, dynamic>> links) =>
        {'slug': 'noonflix', 'version': version, 'links': links};
    const apk = {'platform': 'APK', 'url': 'https://mugenstream.fun/uploads/apks/noonflix-1.3.0.apk'};

    test('offers a newer version with its APK link', () {
      final u = UpdateService.parseListing(listing('1.3.0', [apk]), '1.2.0');
      expect(u?.version, '1.3.0');
      expect(u?.apkUrl, apk['url']);
    });

    test('nothing when the listing is not newer', () {
      expect(UpdateService.parseListing(listing('1.2.0', [apk]), '1.2.0'), isNull);
      expect(UpdateService.parseListing(listing('1.1.0', [apk]), '1.2.0'), isNull);
    });

    test('nothing without a usable https APK link', () {
      expect(UpdateService.parseListing(listing('1.3.0', []), '1.2.0'), isNull);
      expect(
        UpdateService.parseListing(
            listing('1.3.0', [
              {'platform': 'APK', 'url': 'http://example.com/a.apk'}
            ]),
            '1.2.0'),
        isNull,
      );
      expect(UpdateService.parseListing('not json', '1.2.0'), isNull);
    });
  });
}
