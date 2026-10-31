import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/guest_search_runner.dart';
import 'package:timbrebox_app/app/plugins/platform_media_backend.dart';

void main() {
  for (final platform in ['tiktok', 'douyin']) {
    test(
      '$platform keyword search reaches the fixed guest metadata adapter',
      () async {
        final guest = _Guest();
        final backend = DesktopPlatformMediaBackend(guestSearch: guest);
        addTearDown(backend.dispose);
        final result = await backend.call({
          'platform': platform,
          'operation': 'search',
          'query': ' music ',
          'page': 2,
        });
        expect(guest.requests.single, [platform, 'music', 2]);
        final row = (result['data'] as List).single as Map;
        expect(row['accessState'], 'unknown');
        expect(row['contentKind'], 'video_audio');
        expect(result['isEnd'], isFalse);
        expect(row, isNot(contains('webpage_url')));
      },
    );
  }

  test('cancel and dispose propagate to the guest adapter', () {
    final guest = _Guest();
    final backend = DesktopPlatformMediaBackend(guestSearch: guest);
    backend.cancel();
    expect(guest.cancelled, isTrue);
    backend.dispose();
    expect(guest.disposed, isTrue);
  });
}

class _Guest implements GuestSearchRunner {
  final requests = <List<Object>>[];
  bool cancelled = false;
  bool disposed = false;
  @override
  Future<Map<String, Object?>> search(
    String platform,
    String query,
    int page,
  ) async {
    requests.add([platform, query, page]);
    const id = '1000000000000000000';
    return {
      'entries': [
        {
          'id': id,
          'title': 'Protocol fixture',
          'artist': 'Fixture',
          'duration': 20,
          'webpage_url': platform == 'tiktok'
              ? 'https://www.tiktok.com/@fixture_author/video/$id'
              : 'https://www.douyin.com/video/$id',
        },
      ],
      'isEnd': false,
    };
  }

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
