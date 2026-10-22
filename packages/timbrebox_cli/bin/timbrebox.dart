// TimbreBox one-shot CLI. Drives the running player's loopback control API
// (127.0.0.1:8787-8796). Cross-platform Dart equivalent of tools/timbrebox-ctl.
//
//   timbrebox <command> [args] [--json]
//   commands: status | search <q> | play-ref <source> <item> | play | pause
//             | toggle | next | prev | stop | quit | seek <ms> | volume <0..1>
//             | mode <queue|track|off|shuffle> | queue | sources
//             | source <id> <true|false> | lyric | play-queue <index>
import 'dart:convert';
import 'dart:io';

import 'package:timbrebox_cli/timbrebox_cli.dart';

Future<void> main(List<String> argv) async {
  final asJson = argv.contains('--json');
  final args = argv.where((a) => a != '--json').toList();
  if (args.isEmpty) {
    stderr.writeln('Usage: timbrebox <command> [args] [--json]');
    exitCode = 2;
    return;
  }

  final client = ControlApiClient();
  try {
    final base = await client.discover();
    if (base == null) {
      stderr.writeln('TimbreBox is not running or Agent control is off.');
      exitCode = 3;
      return;
    }
    final path = _pathFor(args);
    if (path == null) {
      stderr.writeln('Unknown or malformed command: ${args.first}');
      exitCode = 2;
      return;
    }
    final result = await client.getJson(base, path);
    stdout.writeln(asJson ? jsonEncode(result) : _human(args.first, result));
  } catch (error) {
    stderr.writeln('Error: $error');
    exitCode = 1;
  } finally {
    client.close();
  }
}

String? _pathFor(List<String> args) {
  final cmd = args.first;
  String q(int i) => Uri.encodeQueryComponent(args[i]);
  switch (cmd) {
    case 'status' || 'queue' || 'sources' || 'lyric' || 'play' || 'pause' ||
        'toggle' || 'next' || 'stop' || 'quit':
      return '/$cmd';
    case 'prev':
      return '/previous';
    case 'search':
      return args.length >= 2 ? '/search?q=${q(1)}' : null;
    case 'play-ref':
      return args.length >= 3 ? '/play-ref?source=${q(1)}&item=${q(2)}' : null;
    case 'play-queue':
      return args.length >= 2 ? '/play-queue?i=${q(1)}' : null;
    case 'seek':
      return args.length >= 2 ? '/seek?ms=${q(1)}' : null;
    case 'volume':
      return args.length >= 2 ? '/volume?level=${q(1)}' : null;
    case 'mode':
      return args.length >= 2 ? '/mode?loop=${q(1)}' : null;
    case 'source':
      return args.length >= 3 ? '/source?id=${q(1)}&enabled=${q(2)}' : null;
    default:
      return null;
  }
}

String _human(String cmd, Map<String, Object?> result) {
  if (result['error'] != null) return 'Error: ${result['error']}';
  switch (cmd) {
    case 'status':
      final track = result['track'];
      final title = track is Map ? track['title'] : null;
      return 'playing=${result['playing']} · volume=${result['volume']} · '
          'loop=${result['loop']} · track=${title ?? 'none'}';
    case 'search':
      final results = (result['results'] as List?) ?? const [];
      final lines = [
        for (final r in results.take(10))
          if (r is Map)
            '  ${r['source']}  ${r['item']}  ${r['title']} — ${r['artist']}',
      ];
      return '${results.length} result(s):\n${lines.join('\n')}';
    default:
      return jsonEncode(result);
  }
}
