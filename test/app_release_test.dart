import 'dart:ffi';

import 'package:bitree/updates/release.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _release(
  List<String> names, {
  bool development = false,
}) => {
  'tag_name': development ? 'v0.2.0-dev' : 'v0.2.0',
  'html_url': 'https://github.com/bitoolkit/bitree/releases/tag/v0.2.0',
  'body': '更新说明',
  'prerelease': development,
  'assets': [
    for (final name in names)
      {'name': name, 'browser_download_url': 'https://downloads.example/$name'},
  ],
};

void main() {
  for (final (abi, architecture) in [
    (Abi.androidArm, 'armeabi-v7a'),
    (Abi.androidArm64, 'arm64-v8a'),
    (Abi.androidX64, 'x86_64'),
  ]) {
    for (final suffix in ['', '-debug-signed']) {
      test('Selects $architecture APK with suffix "$suffix"', () {
        final release = AppRelease.fromGitHub(
          _release([
            for (final architecture in ['armeabi-v7a', 'arm64-v8a', 'x86_64'])
              'BITree-v0.2.0-android-$architecture$suffix.apk',
            'BITree-v0.2.0-android.aab',
            'BITree-v0.2.0-windows-x64-setup-unsigned.exe',
          ]),
          abi: abi,
        );
        expect(
          release.downloadUrl.path,
          endsWith('-android-$architecture$suffix.apk'),
        );
        expect(release.url.path, '/bitoolkit/bitree/releases/tag/v0.2.0');
        expect(release.version, 'v0.2.0');
        expect(release.notes, '更新说明');
      });
    }
  }

  test('Prefers the release-signed APK when both signing variants exist', () {
    final release = AppRelease.fromGitHub(
      _release([
        'BITree-v0.2.0-android-arm64-v8a-debug-signed.apk',
        'BITree-v0.2.0-android-arm64-v8a.apk',
      ]),
      abi: Abi.androidArm64,
    );
    expect(release.downloadUrl.path, endsWith('-android-arm64-v8a.apk'));
  });

  test(
    'Missing matching APK uses the release page, never another architecture',
    () {
      final data = _release(['BITree-v0.2.0-android-x86_64.apk']);
      for (final abi in [
        Abi.androidArm64,
        Abi.androidArm,
        Abi.linuxX64,
        Abi.iosArm64,
      ]) {
        final release = AppRelease.fromGitHub(data, abi: abi);
        expect(release.downloadUrl, release.url);
      }
    },
  );

  test('Development metadata version preserves its release page and APK', () {
    final release = AppRelease.fromGitHub(
      _release([
        'BITree-v0.2.0-abc1234-android-arm64-v8a.apk',
      ], development: true),
      abi: Abi.androidArm64,
      version: 'v0.2.0-abc1234',
    );
    expect(release.version, 'v0.2.0-abc1234');
    expect(release.isDevelopment, isTrue);
    expect(release.downloadUrl.path, endsWith('abc1234-android-arm64-v8a.apk'));
  });
}
