import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/plugins/plugin_environment.dart';
import 'package:timbrebox_app/app/plugins/plugin_http.dart';
import 'package:timbrebox_app/app/plugins/plugin_runtime.dart';

/// The plugin format's module shapes, globals and axios usage, as plugins
/// rely on them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String base;

  // The test binding stubs HttpClient; these tests talk to a loopback server.
  final stubbed = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = stubbed);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://public.test:${server.port}';
    server.listen(_answer);
  });

  tearDown(() => server.close(force: true));

  Future<PluginRuntime> load(
    String source, {
    PluginEnvironment environment = const PluginEnvironment(
      appVersion: '9.9.9',
      os: 'linux',
      language: 'zh-CN',
    ),
  }) async {
    final runtime = PluginRuntime(
      http: PluginHttpClient(
        policy: EgressPolicy(
          lookup: (_) async => [InternetAddress.loopbackIPv4],
          isPublicAddress: (_) => true,
        ),
      ),
      environment: environment,
    );
    addTearDown(runtime.dispose);
    await runtime.load(source);
    return runtime;
  }

  /// Runs [body] (the inside of an async function) and returns what it
  /// returns, decoded.
  Future<Object?> run(String body, {String setup = ''}) async {
    final runtime = await load('''
$setup
module.exports = {
  platform: 'Compat',
  search: async function () { return { isEnd: true, data: [] }; },
  probe: async function () { $body },
};
''');
    return runtime.call('probe', const []);
  }

  group('module shapes', () {
    test('a plugin exported as exports.default loads', () async {
      final runtime = await load('''
exports.default = {
  platform: 'Default export',
  version: '1.0.0',
  search: async function () { return { isEnd: true, data: [] }; },
};
''');

      expect(runtime.meta('platform'), 'Default export');
      expect(runtime.hasFunction('search'), isTrue);
    });

    test('a module.exports object without default stays as it is', () async {
      final runtime = await load('''
module.exports = {
  platform: 'Plain',
  search: async function () { return { isEnd: true, data: [] }; },
};
''');

      expect(runtime.meta('platform'), 'Plain');
    });

    test('require resolves the whitelist and refuses anything else', () async {
      expect(
        await run(
          "return typeof require('cheerio').load;",
          setup: "const c = require('cheerio');",
        ),
        'function',
      );
      expect(
        await run("try { require('fs'); } catch (e) { return 'refused'; }"),
        'refused',
      );
    });
  });

  group('env and process', () {
    test('env describes the app, the system and the language', () async {
      expect(
        await run(
          'return [env.appVersion, env.os, env.lang, '
          'JSON.stringify(env.getUserVariables())];',
        ),
        ['9.9.9', 'linux', 'zh-CN', '{}'],
      );
    });

    test('process carries the platform, version and env', () async {
      expect(
        await run(
          'return [process.platform, process.version, process.env === env];',
        ),
        ['linux', '9.9.9', true],
      );
    });

    test('a plugin cannot change what env reports', () async {
      expect(
        await run(
          "try { env.appVersion = 'x'; } catch (e) {} "
          'env.getUserVariables().k = 1; '
          'return [env.appVersion, JSON.stringify(env.getUserVariables())];',
        ),
        ['9.9.9', '{}'],
      );
    });
  });

  group('URL', () {
    test('parses the parts of an absolute URL', () async {
      expect(
        await run(
          "const u = new URL('https://user:pw@a.example:8443/p/q?x=1&y=2#h'); "
          'return [u.protocol, u.username, u.password, u.hostname, u.port, '
          'u.host, u.origin, u.pathname, u.search, u.hash, u.href];',
        ),
        [
          'https:',
          'user',
          'pw',
          'a.example',
          '8443',
          'a.example:8443',
          'https://a.example:8443',
          '/p/q',
          '?x=1&y=2',
          '#h',
          'https://user:pw@a.example:8443/p/q?x=1&y=2#h',
        ],
      );
    });

    test('resolves a relative URL against a base', () async {
      expect(
        await run(
          'return [new URL(\'../r?z=3\', \'https://a.example/p/q/s\').href, '
          "new URL('/top', 'https://a.example/p/q').href, "
          "new URL('//b.example/x', 'https://a.example/p').href];",
        ),
        [
          'https://a.example/p/r?z=3',
          'https://a.example/top',
          'https://b.example/x',
        ],
      );
    });

    test('searchParams reads and writes the query', () async {
      expect(
        await run(
          "const u = new URL('https://a.example/s?q=%E5%A4%9C%E7%AA%97&n=1'); "
          "u.searchParams.append('page', '2'); "
          "u.searchParams.set('n', '5'); "
          "return [u.searchParams.get('q'), u.href];",
        ),
        ['夜窗', 'https://a.example/s?q=%E5%A4%9C%E7%AA%97&n=5&page=2'],
      );
    });

    test('URLSearchParams accepts a string, an object and pairs', () async {
      expect(
        await run(
          "return [new URLSearchParams('?a=1&b=x+y').toString(), "
          "new URLSearchParams({ a: '1', b: 'x y' }).toString(), "
          "new URLSearchParams([['a', '1'], ['a', '2']]).getAll('a').join()];",
        ),
        ['a=1&b=x+y', 'a=1&b=x+y', '1,2'],
      );
    });

    test('an invalid URL throws a TypeError', () async {
      expect(
        await run(
          "try { new URL('not a url'); return 'parsed'; } "
          'catch (e) { return e instanceof TypeError; }',
        ),
        true,
      );
    });
  });

  group('axios', () {
    test('create merges baseURL, headers and params', () async {
      final echo = await run('''
const api = axios.create({
  baseURL: '$base/api',
  headers: { 'X-From': 'instance' },
  params: { lang: 'zh' },
});
const res = await api.get('/songs', { params: { page: 2 } });
return res.data;
''');

      expect(echo, containsPair('path', '/api/songs'));
      expect(echo, containsPair('query', {'lang': 'zh', 'page': '2'}));
      expect((echo! as Map)['headers'], containsPair('x-from', 'instance'));
    });

    test('defaults apply to every request', () async {
      final echo = await run('''
axios.defaults.headers.common['X-Common'] = 'yes';
axios.defaults.headers.get = { 'X-Get': 'only-get' };
const res = await axios.get('$base/d');
return res.data;
''');

      expect((echo! as Map)['headers'], containsPair('x-common', 'yes'));
      expect((echo as Map)['headers'], containsPair('x-get', 'only-get'));
    });

    test('put, patch, delete, head and request send their method', () async {
      expect(
        await run('''
const methods = [];
methods.push((await axios.put('$base/m', { a: 1 })).data.method);
methods.push((await axios.patch('$base/m', 'raw')).data.method);
methods.push((await axios.delete('$base/m')).data.method);
methods.push((await axios.head('$base/m')).status);
methods.push((await axios.request({ url: '$base/m', method: 'post' })).data.method);
return methods;
'''),
        ['PUT', 'PATCH', 'DELETE', 200, 'POST'],
      );
    });

    test('an object body is sent as JSON with its content type', () async {
      final echo = await run('''
return (await axios.post('$base/j', { name: '夜窗' })).data;
''');

      expect(echo, containsPair('body', '{"name":"夜窗"}'));
      expect(
        (echo! as Map)['headers'],
        containsPair('content-type', startsWith('application/json')),
      );
    });

    test('interceptors change the request and the response', () async {
      final result = await run('''
const api = axios.create();
api.interceptors.request.use(function (config) {
  config.headers['X-Signed'] = 'sig';
  return config;
});
const id = api.interceptors.response.use(function (res) {
  res.data.seen = true;
  return res;
});
const first = (await api.get('$base/i')).data;
api.interceptors.response.eject(id);
const second = (await api.get('$base/i')).data;
return [first.headers['x-signed'], first.seen, second.seen === undefined];
''');

      expect(result, ['sig', true, true]);
    });

    test('a non-2xx status rejects with the response attached', () async {
      expect(
        await run('''
try {
  await axios.get('$base/status/404');
  return 'resolved';
} catch (e) {
  return [e.isAxiosError, e.response.status, e.response.data, e.message];
}
'''),
        [true, 404, 'missing', 'Request failed with status code 404'],
      );
    });

    test('validateStatus decides which statuses resolve', () async {
      expect(
        await run('''
const res = await axios.get('$base/status/404', {
  validateStatus: function () { return true; },
});
return res.status;
'''),
        404,
      );
    });

    test('a timeout rejects with ECONNABORTED', () async {
      expect(
        await run('''
try {
  await axios.get('$base/slow', { timeout: 300 });
  return 'resolved';
} catch (e) {
  return e.code;
}
'''),
        'ECONNABORTED',
      );
    });

    test(
      'a Cookie header the plugin sets is sent as it is, every time',
      () async {
        expect(
          await run('''
const seen = [];
for (let i = 0; i < 2; i++) {
  const res = await axios.get('$base/c', { headers: { Cookie: 'session=demo' } });
  seen.push(res.data.headers.cookie);
}
return seen;
'''),
          ['session=demo', 'session=demo'],
        );
      },
    );

    test('JSON bodies are parsed unless text was asked for', () async {
      expect(
        await run('''
const parsed = (await axios.get('$base/j')).data;
const text = (await axios.get('$base/j', { responseType: 'text' })).data;
return [typeof parsed, typeof text];
'''),
        ['object', 'string'],
      );
    });
  });
}

/// Echoes the request as JSON; `/status/<code>` answers that status with the
/// body `missing`, and `/slow` answers after two seconds.
Future<void> _answer(HttpRequest request) async {
  final path = request.uri.path;
  final response = request.response;
  if (path.startsWith('/status/')) {
    response
      ..statusCode = int.parse(path.substring('/status/'.length))
      ..headers.contentType = ContentType.text
      ..write('missing');
    await response.close();
    return;
  }
  if (path == '/slow') {
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  final body = await utf8.decodeStream(request);
  final headers = <String, String>{};
  request.headers.forEach((name, values) => headers[name] = values.join(', '));
  response
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode({
        'method': request.method,
        'path': path,
        'query': request.uri.queryParameters,
        'headers': headers,
        'body': body,
      }),
    );
  await response.close();
}
