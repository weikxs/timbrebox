import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';

void main() {
  late HttpServer server;
  late List<String> paths;

  setUp(() async {
    paths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      paths.add(request.uri.path);
      request.response
        ..write('module.exports = {platform: "x", search() {}};')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  PluginRepository repository() => PluginRepository(
    policy: EgressPolicy(
      lookup: (_) async => [InternetAddress.loopbackIPv4],
      isPublicAddress: (_) => true,
    ),
  );

  test('refuses to install a plugin over plain http', () async {
    await expectLater(
      repository().installFromUrl('http://plugins.test:${server.port}/p.js'),
      throwsA(isA<PluginInstallException>()),
    );
    expect(paths, isEmpty);
  });

  test('refuses to install a plugin from the local machine', () async {
    await expectLater(
      PluginRepository().installFromUrl(
        'https://127.0.0.1:${server.port}/p.js',
      ),
      throwsA(isA<PluginInstallException>()),
    );
    expect(paths, isEmpty);
  });
}
