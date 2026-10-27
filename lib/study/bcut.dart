import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/async/cancelable_request.dart';
import 'model.dart';

/// Optional BCut transcription. Only the explicitly selected audio is uploaded.
class BCutTranscriber {
  static final _origin = Uri.https(
    'member.bilibili.com',
    '/x/bcut/rubick-interface/',
  );

  Future<List<TranscriptSegment>> transcribe(
    File audio,
    CancellationToken cancellation,
    void Function(double?, String) progress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final detach = cancellation.onCancel(() => client.close(force: true));
    Future<Map<String, dynamic>> call(
      String path, {
      Map<String, String>? form,
      Map<String, dynamic>? json,
      Map<String, String>? query,
    }) async {
      cancellation.check();
      final request = await client.openUrl(
        form == null && json == null ? 'GET' : 'POST',
        _origin.resolve(path).replace(queryParameters: query),
      );
      request.headers.set('User-Agent', 'Mozilla/5.0');
      if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write(Uri(queryParameters: form).query);
      } else if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode >= 400) {
        await response.drain<void>();
        throw HttpException('必剪请求失败（${response.statusCode}）');
      }
      final body = jsonDecode(
        await utf8.decoder.bind(response).join(),
      ) as Map<String, dynamic>;
      if (body['code'] != 0) {
        throw StateError('必剪：${body['message'] ?? body['code']}');
      }
      return body['data'] as Map<String, dynamic>;
    }

    try {
      final size = await audio.length();
      final extension = audio.path.split('.').last.toLowerCase();
      final resource = await call(
        'resource/create',
        form: {
          'type': '2',
          'name': audio.uri.pathSegments.last,
          'size': '$size',
          'resource_file_type': extension,
          'model_id': '7',
        },
      );
      final input = await audio.open();
      final etags = <String>[];
      var sent = 0;
      try {
        for (final url in resource['upload_urls'] as List) {
          cancellation.check();
          final bytes = await input.read((resource['per_size'] as num).toInt());
          final request = await client.putUrl(Uri.parse(url as String));
          request.contentLength = bytes.length;
          request.add(bytes);
          final response = await request.close().timeout(
            const Duration(minutes: 2),
          );
          await response.drain<void>();
          if (response.statusCode >= 400) {
            throw HttpException('上传音频失败（${response.statusCode}）');
          }
          etags.add(response.headers.value('Etag')!);
          sent += bytes.length;
          progress(sent / size, '正在上传音频');
        }
      } finally {
        await input.close();
      }
      final uploaded = await call(
        'resource/create/complete',
        form: {
          'in_boss_key': '${resource['in_boss_key']}',
          'resource_id': '${resource['resource_id']}',
          'etags': etags.join(','),
          'upload_id': '${resource['upload_id']}',
          'model_id': '7',
        },
      );
      final task = await call(
        'task',
        json: {'resource': uploaded['download_url'], 'model_id': '7'},
      );
      final deadline = DateTime.now().add(const Duration(minutes: 40));
      progress(null, '必剪正在识别音频');
      while (DateTime.now().isBefore(deadline)) {
        cancellation.check();
        final result = await call(
          'task/result',
          query: {'model_id': '7', 'task_id': '${task['task_id']}'},
        );
        if (result['state'] == 4) {
          final decoded =
              jsonDecode(result['result'] as String) as Map<String, dynamic>;
          return [
            for (final row in decoded['utterances'] as List)
              TranscriptSegment(
                Duration(milliseconds: (row['start_time'] as num).round()),
                Duration(milliseconds: (row['end_time'] as num).round()),
                row['transcript'] as String,
              ),
          ];
        }
        if (result['state'] == 3) {
          throw StateError('必剪识别失败：${result['remark'] ?? '请更换音频后重试'}');
        }
        final stop = Completer<void>();
        final unbind = cancellation.onCancel(() => stop.complete());
        try {
          await Future.any([
            Future<void>.delayed(const Duration(seconds: 10)),
            stop.future,
          ]);
        } finally {
          unbind();
        }
      }
      throw TimeoutException('必剪识别超时，请稍后重试');
    } catch (_) {
      cancellation.check();
      rethrow;
    } finally {
      detach();
      client.close(force: true);
    }
  }
}
