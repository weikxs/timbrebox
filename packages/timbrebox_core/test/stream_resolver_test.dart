import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test(
    'stream requests carry stable refs, resolved URL stays ephemeral',
    () async {
      final ref = MediaRef(sourceId: 'youtube', itemId: 'video-1');
      final resolver = _Resolver();
      final stream = await resolver.resolve(
        StreamRequest(
          ref: ref,
          quality: 'high',
          cancellation: CancellationToken(),
        ),
      );

      expect(resolver.lastRequest?.ref, ref);
      expect(stream.uri.scheme, 'https');
      expect(stream.headers, isEmpty);
      expect(stream.isExpired, isFalse);
    },
  );

  test('expired stream is reported without persisting credentials', () {
    final stream = ResolvedStream(
      uri: Uri.parse('https://media.example/audio'),
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );

    expect(stream.isExpired, isTrue);
  });
}

class _Resolver implements StreamResolver {
  StreamRequest? lastRequest;

  @override
  Future<ResolvedStream> resolve(StreamRequest request) async {
    lastRequest = request;
    request.cancellation.throwIfCancelled();
    return ResolvedStream(uri: Uri.parse('https://media.example/audio'));
  }
}
