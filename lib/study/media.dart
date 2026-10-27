import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf;
import 'package:pointycastle/export.dart';

import '../core/async/cancelable_request.dart';
import '../core/diagnostics.dart';
import '../school/session.dart';
import 'model.dart';
import 'playback.dart';

/// HLS child requests need fresh path-specific signatures, including after seeks.
class StudyMediaProxy {
  HttpServer? _server;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final _targets = <String, (Uri, LectureStreams)>{};
  final _secret = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  Future<Uri> open(Uri target, LectureStreams streams) async {
    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen((request) => unawaited(_serve(request)));
    }
    return _register(target, streams);
  }

  Uri _register(Uri target, LectureStreams streams) {
    // HLS demuxers validate segment extensions, including local proxy URLs.
    final suffix = RegExp(r'\.[a-zA-Z0-9]+$').stringMatch(target.path) ?? '';
    final key = '${_targets.length}$suffix';
    _targets[key] = (target, streams);
    return Uri.http('127.0.0.1:${_server!.port}', '/$_secret/$key');
  }

  Future<void> _serve(HttpRequest incoming) async {
    try {
      final parts = incoming.uri.pathSegments;
      final item = parts.length == 2 && parts.first == _secret
          ? _targets[parts.last]
          : null;
      if (item == null || !['GET', 'HEAD'].contains(incoming.method)) {
        incoming.response.statusCode = HttpStatus.notFound;
        return;
      }
      final (url, streams) = item;
      final outgoing = await _client.openUrl(
        incoming.method,
        streams.sign(url),
      );
      outgoing.headers.set('Referer', streams.referer);
      outgoing.headers.set('User-Agent', SchoolSession.userAgent);
      outgoing.headers.set('Accept-Encoding', 'identity');
      final range = incoming.headers.value('Range');
      final playlist = url.path.endsWith('.m3u8');
      if (!playlist && range != null) outgoing.headers.set('Range', range);
      final response = await outgoing.close();
      incoming.response.statusCode = response.statusCode;
      final contentType = response.headers.contentType?.mimeType ?? '';
      if ((playlist || contentType.contains('mpegurl')) &&
          [
            HttpStatus.ok,
            HttpStatus.partialContent,
          ].contains(response.statusCode)) {
        // Rewriting changes the bytes, so an upstream byte range no longer applies.
        incoming.response.statusCode = HttpStatus.ok;
        final text = await utf8.decoder.bind(response).join();
        incoming.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        incoming.response.write(
          await rewritePlaylist(
            text,
            (reference) async =>
                _register(url.resolve(reference), streams).toString(),
          ),
        );
      } else {
        for (final name in [
          'Content-Type',
          'Content-Length',
          'Content-Range',
          'Accept-Ranges',
        ]) {
          final value = response.headers.value(name);
          if (value != null) incoming.response.headers.set(name, value);
        }
        await incoming.response.addStream(response);
      }
    } catch (failure, stack) {
      if (_server != null) {
        AppDiagnostics.instance.error('读取录播', failure, stack);
      }
      try {
        incoming.response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        /* Connection closed. */
      }
    } finally {
      try {
        await incoming.response.close();
      } catch (_) {
        /* Player stopped reading. */
      }
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    _client.close(force: true);
    await server?.close(force: true);
    _targets.clear();
  }
}

Future<String> rewritePlaylist(
  String text,
  Future<String> Function(String) resolve,
) async {
  final result = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.isEmpty) {
      result.add(line);
      continue;
    }
    if (!line.startsWith('#')) {
      result.add(await resolve(line.trim()));
      continue;
    }
    final matches = RegExp('URI="([^"]+)"').allMatches(line).toList();
    var rewritten = line;
    for (final match in matches.reversed) {
      rewritten = rewritten.replaceRange(
        match.start,
        match.end,
        'URI="${await resolve(match[1]!)}"',
      );
    }
    result.add(rewritten);
  }
  return '${result.join('\n')}\n';
}

class StudyDownloader {
  Future<File> download(
    Uri url,
    LectureStreams streams,
    Directory directory,
    CancellationToken cancellation,
    void Function(double?, String) progress,
  ) async {
    await directory.create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final detach = cancellation.onCancel(() => client.close(force: true));
    Future<File> fetch(Uri source) async {
      cancellation.check();
      final identity = source.replace(
        queryParameters: {...source.queryParameters}..remove('t'),
      );
      final hash = MD5Digest()
          .process(utf8.encode(identity.toString()))
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      final playlist = source.path.endsWith('.m3u8');
      final extension = playlist ? '.m3u8' : '.media';
      final file = File('${directory.path}/$hash$extension');
      if (await file.exists()) return file;
      final partial = File('${file.path}.part');
      final offset = playlist || !await partial.exists()
          ? 0
          : await partial.length();
      final request = await client.getUrl(streams.sign(source));
      request.headers
        ..set('Referer', streams.referer)
        ..set('User-Agent', SchoolSession.userAgent)
        ..set('Accept-Encoding', 'identity');
      if (offset > 0) request.headers.set('Range', 'bytes=$offset-');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
          offset > 0 &&
          response.headers.value('Content-Range') == 'bytes */$offset') {
        await response.drain<void>();
        return partial.rename(file.path);
      }
      if (response.statusCode >= 400) {
        await response.drain<void>();
        throw HttpException('下载录播失败（${response.statusCode}）');
      }
      if (playlist ||
          (response.headers.contentType?.mimeType.contains('mpegurl') ??
              false)) {
        final text = await utf8.decoder.bind(response).join();
        var completed = 0;
        final total = const LineSplitter()
            .convert(text)
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .length;
        final local = await rewritePlaylist(text, (reference) async {
          final part = await fetch(source.resolve(reference));
          completed++;
          progress(
            total == 0 ? null : (completed / total).clamp(0, 1),
            '已保存 $completed 个片段',
          );
          return part.uri.toString();
        });
        await partial.writeAsString(local, flush: true);
      } else {
        final resumed = response.statusCode == HttpStatus.partialContent;
        final sink = partial.openWrite(
          mode: resumed ? FileMode.append : FileMode.write,
        );
        var received = resumed ? offset : 0;
        final total = response.contentLength < 0
            ? null
            : received + response.contentLength;
        try {
          await for (final chunk in response.timeout(
            const Duration(seconds: 45),
          )) {
            cancellation.check();
            sink.add(chunk);
            received += chunk.length;
            progress(
              total == null || total == 0 ? null : received / total,
              '已保存 ${(received / 1048576).toStringAsFixed(1)} MB',
            );
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      cancellation.check();
      return partial.rename(file.path);
    }

    try {
      return await fetch(url);
    } catch (_) {
      cancellation.check();
      rethrow;
    } finally {
      detach();
      client.close(force: true);
    }
  }
}

class StudySlideExtractor {
  Future<List<StudySlide>> extract(
    String source,
    Directory directory,
    CancellationToken cancellation,
    void Function(double?, String) progress, {
    required Duration startAt,
    required List<StudySlide> existing,
    required Future<void> Function(Duration, List<StudySlide>) checkpoint,
  }) async {
    await directory.create(recursive: true);
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(muted: true),
    );
    final video = VideoController(player);
    final detach = cancellation.onCancel(() => unawaited(player.stop()));
    final slides = [...existing];
    Uint8List? previous;
    try {
      if (slides.isNotEmpty) {
        previous = (await compute(_compareFrame, (
          bytes: await File(slides.last.file).readAsBytes(),
          previous: null,
        ))).thumbnail;
      }
      await player.open(Media(source), play: false);
      await video.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 30),
      );
      final duration = player.state.duration > Duration.zero
          ? player.state.duration
          : await player.stream.duration
                .firstWhere((value) => value > Duration.zero)
                .timeout(const Duration(seconds: 30));
      for (
        var seconds = startAt.inSeconds;
        seconds < duration.inSeconds;
        seconds += 10
      ) {
        cancellation.check();
        final position = Duration(seconds: seconds);
        final arrived = seconds == 0
            ? null
            : player.stream.position
                  .firstWhere(
                    (value) => (value - position).inMilliseconds.abs() <= 1500,
                  )
                  .timeout(const Duration(seconds: 20));
        await player.seek(position);
        await arrived;
        final screenshot = await player.screenshot(format: 'image/jpeg');
        if (screenshot == null) continue;
        final result = await compute(_compareFrame, (
          bytes: screenshot,
          previous: previous,
        ));
        if (result.changed) {
          final file = File(
            '${directory.path}/${seconds.toString().padLeft(6, '0')}.jpg',
          );
          await file.writeAsBytes(screenshot);
          slides.add(StudySlide(file: file.path, position: position));
          previous = result.thumbnail;
        }
        await checkpoint(position + const Duration(seconds: 10), slides);
        progress(seconds / duration.inSeconds, '已提取 ${slides.length} 页课件');
      }
      cancellation.check();
      return slides;
    } catch (_) {
      cancellation.check();
      rethrow;
    } finally {
      detach();
      await player.dispose();
    }
  }
}

({bool changed, Uint8List thumbnail}) _compareFrame(
  ({Uint8List bytes, Uint8List? previous}) input,
) {
  final decoded = image.decodeImage(input.bytes)!;
  final small = image.copyResize(decoded, width: 96, height: 54);
  final thumbnail = Uint8List(96 * 54);
  for (var y = 0; y < 54; y++) {
    for (var x = 0; x < 96; x++) {
      final pixel = small.getPixel(x, y);
      thumbnail[y * 96 + x] = (pixel.r * .299 + pixel.g * .587 + pixel.b * .114)
          .round();
    }
  }
  var difference = 0;
  final previous = input.previous;
  if (previous != null) {
    for (var index = 0; index < thumbnail.length; index++) {
      difference += (thumbnail[index] - previous[index]).abs();
    }
  }
  return (
    changed: previous == null || difference / thumbnail.length > 5,
    thumbnail: thumbnail,
  );
}

Future<Uint8List> studySlidesPdf(List<String> files) => Isolate.run(() async {
  final document = pdf.Document();
  for (final file in files) {
    final data = await File(file).readAsBytes();
    final picture = pdf.MemoryImage(data);
    document.addPage(
      pdf.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pdf.EdgeInsets.zero,
        build: (_) =>
            pdf.Center(child: pdf.Image(picture, fit: pdf.BoxFit.contain)),
      ),
    );
  }
  return document.save();
});
