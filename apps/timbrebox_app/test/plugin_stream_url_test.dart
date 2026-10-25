import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/net/egress_policy.dart';
import 'package:timbrebox_app/app/plugins/plugin_stream_url.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  final publicDns = EgressPolicy(
    lookup: (_) async => [InternetAddress('93.184.216.34')],
  );

  Matcher blockedWith(String code) =>
      throwsA(isA<SourceException>().having((e) => e.code, 'code', code));

  test('accepts a public https stream URL', () async {
    final uri = await checkedPluginStreamUri(
      'https://cdn.example.org/a.mp3',
      policy: publicDns,
    );

    expect(uri.host, 'cdn.example.org');
  });

  for (final url in [
    'file:///Users/someone/.ssh/id_rsa',
    'http://127.0.0.1:8787/quit',
    'http://192.168.1.1/admin',
    'http://localhost/',
  ]) {
    test('blocks $url', () {
      expect(
        checkedPluginStreamUri(url, policy: publicDns),
        blockedWith('stream_url_blocked'),
      );
    });
  }

  for (final url in [null, '', 'not a url']) {
    test('reports a missing URL for "$url"', () {
      expect(
        checkedPluginStreamUri(url, policy: publicDns),
        blockedWith('source_stream_unavailable'),
      );
    });
  }
}
