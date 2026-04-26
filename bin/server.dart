import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

final _analyzeCache = <String, List<List<double>>>{};

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final router = Router();

  router.get('/search/<query>', _search);
  router.get('/stream/<id>', _stream);
  router.get('/analyze/<id>', _analyze);

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
  final isVideo = req.url.queryParameters['video'] == 'true';

  final format = isVideo
      ? 'best'
      : 'bestaudio[ext=webm]/bestaudio[ext=m4a]/bestaudio';

  final result = await Process.run('yt-dlp', [
    '-f',
    format,
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

Future<Response> _analyze(Request req, String id) async {
  if (_analyzeCache.containsKey(id)) {
    return Response.ok(
      jsonEncode({'fps': 10, 'bands': 32, 'frames': _analyzeCache[id]}),
      headers: {'content-type': 'application/json'},
    );
  }

  final urlResult = await Process.run('yt-dlp', [
    '-f',
    'bestaudio',
    '--get-url',
    '--no-warnings',
    'https://www.youtube.com/watch?v=$id',
  ]);

  if (urlResult.exitCode != 0) {
    return Response.internalServerError(body: 'URL alınamadı');
  }

  final url = (urlResult.stdout as String).trim();

  final ffmpeg = await Process.start('ffmpeg', [
    '-i',
    url,
    '-ac',
    '1',
    '-ar',
    '22050',
    '-f',
    'f32le',
    '-',
  ]);

  final bytes = <int>[];
  await ffmpeg.stdout.forEach(bytes.addAll);
  await ffmpeg.exitCode;

  final samples = List<double>.generate(
    bytes.length ~/ 4,
    (i) => ByteData.sublistView(
      Uint8List.fromList(bytes.sublist(i * 4, i * 4 + 4)),
    ).getFloat32(0, Endian.little),
  );

  const sampleRate = 22050;
  const fps = 10;
  const bands = 32;
  const frameSize = sampleRate ~/ fps;

  final frames = <List<double>>[];

  for (var i = 0; i + frameSize <= samples.length; i += frameSize) {
    final frame = samples.sublist(i, i + frameSize);
    final bandSize = frameSize ~/ bands;
    final magnitudes = List<double>.generate(bands, (b) {
      final slice = frame.sublist(b * bandSize, (b + 1) * bandSize);
      final meanSquare = slice.fold(0.0, (s, x) => s + x * x) / slice.length;
      final rms = math.sqrt(meanSquare);
      return (rms * 4.0).clamp(0.0, 1.0);
    });
    frames.add(magnitudes);
  }

  _analyzeCache[id] = frames;

  return Response.ok(
    jsonEncode({'fps': fps, 'bands': bands, 'frames': frames}),
    headers: {'content-type': 'application/json'},
  );
}
