import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

void main() {
  final envelope = jsonEncode({
    'ok': true,
    'value': [
      {'id': '1', 'title': 'Demo'},
    ],
  });

  test('reads the envelope QuickJS returns as JSON text', () {
    final decoded = PluginRuntime.decodeCallEnvelope(envelope);

    expect(decoded, isA<Map>());
    expect((decoded! as Map)['value'], hasLength(1));
  });

  test('reads the envelope JavaScriptCore stringifies a second time', () {
    final decoded = PluginRuntime.decodeCallEnvelope(jsonEncode(envelope));

    expect(decoded, isA<Map>());
    expect((decoded! as Map)['ok'], isTrue);
    expect((decoded as Map)['value'], hasLength(1));
  });

  test('an empty answer is no envelope', () {
    expect(PluginRuntime.decodeCallEnvelope(''), isNull);
  });
}
