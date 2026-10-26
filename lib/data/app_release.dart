import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.url,
    required this.notes,
    required this.isDevelopment,
  });

  final String version;
  final Uri url;
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

    return [?stableUpdate, ?developmentUpdate];
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

  return AppRelease(
    version: tag,
    url: Uri.parse(release['html_url'] as String),
    notes: release['body'] as String? ?? '',
    isDevelopment: false,
  );
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

  return AppRelease(
    version: version,
    url: Uri.parse(release['html_url'] as String),
    notes: release['body'] as String? ?? '',
    isDevelopment: true,
  );
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
