import 'package:bitree/school/network.dart';

import 'http.dart';

/// Sends the real HTTP client to a local server instead of school services.
class LocalSchoolNetwork extends LocalHttpOverrides {
  LocalSchoolNetwork(super.port);

  LocalHttpClient clientFor(SchoolNetwork network) => clients.firstWhere(
    (client) =>
        client.firstUrl?.host ==
        (network == SchoolNetwork.webvpn
            ? 'webvpn.bit.edu.cn'
            : 'jxzxehallapp.bit.edu.cn'),
  );
}
