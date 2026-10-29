import 'dart:io';

import 'package:test/test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

void main() {
  EgressPolicy resolvingTo(List<String> addresses) => EgressPolicy(
    lookup: (_) async => [for (final a in addresses) InternetAddress(a)],
  );

  group('EgressPolicy.isPublic', () {
    const blocked = [
      '0.0.0.0',
      '10.1.2.3',
      '100.64.0.1',
      '127.0.0.1',
      '127.8.9.10',
      '169.254.169.254',
      '172.16.0.1',
      '172.31.255.255',
      '192.0.0.8',
      '192.168.1.1',
      '198.18.0.1',
      '224.0.0.1',
      '255.255.255.255',
      '::',
      '::1',
      '::ffff:127.0.0.1',
      '::ffff:192.168.1.1',
      '64:ff9b::a00:1',
      'fc00::1',
      'fd12:3456::1',
      'fe80::1',
      'fec0::1',
      'ff02::1',
    ];
    const allowed = [
      '1.1.1.1',
      '8.8.8.8',
      '172.32.0.1',
      '100.128.0.1',
      '204.62.247.86',
      '2606:4700:4700::1111',
      '::ffff:8.8.8.8',
    ];

    for (final address in blocked) {
      test('blocks $address', () {
        expect(EgressPolicy.isPublic(InternetAddress(address)), isFalse);
      });
    }
    for (final address in allowed) {
      test('allows $address', () {
        expect(EgressPolicy.isPublic(InternetAddress(address)), isTrue);
      });
    }
  });

  group('EgressPolicy.vet', () {
    test('accepts a public host and returns its addresses', () async {
      final addresses = await resolvingTo([
        '93.184.216.34',
      ]).vet(Uri.parse('https://example.org/a.mp3'));

      expect(addresses.single.address, '93.184.216.34');
    });

    test('rejects a public-looking name that resolves to loopback', () {
      expect(
        resolvingTo([
          '127.0.0.1',
        ]).vet(Uri.parse('https://127.0.0.1.nip.io/quit')),
        throwsA(isA<EgressDeniedException>()),
      );
    });

    test('rejects a name when any resolved address is private', () {
      expect(
        resolvingTo([
          '93.184.216.34',
          '10.0.0.5',
        ]).vet(Uri.parse('https://mixed.example/')),
        throwsA(isA<EgressDeniedException>()),
      );
    });

    for (final url in [
      'http://localhost:8787/quit',
      'http://app.localhost/',
      'http://printer.local/',
      'http://127.0.0.1:8787/quit',
      'http://[::ffff:127.0.0.1]:8787/',
      'http://[::]:8787/',
      'http://127.1/',
      'http://0177.0.0.1/',
      'http://2130706433/',
      'http://0x7f000001/',
      'http://10.1/',
    ]) {
      test('rejects $url without resolving it', () async {
        var looked = false;
        final policy = EgressPolicy(
          lookup: (_) async {
            looked = true;
            return [InternetAddress('93.184.216.34')];
          },
        );

        await expectLater(
          policy.vet(Uri.parse(url)),
          throwsA(isA<EgressDeniedException>()),
        );
        expect(looked, isFalse);
      });
    }

    for (final url in [
      'file:///etc/passwd',
      'ftp://example.org/a',
      'data:audio/mpeg;base64,AA==',
    ]) {
      test('rejects the $url scheme', () {
        expect(
          resolvingTo(['93.184.216.34']).vet(Uri.parse(url)),
          throwsA(isA<EgressDeniedException>()),
        );
      });
    }

    test('rejects plain http when https is required', () {
      expect(
        resolvingTo([
          '93.184.216.34',
        ]).vet(Uri.parse('http://example.org/p.js'), httpsOnly: true),
        throwsA(isA<EgressDeniedException>()),
      );
    });

    test('rejects a host that does not resolve', () {
      expect(
        resolvingTo(const []).vet(Uri.parse('https://nothing.invalid/')),
        throwsA(isA<EgressDeniedException>()),
      );
    });
  });

  group('EgressPolicy.attach', () {
    test('refuses to connect a client to a loopback server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var reached = false;
      server.listen((request) {
        reached = true;
        request.response.close();
      });
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      const EgressPolicy().attach(client);

      await expectLater(() async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/quit'),
        );
        await request.close();
      }(), throwsA(isA<EgressDeniedException>()));
      expect(reached, isFalse);
    });

    test('checks every redirect hop', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final hosts = <String>[];
      server.listen((request) {
        hosts.add(request.headers.host ?? '');
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://localhost:${server.port}/internal',
          )
          ..close();
      });
      // "public.test" resolves to the loopback test server so the first hop
      // connects; the redirect to localhost must then be refused.
      final policy = EgressPolicy(
        lookup: (_) async => [InternetAddress.loopbackIPv4],
        isPublicAddress: (_) => true,
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      policy.attach(client);

      await expectLater(() async {
        final request = await client.getUrl(
          Uri.parse('http://public.test:${server.port}/start'),
        );
        await (await request.close()).drain<void>();
      }(), throwsA(isA<EgressDeniedException>()));
      expect(hosts, hasLength(1));
    });
  });
}
