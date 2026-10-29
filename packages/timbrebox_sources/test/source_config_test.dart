import 'package:test/test.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

void main() {
  group('SourceEndpoint.uri', () {
    const endpoint = SourceEndpoint(
      host: 'example.org',
      paths: {'file': '/download/{id}/{file}', 'search': '/search/{query}'},
    );

    test('encodes a path value with spaces and brackets exactly once', () {
      final uri = endpoint.uri(
        'file',
        pathValues: {
          'id': 'item-1',
          'file': '01 - Clair de lune (Suite bergamasque).flac',
        },
      );

      expect(uri.toString(), isNot(contains('%25')));
      expect(
        uri.toString(),
        'https://example.org/download/item-1/01%20-%20Clair%20de%20lune%20(Suite%20bergamasque).flac',
      );
      expect(
        uri.pathSegments.last,
        '01 - Clair de lune (Suite bergamasque).flac',
      );
    });

    test('keeps reserved characters inside one path segment', () {
      final uri = endpoint.uri(
        'search',
        pathValues: {'query': 'AC/DC 100% #1?'},
      );

      expect(uri.pathSegments, ['search', 'AC/DC 100% #1?']);
      expect(uri.query, isEmpty);
    });

    test('round-trips non-ASCII path values', () {
      final uri = endpoint.uri('search', pathValues: {'query': '周杰伦 晴天'});

      expect(uri.pathSegments.last, '周杰伦 晴天');
    });

    test('adds query parameters', () {
      final uri = endpoint.uri(
        'search',
        pathValues: {'query': 'jazz'},
        query: {'page': '2', 'q': 'a b'},
      );

      expect(uri.queryParameters, {'page': '2', 'q': 'a b'});
      expect(uri.path, '/search/jazz');
    });

    test('rejects an unknown path key', () {
      expect(() => endpoint.uri('missing'), throwsArgumentError);
    });
  });
}
