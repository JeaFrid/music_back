import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  
  final router = Router();

  router.get('/search/<query>', _search);
  router.get('/stream/<id>', _stream);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('Sunucu çalışıyor: ${server.address.host}:${server.port}');
}

Future<Response> _search(Request req, String query) async {
  final result = await Process.run('yt-dlp', [
    'ytsearch10:${Uri.decodeComponent(query)}',
    '--dump-json',
    '--flat-playlist',
    '--no-warnings',
  ]);

  if (result.exitCode != 0) {
    return Response.internalServerError(body: 'Arama başarısız');
  }

  final lines = (result.stdout as String)
      .trim()
      .split('\n')
      .where((l) => l.isNotEmpty);

  final items = lines.map((line) {
    final json = jsonDecode(line);
    return {
      'id': json['id'],
      'title': json['title'],
      'channel': json['channel'] ?? json['uploader'] ?? '',
      'duration': json['duration'],
      'thumbnail':
          json['thumbnail'] ??
          'https://i.ytimg.com/vi/${json['id']}/hqdefault.jpg',
    };
  }).toList();

  return Response.ok(
    jsonEncode(items),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _stream(Request req, String id) async {
  final result = await Process.run('yt-dlp', [
    '-f',
    'bestaudio[ext=webm]/bestaudio[ext=m4a]/bestaudio',
    '--get-url',
    '--no-warnings',
    'https://www.youtube.com/watch?v=$id',
  ]);

  if (result.exitCode != 0) {
    return Response.internalServerError(body: 'Link alınamadı');
  }

  final url = (result.stdout as String).trim();

  return Response.ok(
    jsonEncode({'url': url}),
    headers: {'content-type': 'application/json'},
  );
}
