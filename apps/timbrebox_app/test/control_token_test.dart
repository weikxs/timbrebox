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

    Future<int> status({String? withToken}) async {
      final request = await client.getUrl(
        Uri.parse('${server.address}/status'),
      );
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
    final discovery =
        jsonDecode(await File('${root.path}/control.json').readAsString())
            as Map;
    expect(discovery.containsValue(token), isFalse);
  });
}
