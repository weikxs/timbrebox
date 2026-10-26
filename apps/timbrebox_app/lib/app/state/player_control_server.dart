import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show exit;

import '../model/catalog_track.dart';
import 'app_controller.dart';
import 'control_request_guard.dart';
import 'control_token.dart';

/// A loopback HTTP control API so a local agent / CLI / script can drive the
/// player. Bound to 127.0.0.1, so nothing off the machine can reach it; the
/// checks in [controlRequestRejection] keep web pages in the user's browser
/// out as well, and every request must carry this run's token from the
/// user-only token file (header [controlTokenHeader]). On by default.
///
/// Endpoints (all return JSON):
///   GET  / /status /queue /sources /lyric
///   POST /search?q= /play /pause /toggle /next /previous /stop /quit
///   POST /seek?ms= /volume?level= /mode?loop= /play-ref?source=&item=
///   POST /play-queue?i= /source?id=&enabled=
final class PlayerControlServer {
  PlayerControlServer(
    this._controller, {
    void Function(int code)? exit,
    List<int> ports = preferredPorts,
    ControlTokenFile? tokenFile,
    File? endpointFile,
  }) : _exit = exit ?? io.exit,
       // ignore: prefer_initializing_formals
       _ports = ports,
       _tokenFile = tokenFile ?? ControlTokenFile(),
       _endpointOverride = endpointFile;

  final AppController _controller;
  final List<int> _ports;
  final ControlTokenFile _tokenFile;
  final File? _endpointOverride;

  /// This run's token; requests without it are refused.
  String? _token;

  /// The file holding the token while the API runs (shown in Settings).
  String? tokenPath;

  /// Ends the process; replaced in tests.
  final void Function(int code) _exit;

  /// The longest a quit waits for the session save and pending writes.
  static const _quitSaveLimit = Duration(seconds: 5);
  HttpServer? _server;

  /// Preferred deterministic loopback ports so a local agent/CLI can find the
  /// server by scanning this small range — the macOS sandbox redirects the
  /// app's HOME into its container, so a shared discovery file isn't visible to
  /// an external CLI, but a fixed port range always is.
  static const preferredPorts = [
    8787, 8788, 8789, 8790, 8791, 8792, 8793, 8794, 8795, 8796,
  ];

  bool get running => _server != null;
  int? get port => _server?.port;
  String? get address =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';

  /// Starts the API with a fresh token. Throws (and stays stopped) when the
  /// token file cannot be written privately: no token, no API.
  Future<void> start() async {
    if (_server != null) return;
    _token = await _tokenFile.issue();
    tokenPath = (await _tokenFile.file()).path;
    HttpServer? server;
    for (final candidate in _ports) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, candidate);
        break;
      } catch (_) {
        // Port busy — try the next.
      }
    }
    server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server..listen(_handle);
    await _writeEndpointFile();
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return; // Never started: no file of ours to remove.
    _server = null;
    _token = null;
    tokenPath = null;
    await server.close(force: true);
    await _tokenFile.revoke();
    await _removeEndpointFile();
  }

  /// The well-known file any local agent/CLI reads to discover the running
  /// control endpoint (the port is ephemeral). Cross-platform home dir.
  File? _endpointFile() {
    if (_endpointOverride case final file?) return file;
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return null;
    return File('$home/.timbrebox/control.json');
  }

  Future<void> _writeEndpointFile() async {
    final file = _endpointFile();
    final addr = address;
    if (file == null || addr == null) return;
    try {
      await file.parent.create(recursive: true);
      // Where the token is, never the token itself: this file is not private.
      final tokenFile = (await _tokenFile.file()).path;
      await file.writeAsString(
        jsonEncode({'address': addr, 'pid': pid, 'tokenFile': tokenFile}),
        flush: true,
      );
    } catch (_) {
      // Discovery is best-effort; the address is still shown in Settings.
    }
  }

  Future<void> _removeEndpointFile() async {
    final file = _endpointFile();
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest request) async {
    final rejection = controlRequestRejection(
      method: request.method,
      path: request.uri.path,
      host: request.headers.value(HttpHeaders.hostHeader),
      origin: request.headers.value('origin'),
      fetchSite: request.headers.value('sec-fetch-site'),
      port: request.connectionInfo?.localPort ?? port ?? 0,
      token: request.headers.value(controlTokenHeader),
      expectedToken: _token ?? '',
    );
    if (rejection != null) {
      return _json(request, rejection.status, {'error': rejection.error});
    }
    final query = request.uri.queryParameters;
    try {
      switch (request.uri.path) {
        case '/':
          return _json(request, HttpStatus.ok, _discovery());
        case '/status':
          return _json(request, HttpStatus.ok, _status());
        case '/queue':
          return _json(request, HttpStatus.ok, {
            'items': [
              for (final track in _controller.queue) _trackJson(track),
            ],
          });
        case '/sources':
          return _json(request, HttpStatus.ok, {
            'sources': [
              for (final source in _controller.sourceDescriptors)
                {
                  'id': source.id,
                  'name': source.name,
                  'enabled': _controller.sourceEnabled(source.id),
                },
            ],
          });
        case '/lyric':
          final lyric = await _controller.currentLyric();
          return _json(request, HttpStatus.ok, {'lyric': lyric});
        case '/play-queue':
          final i = int.tryParse(query['i'] ?? '');
          if (i == null) return _badRequest(request, 'i 参数无效');
          final ok = await _controller.playQueueIndex(i);
          return _json(request, ok ? HttpStatus.ok : HttpStatus.notFound, {
            'ok': ok,
            ...ok ? _status() : {'error': '队列索引超范围'},
          });
        case '/mode':
          final mode = query['loop'];
          PlaybackLoop? parsed;
          for (final loop in PlaybackLoop.values) {
            if (loop.name == mode) parsed = loop;
          }
          if (parsed == null) {
            return _badRequest(
              request,
              'loop 需为 ${PlaybackLoop.values.map((l) => l.name).join('/')}',
            );
          }
          _controller.setLoop(parsed);
          return _json(request, HttpStatus.ok, _status());
        case '/source':
          final id = query['id'];
          final enabled = query['enabled'];
          if (id == null || enabled == null) {
            return _badRequest(request, '缺少 id/enabled 参数');
          }
          _controller.setSourceEnabled(id, enabled == 'true' || enabled == '1');
          return _json(request, HttpStatus.ok, {'ok': true});
        case '/play':
          if (!_controller.isPlaying) await _controller.togglePlayback();
          return _json(request, HttpStatus.ok, _status());
        case '/pause':
          if (_controller.isPlaying) await _controller.togglePlayback();
          return _json(request, HttpStatus.ok, _status());
        case '/toggle':
          await _controller.togglePlayback();
          return _json(request, HttpStatus.ok, _status());
        case '/next':
          await _controller.next();
          return _json(request, HttpStatus.ok, _status());
        case '/previous':
          await _controller.previous();
          return _json(request, HttpStatus.ok, _status());
        case '/stop':
          await _controller.stopPlayback();
          return _json(request, HttpStatus.ok, _status());
        case '/quit':
          // Deliberate shutdown of the whole app — useful when the window is
          // hidden in the background and there is no Cmd+Q (Windows/Linux).
          // Respond first, then save and exit so the process and this
          // server stop.
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 150), quit),
          );
          return _json(request, HttpStatus.ok, {'ok': true, 'quitting': true});
        case '/seek':
          final ms = int.tryParse(query['ms'] ?? '');
          if (ms == null) return _badRequest(request, 'ms 参数无效');
          await _controller.seek(Duration(milliseconds: ms));
          return _json(request, HttpStatus.ok, _status());
        case '/volume':
          final level = double.tryParse(query['level'] ?? '');
          if (level == null) return _badRequest(request, 'level 参数无效');
          _controller.setVolume(level);
          return _json(request, HttpStatus.ok, _status());
        case '/search':
          final q = query['q'] ?? '';
          if (q.trim().isEmpty) return _badRequest(request, 'q 参数为空');
          await _controller.search(q);
          return _json(request, HttpStatus.ok, {
            'query': q,
            'results': [
              for (final track in _controller.searchResults)
                {
                  'source': track.sourceId,
                  'item': track.id,
                  'title': track.title,
                  'artist': track.artist,
                  'sourceName': track.sourceName,
                },
            ],
          });
        case '/play-ref':
          final source = query['source'];
          final item = query['item'];
          if (source == null || item == null) {
            return _badRequest(request, '缺少 source/item 参数');
          }
          final ok = await _controller.playByRef(source, item);
          return _json(request, ok ? HttpStatus.ok : HttpStatus.notFound, {
            'ok': ok,
            ...ok ? _status() : {'error': '未找到该曲目，请先 /search'},
          });
        default:
          return _json(request, HttpStatus.notFound, {'error': 'unknown path'});
      }
    } catch (error) {
      return _json(request, HttpStatus.internalServerError, {'error': '$error'});
    }
  }

  /// Saves the session and lets pending file writes finish (for at most
  /// [_quitSaveLimit]), then ends the process.
  Future<void> quit() async {
    try {
      await _controller.prepareToQuit().timeout(_quitSaveLimit);
    } catch (_) {
      // Quitting must not hang on a stuck disk; whatever was saved stays.
    }
    await stop();
    _exit(0);
  }

  Map<String, Object?> _discovery() => {
    'name': 'TimbreBox control API',
    'version': 1,
    'auth':
        'header $controlTokenHeader: the token from the user-only file '
        'control-token in the app support directory (new each run)',
    'endpoints': const {
      'GET /': 'this discovery document',
      'GET /status': 'current playback state',
      'GET /queue': 'the play queue',
      'GET /sources': 'sources with enabled state',
      'GET /lyric': "current track's lyric (plugin sources)",
      'POST /search?q=': 'search all enabled sources',
      'POST /play /pause /toggle /next /previous /stop': 'transport',
      'POST /seek?ms=': 'seek to position (ms)',
      'POST /volume?level=': 'set volume (0..1)',
      'POST /mode?loop=': 'queue/track/off/shuffle',
      'POST /play-ref?source=&item=': 'play a searched track',
      'POST /play-queue?i=': 'play queue index',
      'POST /source?id=&enabled=': 'enable/disable a source',
      'POST /quit': 'quit the whole app',
    },
    'status': _status(),
  };

  Map<String, Object?> _trackJson(CatalogTrack track) => {
    'source': track.sourceId,
    'item': track.id,
    'title': track.title,
    'artist': track.artist,
    'sourceName': track.sourceName,
    'durationMs': track.duration.inMilliseconds,
  };

  Map<String, Object?> _status() {
    final track = _controller.currentTrack;
    return {
      'playing': _controller.isPlaying,
      'loading': _controller.isLoading,
      'positionMs': _controller.position.inMilliseconds,
      'volume': _controller.volume,
      'loop': _controller.loop.name,
      'queueLength': _controller.queue.length,
      'track': track == null ? null : _trackJson(track),
    };
  }

  void _badRequest(HttpRequest request, String message) =>
      _json(request, HttpStatus.badRequest, {'error': message});

  void _json(HttpRequest request, int status, Map<String, Object?> body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    request.response.close();
  }
}
