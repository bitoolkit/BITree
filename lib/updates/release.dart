import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../core/diagnostics.dart';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.url,
    required this.downloadUrl,
    required this.notes,
    required this.isDevelopment,
  });

  factory AppRelease.fromGitHub(
    Map<String, dynamic> release, {
    required Abi abi,
    String? version,
  }) {
    final url = Uri.parse(release['html_url'] as String);
    var downloadUrl = url;
    final architecture = switch (abi) {
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidX64 => 'x86_64',
      _ => null,
    };
    if (architecture != null) {
      final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
      for (final suffix in ['', '-debug-signed']) {
        final asset = assets
            .where(
              (asset) => (asset['name'] as String).endsWith(
                '-android-$architecture$suffix.apk',
              ),
            )
            .firstOrNull;
        if (asset != null) {
          downloadUrl = Uri.parse(asset['browser_download_url'] as String);
          break;
        }
      }
    }
    return AppRelease(
      version: version ?? release['tag_name'] as String,
      url: url,
      downloadUrl: downloadUrl,
      notes: release['body'] as String? ?? '',
      isDevelopment: release['prerelease'] == true,
    );
  }

  final String version;
  final Uri url;
  final Uri downloadUrl;
  final String notes;
  final bool isDevelopment;
}

Future<List<AppRelease>> availableAppReleases(
  String installed, {
  DateTime? builtAt,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  try {
    final [stable, releases] = await Future.wait([
      _readJson(
        client,
        Uri.https('api.github.com', '/repos/so1ve/bitree/releases/latest'),
      ),
      _readJson(
        client,
        Uri.https('api.github.com', '/repos/so1ve/bitree/releases'),
      ),
    ]);
    final dev = (releases as List?)
        ?.cast<Map<String, dynamic>>()
        .where(
          (release) =>
              release['prerelease'] == true &&
              RegExp(r'^v\d+\.\d+\.\d+-dev$')
                  .hasMatch(release['tag_name'] as String),
        )
        .firstOrNull;
    final stableUpdate = _stableUpdate(
      stable as Map<String, dynamic>?,
      installed,
      builtAt: builtAt,
    );
    final developmentUpdate = await _developmentUpdate(
      client,
      dev,
      installed,
      builtAt: builtAt,
    );

    return await Future.wait([
      for (final update in [?stableUpdate, ?developmentUpdate])
        _withUpdateNotes(client, update, installed),
    ]);
  } finally {
    client.close(force: true);
  }
}

AppRelease? _stableUpdate(
  Map<String, dynamic>? release,
  String installed, {
  DateTime? builtAt,
}) {
  final normalized = installed.replaceFirst(RegExp(r'^v'), '');
  final current = Version.parse(normalized.split('-').first);
  if (release == null ||
      release['draft'] == true ||
      release['prerelease'] == true) {
    return null;
  }

  final tag = release['tag_name'] as String;
  final version = Version.parse(tag.replaceFirst(RegExp(r'^v'), ''));
  final development = normalized.contains('-');
  final releasedAfterBuild =
      development &&
      builtAt != null &&
      DateTime.parse(release['published_at'] as String).isAfter(builtAt);
  final newer =
      version > current ||
      (development && version == current) ||
      releasedAfterBuild;
  if (version.isPreRelease || !newer) return null;

  return AppRelease.fromGitHub(release, abi: Abi.current());
}

Future<AppRelease?> _developmentUpdate(
  HttpClient client,
  Map<String, dynamic>? release,
  String installed, {
  DateTime? builtAt,
}) async {
  if (release == null || release['draft'] == true) return null;

  final suffix = '-${Platform.operatingSystem}-update.json';
  final asset = (release['assets'] as List)
      .cast<Map<String, dynamic>>()
      .where((asset) => (asset['name'] as String).endsWith(suffix))
      .firstOrNull;
  if (asset == null) return null;

  final metadata = await _readJson(
    client,
    Uri.parse(asset['browser_download_url'] as String),
  ) as Map<String, dynamic>?;
  if (metadata == null) return null;

  final version = metadata['version'] as String;
  final publishedBuildTime = DateTime.parse(metadata['builtAt'] as String);
  final newer = builtAt == null
      ? version != installed
      : publishedBuildTime.isAfter(builtAt);
  if (!newer) return null;

  return AppRelease.fromGitHub(release, abi: Abi.current(), version: version);
}

String _revision(String version) =>
    RegExp(r'-(?:dev\.)?([0-9a-f]{7,40})$').firstMatch(version)?[1] ??
    (version.startsWith('v') ? version : 'v$version');

Future<AppRelease> _withUpdateNotes(
  HttpClient client,
  AppRelease release,
  String installed,
) async {
  String notes;
  try {
    notes = await _updateNotes(
      client,
      _revision(installed),
      _revision(release.version),
    );
  } catch (failure, stack) {
    AppDiagnostics.instance.error('读取 ${release.version} 更新日志', failure, stack);
    notes = '更新说明暂时无法读取，请查看发布页。';
  }
  return AppRelease(
    version: release.version,
    url: release.url,
    downloadUrl: release.downloadUrl,
    notes: notes,
    isDevelopment: release.isDevelopment,
  );
}

Future<String> _updateNotes(HttpClient client, String base, String head) async {
  const previewCount = 6;
  const pageSize = 100;
  const unchanged = '此版本没有新增代码变更，完整说明见发布页。';
  if (base == head) return unchanged;

  Future<Map<String, dynamic>> readPage(int page) async {
    final url = Uri.https(
      'api.github.com',
      '/repos/so1ve/bitree/compare/$base...$head',
      {'per_page': '$pageSize', 'page': '$page'},
    );
    final comparison = await _readJson(client, url) as Map<String, dynamic>?;
    if (comparison == null) {
      throw HttpException('找不到版本比较记录。', uri: url);
    }
    return comparison;
  }

  final first = await readPage(1);
  final total = first['total_commits'] as int;
  if (total == 0) return unchanged;

  var commits = (first['commits'] as List).cast<Map<String, dynamic>>();
  if (total > pageSize) {
    final lastPage = (total + pageSize - 1) ~/ pageSize;
    final last = await readPage(lastPage);
    commits = (last['commits'] as List).cast<Map<String, dynamic>>();
    if (commits.length < previewCount) {
      final previous = lastPage == 2 ? first : await readPage(lastPage - 1);
      commits = [
        ...(previous['commits'] as List).cast<Map<String, dynamic>>(),
        ...commits,
      ];
    }
  }

  final preview = commits.reversed.take(previewCount).toList();
  final notes = [
    for (final commit in preview)
      '- ${((commit['commit'] as Map)['message'] as String).split('\n').first} '
          '([${(commit['sha'] as String).substring(0, 7)}](${commit['html_url']}))',
    if (total > preview.length)
      '\n另有 ${total - preview.length} 项变更，'
          '[查看完整变更](https://github.com/so1ve/bitree/compare/$base...$head)。',
  ];
  return notes.join('\n');
}

Future<Object?> _readJson(HttpClient client, Uri url) async {
  final request = await client.getUrl(url).timeout(const Duration(seconds: 15));
  request.headers
    ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
    ..set(HttpHeaders.userAgentHeader, 'BITree')
    ..set('X-GitHub-Api-Version', '2022-11-28');

  final response = await request.close().timeout(const Duration(seconds: 15));
  if (response.statusCode == HttpStatus.notFound) return null;
  if (response.statusCode == HttpStatus.forbidden ||
      response.statusCode == HttpStatus.tooManyRequests) {
    throw const HttpException('检查更新次数过多，请稍后重试。');
  }
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('GitHub 暂时无法提供更新信息（${response.statusCode}）。');
  }

  final text = await response
      .transform(utf8.decoder)
      .join()
      .timeout(const Duration(seconds: 15));
  return jsonDecode(text);
}
