import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_app/app/plugins/plugin_catalog_source.dart';
import 'package:timbrebox_app/app/plugins/plugin_manifest.dart';
import 'package:timbrebox_app/app/plugins/plugin_repository.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';
import 'package:timbrebox_app/app/plugins/plugin_shims.dart';

/// A plugin whose search reports which shim libraries its engine evaluated.
const _script = r'''
module.exports = {
  platform: 'P',
  search: async function () {
    return { isEnd: true, data: [{
      id: 'x',
      title: [typeof globalThis.__lib_cheerio, typeof globalThis.__lib_he].join(','),
    }] };
  },
  getLyric: async function () { return { rawLrc: '' }; },
};
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late int started;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('plugins');
    started = 0;
  });

  tearDown(() => root.delete(recursive: true));

  PluginRepository repository({Duration? idleTimeout}) => PluginRepository(
    pluginsDirectory: () async => root,
    createRuntime: (environment, _) {
      started++;
      return PluginRuntime(environment: environment);
    },
    idleTimeout: idleTimeout ?? const Duration(minutes: 5),
  );

  Future<void> store(
    String id, {
    bool enabled = true,
    List<String>? functions = const ['search', 'getLyric'],
    String script = _script,
  }) async {
    final dir = await Directory('${root.path}/$id').create();
    await File('${dir.path}/plugin.js').writeAsString(script);
    final manifest = PluginManifest(
      id: id,
      platform: id,
      version: '1',
      enabled: enabled,
      functions: functions,
    );
    await File(
      '${dir.path}/manifest.json',
    ).writeAsString(jsonEncode(manifest.toJson()));
  }

  Future<SearchPage> search(PluginCatalogSource source) => source.search(
    SearchRequest(query: 'q', cancellation: CancellationToken()),
  );

  test('launch starts no plugin engine; the first search starts one', () async {
    for (var index = 0; index < 8; index++) {
      await store('plugin_$index', enabled: index < 5);
    }

    final watch = Stopwatch()..start();
    final sources = await repository().loadInstalled();
    watch.stop();
    // ignore: avoid_print
    print('loadInstalled(8 plugins): ${watch.elapsedMilliseconds} ms');

    expect(sources, hasLength(8));
    expect(started, 0);
    expect(sources.every((source) => !source.isStarted), isTrue);

    final first = sources.first;
    await search(first);
    await search(first);
    expect(started, 1);
    expect(first.isStarted, isTrue);
    for (final source in sources) {
      source.dispose();
    }
  });

  test('capabilities come from the manifest without evaluating JS', () async {
    await store('plugin_a');
    final source = (await repository().loadInstalled()).single;

    for (var read = 0; read < 100; read++) {
      expect(source.descriptor.supports(SourceCapability.search), isTrue);
      expect(source.descriptor.supports(SourceCapability.lyrics), isTrue);
      expect(source.descriptor.supports(SourceCapability.streaming), isFalse);
      expect(source.hasLyric, isTrue);
      expect(source.hasTopLists, isFalse);
    }
    expect(started, 0);
    source.dispose();
  });

  test('a plugin from before recorded functions is read once', () async {
    await store('plugin_old', functions: null);

    final source = (await repository().loadInstalled()).single;

    expect(started, 1);
    expect(source.hasLyric, isTrue);
    final saved = PluginManifest.fromJson(
      jsonDecode(
            await File('${root.path}/plugin_old/manifest.json').readAsString(),
          )
          as Map<String, Object?>,
    );
    expect(saved.functions, containsAll(['search', 'getLyric']));
    source.dispose();
  });

  test('a plugin evaluates only the shim libraries it names', () async {
    Future<String?> loaded(String script) async {
      final runtime = PluginRuntime();
      addTearDown(runtime.dispose);
      await runtime.load(script);
      return runtime.meta('loaded');
    }

    const report =
        'module.exports = { platform: "P", search() {}, loaded: '
        '[typeof globalThis.__lib_cheerio, typeof globalThis.__lib_he]'
        '.join(",") };';

    expect(await loaded(report), 'undefined,undefined');
    expect(
      await loaded("const he = require('he');\n$report"),
      'undefined,object',
    );
  });

  test('module names are matched only as quoted literals', () {
    expect(PluginShims.mentions("require('cheerio')", 'cheerio'), isTrue);
    expect(PluginShims.mentions('require("qs")', 'qs'), isTrue);
    expect(PluginShims.mentions('const qs = 1; // the qs lib', 'qs'), isFalse);
  });

  test('a disposed source never keeps an engine it was starting', () async {
    await store('plugin_a');
    final source = (await repository().loadInstalled()).single;

    final pending = search(source);
    source.dispose();

    await expectLater(pending, throwsA(isA<SourceException>()));
    expect(started, 1);
  });

  test('an idle engine shuts down and starts again on the next call', () async {
    await store('plugin_a');
    final source = (await repository(
      idleTimeout: const Duration(milliseconds: 40),
    ).loadInstalled()).single;
    addTearDown(source.dispose);

    await search(source);
    expect(source.isStarted, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(source.isStarted, isFalse);

    final page = await search(source);
    expect(page.items.single.ref.itemId, 'x');
    expect(started, 2);
  });

  test('a fresh install leaves its engine stopped', () async {
    final source = await repository().installSource(
      _script,
      Uri.parse('https://plugins.example/p.js'),
    );
    addTearDown(source.dispose);

    // One engine read the plugin's metadata, then was released.
    expect(started, 1);
    expect(source.isStarted, isFalse);
    expect(source.hasLyric, isTrue);
    expect((await search(source)).items, hasLength(1));
    expect(started, 2);
  });
}
