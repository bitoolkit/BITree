import 'dart:io';

import 'package:bitree/school/network.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sends the real HTTP client to a local server instead of school services.
class LocalSchoolNetwork extends HttpOverrides {
  LocalSchoolNetwork(this.port);

  final int port;
  final clients = <LocalSchoolClient>[];

  LocalSchoolClient clientFor(SchoolNetwork network) => clients.firstWhere(
    (client) =>
        client.firstUrl?.host ==
        (network == SchoolNetwork.webvpn
            ? 'webvpn.bit.edu.cn'
            : 'jxzxehallapp.bit.edu.cn'),
  );

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = LocalSchoolClient(super.createHttpClient(context), port);
    clients.add(client);
    return client;
  }
}

class LocalSchoolClient extends Fake implements HttpClient {
  LocalSchoolClient(this.delegate, this.port);

  final HttpClient delegate;
  final int port;
  Uri? firstUrl;
  bool closed = false;

  @override
  set connectionTimeout(Duration? timeout) =>
      delegate.connectionTimeout = timeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    firstUrl ??= url;
    return delegate.openUrl(
      method,
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/${url.host}${url.path}',
        query: url.hasQuery ? url.query : null,
      ),
    );
  }

  @override
  void close({bool force = false}) {
    closed = true;
    delegate.close(force: force);
  }
}
