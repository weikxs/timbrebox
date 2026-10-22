import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/data/video_source_adapters.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  // YouTube now goes through youtube_explode_dart (real network, not fixture-
  // mockable); it is covered by integration_test/playback_test.dart instead.

  test('Bilibili maps anonymous search and DASH audio response', () async {
    final source = BilibiliCatalogSource(
      http: SourceHttpClient.withReader((
        uri,
        body,
        headers,
        cancellation,
      ) async {
        if (uri.path.endsWith('/search/type')) {
          return '''{"data":{"result":[{"bvid":"BV1","title":"<em>Track</em>","author":"Artist"}]}}''';
        }
        if (uri.path.endsWith('/view')) {
          return '{"data":{"pages":[{"cid":9}]}}';
        }
        return '''{"data":{"dash":{"audio":[{"baseUrl":"https://media.example/bili.m4a"}]}}}''';
      }),
    );
    final track = (await source.search(_request('track'))).items.single;
    expect(track.title, 'Track');
    final stream = await source.resolve(
      StreamRequest(
        ref: track.ref,
        quality: 'public',
        cancellation: CancellationToken(),
      ),
    );
    expect(stream.uri.host, 'media.example');
    expect(stream.headers['Referer'], 'https://www.bilibili.com/');
  });

  test(
    'TikTok parses embedded public page state without fabricated rows',
    () async {
      final source = TikTokCatalogSource(
        http: SourceHttpClient.withReader(
          (uri, body, headers, cancellation) async =>
              '''<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"itemStruct":{"id":"tt-1","desc":"Public clip","author":{"nickname":"Creator"},"video":{"playAddr":"https://media.example/tt.mp4"}}}</script>''',
        ),
      );
      final track = (await source.search(_request('clip'))).items.single;
      expect(track.title, 'Public clip');
      expect(track.artist, 'Creator');
    },
  );

  test(
    'short-video sources reject pages without a playable public record',
    () async {
      final source = DouyinCatalogSource(
        http: SourceHttpClient.withReader(
          (uri, body, headers, cancellation) async => '<html></html>',
        ),
      );

      await expectLater(
        source.search(_request('clip')),
        throwsA(
          isA<SourceException>().having(
            (error) => error.code,
            'code',
            'source_no_public_results',
          ),
        ),
      );
    },
  );
}

SearchRequest _request(String query) =>
    SearchRequest(query: query, cancellation: CancellationToken());
