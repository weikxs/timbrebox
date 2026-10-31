import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/control_token.dart';
import 'package:timbrebox_app/app/state/player_control_server.dart';

import 'support/test_player_engine.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('token'));
  tearDown(() => root.delete(recursive: true));

  ControlTokenFile tokens() => ControlTokenFile(directory: () async => root);

  test(
    'each run writes a new random token readable only by the user',
    () async {
      final first = await tokens().issue();
      final second = await tokens().issue();
      final file = File('${root.path}/${ControlTokenFile.fileName}');

      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(second, isNot(first));
      expect(await file.readAsString(), second);
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
      }
      expect(root.listSync().map((entry) => entry.uri.pathSegments.last), [
        ControlTokenFile.fileName,
      ]);
    },
  );

  test('stopping removes the token file', () async {
    final file = tokens();
    await file.issue();

    await file.revoke();

    expect(root.listSync(), isEmpty);
  });

  test('the server answers only requests carrying the token', () async {
    final controller = AppController(engine: TestPlayerEngine());
    addTearDown(controller.dispose);
    final server = PlayerControlServer(
      controller,
      ports: const [],
      tokenFile: tokens(),
      endpointFile: File('${root.path}/control.json'),
    );
    await server.start();
    addTearDown(server.stop);
    final token = await File(
      '${root.path}/${ControlTokenFile.fileName}',
    ).readAsString();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    Future<int> status({String? withToken, String path = '/status'}) async {
      final request = await client.getUrl(Uri.parse('${server.address}$path'));
      if (withToken != null) {
        request.headers.set(controlTokenHeader, withToken);
      }
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await status(), HttpStatus.unauthorized);
    expect(await status(withToken: 'wrong'), HttpStatus.unauthorized);
    expect(await status(withToken: token), HttpStatus.ok);
    expect(await status(path: '/search-status'), HttpStatus.unauthorized);
    expect(
      await status(path: '/search-status', withToken: token),
      HttpStatus.ok,
    );
    final queryBefore = controller.query;
    final request = await client.getUrl(
      Uri.parse('${server.address}/search-status'),
    );
    request.headers.set(controlTokenHeader, token);
    final response = await request.close();
    final search = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(search['hasQuery'], false);
    expect(search['isSearching'], false);
    expect(search['sources'], isA<List>());
    expect(search.containsKey('query'), false);
    expect(search.containsKey('results'), false);
    expect(controller.query, queryBefore);
    expect(controller.isPlaying, false);
    expect(await status(path: '/playback-status'), HttpStatus.unauthorized);
    final playbackRequest = await client.getUrl(
      Uri.parse('${server.address}/playback-status'),
    );
    playbackRequest.headers.set(controlTokenHeader, token);
    final playbackResponse = await playbackRequest.close();
    final playback =
        jsonDecode(await utf8.decoder.bind(playbackResponse).join()) as Map;
    expect(playback['state'], 'idle');
    expect(playback['hasError'], false);
    expect(playback.containsKey('errorMessage'), false);
    expect(playback.containsKey('track'), false);
    expect(controller.query, queryBefore);
    final discovery =
        jsonDecode(await File('${root.path}/control.json').readAsString())
            as Map;
    expect(discovery.containsValue(token), isFalse);
  });
}
