import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:timbrebox_cli/timbrebox_cli.dart';

const _token = 'run-token';

void main() {
  late HttpServer server;
  late List<String> methods;

  setUp(() async {
    methods = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType.json;
      if (request.headers.value('X-TimbreBox-Token') != _token) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(jsonEncode({'error': 'Missing or wrong X-TimbreBox-Token'}))
          ..close();
        return;
      }
      methods.add('${request.method} ${request.uri.path}');
      switch (request.uri.path) {
        case '/':
          request.response.write(jsonEncode({'name': 'TimbreBox control API'}));
        case '/status' || '/pause' || '/search':
          request.response.write(jsonEncode({'playing': true, 'volume': 0.4}));
        case '/hang':
          return; // Never answers.
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  ControlApiClient client({String? token = _token, Duration? timeout}) =>
      ControlApiClient(
        ports: [server.port],
        token: token,
        timeout: timeout ?? const Duration(seconds: 5),
      );

  test('discovers the control API on its port and parses JSON', () async {
    final api = client();
    addTearDown(api.close);

    final base = await api.discover();
    expect(base, 'http://127.0.0.1:${server.port}');

    final status = await api.getJson(base!, '/status');
    expect(status['playing'], true);
    expect(status['volume'], 0.4);
  });

  test('returns null when nothing answers on the scanned ports', () async {
    final api = ControlApiClient(ports: const [1], token: _token);
    addTearDown(api.close);
    expect(await api.discover(), isNull);
  });

  test('reads with GET and sends actions with POST', () async {
    final api = client();
    addTearDown(api.close);
    final base = 'http://127.0.0.1:${server.port}';

    await api.requestJson(base, '/status');
    await api.requestJson(base, '/pause');
    await api.requestJson(base, '/search?q=lofi%20jazz');

    expect(methods, ['GET /status', 'POST /pause', 'POST /search']);
  });

  test('says the token is missing or wrong instead of "not running"', () async {
    final api = client(token: 'stale');
    addTearDown(api.close);

    await expectLater(
      api.discover(),
      throwsA(
        isA<ControlApiException>().having(
          (error) => error.message,
          'message',
          contains('token'),
        ),
      ),
    );
  });

  test('gives up on a player that never answers', () async {
    final api = client(timeout: const Duration(milliseconds: 200));
    addTearDown(api.close);

    await expectLater(
      api.requestJson('http://127.0.0.1:${server.port}', '/hang'),
      throwsA(isA<TimeoutException>()),
    );
  });

  group('token file', () {
    late Directory root;

    setUp(() async => root = await Directory.systemTemp.createTemp('token'));
    tearDown(() => root.delete(recursive: true));

    test('reads the token from the file named in the environment', () async {
      final file = File('${root.path}/control-token')
        ..writeAsStringSync('abc\n');

      expect(
        readControlToken(environment: {'TIMBREBOX_TOKEN_FILE': file.path}),
        'abc',
      );
      expect(readControlToken(environment: {'TIMBREBOX_TOKEN': 'xyz'}), 'xyz');
    });

    test('looks where each platform\'s app keeps it', () {
      expect(
        controlTokenPaths(const {'HOME': '/Users/me'}, os: 'macos'),
        contains(
          '/Users/me/Library/Containers/io.timbrebox.timbreboxApp/Data/'
          'Library/Application Support/io.timbrebox.timbreboxApp/control-token',
        ),
      );
      expect(
        controlTokenPaths(const {'HOME': '/home/me'}, os: 'linux'),
        contains(
          '/home/me/.local/share/io.timbrebox.timbrebox_app/control-token',
        ),
      );
      expect(
        controlTokenPaths(const {
          'APPDATA': r'C:\Users\me\AppData\Roaming',
        }, os: 'windows'),
        contains(
          r'C:\Users\me\AppData\Roaming\io.timbrebox\TimbreBox\control-token',
        ),
      );
    });

    test('finds the token in the first place it exists', () {
      final dir = Directory(
        '${root.path}/.local/share/io.timbrebox.timbrebox_app',
      )..createSync(recursive: true);
      File('${dir.path}/control-token').writeAsStringSync('from-disk');

      expect(
        readControlToken(environment: {'HOME': root.path}, os: 'linux'),
        'from-disk',
      );
    });
  });
}
