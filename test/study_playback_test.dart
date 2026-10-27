import 'dart:convert';
import 'dart:io';

import 'package:bitree/study/media.dart';
import 'package:bitree/study/playback.dart';
import 'package:flutter_test/flutter_test.dart';

class _NativeHttp extends HttpOverrides {}

void main() {
  test('Recorded HLS retains media suffixes and reads beyond the first segment', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      const streams = LectureStreams(
        urls: {},
        signing: (user: '1', tenant: '21', phone: '123'),
      );
      final segments = <int>[];
      origin.listen((request) async {
        expect(request.headers.value('Referer'), streams.referer);
        final uri = request.uri;
        final signature = uri.queryParameters['t']!;
        final at = DateTime.fromMillisecondsSinceEpoch(
          int.parse(signature.split('-')[1]) * 1000,
        );
        expect(streams.sign(uri, at: at).queryParameters['t'], signature);
        if (uri.path.endsWith('.m3u8')) {
          expect(request.headers.value('Range'), isNull);
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          if (uri.path.endsWith('master.m3u8')) {
            expect(uri.queryParameters['client_uuid'], 'keep-me');
            request.response.write(
              '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100000\nvideo/index.m3u8\n',
            );
          } else {
            request.response.write(
              '#EXTM3U\n#EXT-X-TARGETDURATION:20\n#EXT-X-MEDIA-SEQUENCE:0\n',
            );
            for (var index = 0; index < 6; index++) {
              request.response.write('#EXTINF:20,\n$index.ts\n');
            }
            request.response.write('#EXT-X-ENDLIST\n');
          }
        } else {
          final index = int.parse(uri.pathSegments.last.split('.').first);
          segments.add(index);
          request.response.add([index, 0, 255]);
        }
        await request.response.close();
      });
      final proxy = StudyMediaProxy();
      addTearDown(proxy.close);
      final client = HttpClient();
      addTearDown(client.close);
      Future<String> playlist(Uri url) async {
        expect(url.path, endsWith('.m3u8'));
        final request = await client.getUrl(url);
        request.headers.set('Range', 'bytes=0-');
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        return utf8.decoder.bind(response).join();
      }

      final root = await proxy.open(
        Uri.parse(
          'http://127.0.0.1:${origin.port}/play/master.m3u8?client_uuid=keep-me',
        ),
        streams,
      );
      final variant = Uri.parse((await playlist(root)).trim().split('\n').last);
      final media = await playlist(variant);
      expect(media, contains('#EXT-X-ENDLIST'));
      final urls = const LineSplitter()
          .convert(media)
          .where((line) => line.isNotEmpty && !line.startsWith('#'));
      for (final line in urls) {
        final url = Uri.parse(line);
        expect(url.path, endsWith('.ts'));
        final response = await (await client.getUrl(url)).close();
        expect(
          await response.fold<List<int>>(
            [],
            (result, chunk) => result..addAll(chunk),
          ),
          [segments.last, 0, 255],
        );
      }
      expect(segments, [0, 1, 2, 3, 4, 5]);
    }, _NativeHttp());
  });

  test(
    'Progressive recordings preserve HEAD, byte ranges and upstream failures',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final bytes = List.generate(256, (i) => i);
        final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => origin.close(force: true));
        origin.listen((request) async {
          if (request.uri.path == '/missing.m3u8') {
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write('expired');
          } else {
            request.response.headers.contentType = ContentType('video', 'mp4');
            request.response.headers.set('Accept-Ranges', 'bytes');
            final range = request.headers.value('Range');
            if (range != null) {
              expect(range, 'bytes=100-119');
              request.response.statusCode = HttpStatus.partialContent;
              request.response.headers.set(
                'Content-Range',
                'bytes 100-119/256',
              );
              request.response.contentLength = 20;
              request.response.add(bytes.sublist(100, 120));
            } else {
              request.response.contentLength = bytes.length;
              if (request.method != 'HEAD') request.response.add(bytes);
            }
          }
          await request.response.close();
        });
        final proxy = StudyMediaProxy();
        addTearDown(proxy.close);
        final client = HttpClient();
        addTearDown(client.close);
        Future<Uri> open(String name) => proxy.open(
          Uri.parse('http://127.0.0.1:${origin.port}/$name'),
          const LectureStreams(urls: {}),
        );
        final url = await open('screen.mp4');
        expect(url.path, endsWith('.mp4'));
        final head = await (await client.headUrl(url)).close();
        expect(head.contentLength, 256);
        expect(head.headers.value('Accept-Ranges'), 'bytes');
        expect(await head.toList(), isEmpty);
        final request = await client.getUrl(url);
        request.headers.set('Range', 'bytes=100-119');
        final response = await request.close();
        expect(response.statusCode, HttpStatus.partialContent);
        expect(response.contentLength, 20);
        expect(response.headers.value('Content-Range'), 'bytes 100-119/256');
        expect(
          await response.fold<List<int>>(
            [],
            (result, chunk) => result..addAll(chunk),
          ),
          bytes.sublist(100, 120),
        );
        final missing = await (await client.getUrl(await open('missing.m3u8')))
            .close();
        expect(missing.statusCode, HttpStatus.forbidden);
        expect(await utf8.decoder.bind(missing).join(), 'expired');
      }, _NativeHttp());
    },
  );
}
