import 'dart:io';

import 'package:test/test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

void main() {
  EgressPolicy resolvingTo(String address, {Set<String> lanHosts = const {}}) =>
      EgressPolicy(
        lookup: (_) async => [InternetAddress(address)],
      ).allowingLanHosts(lanHosts);

  group('a LAN host the user entered', () {
    test('is reached by its address', () async {
      final policy = const EgressPolicy().allowingLanHosts({
        '192.168.0.10:4533',
      });

      await policy.vet(Uri.parse('http://192.168.0.10:4533/'));
    });

    test('is reached by a .local name', () async {
      final policy = resolvingTo('10.0.0.5', lanHosts: {'nas.local:80'});

      await policy.vet(Uri.parse('http://nas.local/music'));
    });

    for (final address in ['10.1.2.3', '172.16.0.1', '100.64.0.1', 'fd00::1']) {
      test('may be in the private range of $address', () async {
        final host = address.contains(':') ? '[$address]' : address;
        final policy = const EgressPolicy().allowingLanHosts({'$address:443'});

        await policy.vet(Uri.parse('https://$host/'));
      });
    }
  });

  group('still blocked', () {
    // Whoever controls a domain's DNS could point it at any device on the
    // home network; only an address or a .local name is the user's own.
    test('a domain name the user entered that resolves into the LAN', () {
      final policy = resolvingTo(
        '192.168.0.10',
        lanHosts: {'nas.example:4533'},
      );

      expect(
        policy.vet(Uri.parse('http://nas.example:4533/rest/ping')),
        throwsA(isA<EgressDeniedException>()),
      );
    });

    test('a LAN host the user did not enter', () {
      final policy = resolvingTo(
        '192.168.0.11',
        lanHosts: {'nas.example:4533'},
      );

      expect(
        policy.vet(Uri.parse('http://printer.example:4533/')),
        throwsA(isA<EgressDeniedException>()),
      );
    });

    test('the entered host on another port', () {
      final policy = resolvingTo(
        '192.168.0.10',
        lanHosts: {'nas.example:4533'},
      );

      expect(
        policy.vet(Uri.parse('http://nas.example:22/')),
        throwsA(isA<EgressDeniedException>()),
      );
    });

    for (final address in ['127.0.0.1', '::1', '169.254.169.254', '0.0.0.0']) {
      test('$address even when the user entered it', () {
        final policy = resolvingTo(address, lanHosts: {'nas.example:80'});

        expect(
          policy.vet(Uri.parse('http://nas.example/')),
          throwsA(isA<EgressDeniedException>()),
        );
      });
    }

    test('localhost even when the user entered it', () {
      final policy = const EgressPolicy().allowingLanHosts({'localhost:80'});

      expect(
        policy.vet(Uri.parse('http://localhost/')),
        throwsA(isA<EgressDeniedException>()),
      );
    });
  });

  group('lanHostsIn', () {
    test('takes the host and port of every http(s) address', () {
      expect(
        EgressPolicy.lanHostsIn([
          'http://NAS.example:4533/music',
          'https://192.168.0.10',
          'http://[fd00::1]:8096',
          'demo',
          'ftp://files.example/',
          '',
        ]),
        {'nas.example:4533', '192.168.0.10:443', 'fd00::1:8096'},
      );
    });
  });

  group('StreamHeaderProxy', () {
    late HttpServer upstream;

    setUp(() async {
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen(
        (request) => request.response
          ..write('audio')
          ..close(),
      );
    });

    tearDown(() => upstream.close(force: true));

    Future<int> fetch(Uri local) async {
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(local)).close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    test('relays a stream with the policy it was published with', () async {
      // Loopback stands in for the LAN here: the proxy's own policy blocks
      // it, the stream's policy lets the entered host through.
      const blocked = EgressPolicy();
      final allowed = EgressPolicy(
        isLanAddress: (address) => address.isLoopback,
      ).allowingLanHosts({'127.0.0.1:${upstream.port}'});
      final proxy = StreamHeaderProxy(policy: blocked);
      addTearDown(proxy.dispose);
      final target = Uri.parse('http://127.0.0.1:${upstream.port}/a');

      final withLan = await proxy.publish(target, const {}, policy: allowed);
      final withoutLan = await proxy.publish(target, const {});

      expect(await fetch(withLan), HttpStatus.ok);
      expect(await fetch(withoutLan), HttpStatus.badGateway);
    });

    test('drops the client of a policy no stream uses any more', () async {
      final allowed = EgressPolicy(
        isLanAddress: (address) => address.isLoopback,
      ).allowingLanHosts({'127.0.0.1:${upstream.port}'});
      final proxy = StreamHeaderProxy(
        policy: EgressPolicy(isPublicAddress: (address) => address.isLoopback),
      );
      addTearDown(proxy.dispose);
      final target = Uri.parse('http://127.0.0.1:${upstream.port}/a');
      await fetch(await proxy.publish(target, const {}, policy: allowed));
      expect(proxy.upstreamClientCount, 1);

      // Newer streams push the one published with the LAN policy out.
      late Uri latest;
      for (var i = 0; i < 8; i++) {
        latest = await proxy.publish(target, const {});
      }
      await fetch(latest);

      expect(proxy.upstreamClientCount, 1);
    });
  });
}
