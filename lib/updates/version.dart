import 'package:package_info_plus/package_info_plus.dart';

DateTime? get appBuildTime {
  const value = String.fromEnvironment('BITREE_BUILD_TIME');
  return value.isEmpty ? null : DateTime.parse(value);
}

Future<String> appVersion() async {
  const version = String.fromEnvironment('BITREE_VERSION');
  if (version.isNotEmpty) return version;

  return 'v${(await PackageInfo.fromPlatform()).version}';
}
