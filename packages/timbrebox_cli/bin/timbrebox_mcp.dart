// TimbreBox MCP server (stdio, JSON-RPC 2.0, newline-delimited).
//
// Bridges MCP tool calls to the running TimbreBox player's local loopback
// control API, sending the per-run token from the app's user-only
// control-token file (or TIMBREBOX_TOKEN_FILE / TIMBREBOX_TOKEN). Point an
// MCP client (e.g. Claude Desktop) at:
//   dart run timbrebox_cli:timbrebox_mcp
import 'dart:convert';
import 'dart:io';

import 'package:timbrebox_cli/timbrebox_cli.dart';

final ControlApiClient _client = ControlApiClient();

Future<void> main() async {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
}

Future<void> _onLine(String line) async {
  if (line.trim().isEmpty) return;
  Object? message;
  try {
    message = jsonDecode(line);
  } catch (_) {
    return;
  }
  if (message is! Map) return;
  final id = message['id'];
  switch (message['method']) {
    case 'initialize':
      _reply(id, {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': <String, Object?>{}},
        'serverInfo': {'name': 'timbrebox', 'version': '1'},
      });
    case 'notifications/initialized':
      break; // A notification: no response.
    case 'ping':
      _reply(id, <String, Object?>{});
    case 'tools/list':
      _reply(id, {'tools': _tools});
    case 'tools/call':
      await _handleToolCall(id, message['params']);
    default:
      if (id != null) _error(id, -32601, 'Unknown method');
  }
}

const List<Map<String, Object?>> _tools = [
  {
    'name': 'play_music',
    'description':
        'Search all enabled sources and play the best match for a query.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Song, artist, or keywords'},
      },
      'required': ['query'],
    },
  },
  {'name': 'pause', 'description': 'Pause playback.', 'inputSchema': _empty},
  {'name': 'resume', 'description': 'Resume playback.', 'inputSchema': _empty},
  {'name': 'stop', 'description': 'Stop playback.', 'inputSchema': _empty},
  {'name': 'next', 'description': 'Next track.', 'inputSchema': _empty},
  {'name': 'previous', 'description': 'Previous track.', 'inputSchema': _empty},
  {
    'name': 'get_status',
    'description': 'Current playback state (playing, track, volume, loop).',
    'inputSchema': _empty,
  },
  {
    'name': 'set_volume',
    'description': 'Set the volume from 0.0 to 1.0.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'level': {'type': 'number', 'minimum': 0, 'maximum': 1},
      },
      'required': ['level'],
    },
  },
];

const Map<String, Object?> _empty = {
  'type': 'object',
  'properties': <String, Object?>{},
};

Future<void> _handleToolCall(Object? id, Object? params) async {
  final name = (params is Map ? params['name'] : null)?.toString();
  final rawArgs = params is Map ? params['arguments'] : null;
  final args = rawArgs is Map ? rawArgs : const {};
  try {
    // Discovery sends the run's token too, and says so when it is refused.
    final base = await _client.discover();
    if (base == null) {
      _toolResult(
        id,
        'TimbreBox is not running or Agent control is off.',
        isError: true,
      );
      return;
    }
    _toolResult(id, await _runTool(base, name, args));
  } catch (error) {
    _toolResult(id, 'Error: $error', isError: true);
  }
}

Future<String> _runTool(
  String base,
  String? name,
  Map<Object?, Object?> args,
) async {
  String enc(Object? v) => Uri.encodeQueryComponent('$v');
  switch (name) {
    case 'play_music':
      final query = args['query']?.toString().trim() ?? '';
      if (query.isEmpty) return 'Provide a non-empty query.';
      final search = await _client.requestJson(base, '/search?q=${enc(query)}');
      final results = (search['results'] as List?) ?? const [];
      if (results.isEmpty) return 'No results for "$query".';
      final first = results.first as Map;
      final played = await _client.requestJson(
        base,
        '/play-ref?source=${enc(first['source'])}&item=${enc(first['item'])}',
      );
      final track = played['track'];
      return played['ok'] == true
          ? 'Playing: ${track is Map ? track['title'] : first['title']}'
          : 'Could not play: ${played['error'] ?? 'unknown error'}';
    case 'pause':
      await _client.requestJson(base, '/pause');
      return 'Paused.';
    case 'resume':
      await _client.requestJson(base, '/play');
      return 'Resumed.';
    case 'stop':
      await _client.requestJson(base, '/stop');
      return 'Stopped.';
    case 'next':
      await _client.requestJson(base, '/next');
      return 'Skipped to next.';
    case 'previous':
      await _client.requestJson(base, '/previous');
      return 'Skipped to previous.';
    case 'set_volume':
      final level = ((args['level'] as num?)?.toDouble() ?? 0.5).clamp(0, 1);
      await _client.requestJson(base, '/volume?level=$level');
      return 'Volume set to ${(level * 100).round()}%.';
    case 'get_status':
      final status = await _client.requestJson(base, '/status');
      final track = status['track'];
      final title = track is Map ? track['title'] : null;
      return 'playing=${status['playing']}, volume=${status['volume']}, '
          'loop=${status['loop']}, track=${title ?? 'none'}';
    default:
      return 'Unknown tool: $name';
  }
}

void _send(Map<String, Object?> message) => stdout.writeln(jsonEncode(message));

void _reply(Object? id, Object? result) =>
    _send({'jsonrpc': '2.0', 'id': id, 'result': result});

void _error(Object? id, int code, String message) => _send({
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': code, 'message': message},
});

void _toolResult(Object? id, String text, {bool isError = false}) =>
    _reply(id, {
      'content': [
        {'type': 'text', 'text': text},
      ],
      if (isError) 'isError': true,
    });
