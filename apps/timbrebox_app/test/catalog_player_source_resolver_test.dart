import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/state/audio_source.dart';
import 'package:timbrebox_app/app/state/catalog_player_source_resolver.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test('maps a resolved stream to a transient native source', () async {
    final resolver = CatalogPlayerSourceResolver(_Resolver());
    const candidate = StreamCandidate(
      ref: MediaRef(sourceId: 'youtube', itemId: 'video-1'),
      id: 'tb://youtube/video-1',
      label: 'high',
    );

    final source = await resolver.resolve(candidate);
    expect(source, isA<RemoteAudioSource>());
    final remote = source as RemoteAudioSource;
    expect(remote.uri.toString(), 'https://media.example/audio');
    expect(remote.headers, {'X-Stream': 'ephemeral'});
  });
}

class _Resolver implements StreamResolver {
  @override
  Future<ResolvedStream> resolve(StreamRequest request) async => ResolvedStream(
    uri: Uri.parse('https://media.example/audio'),
    headers: const {'X-Stream': 'ephemeral'},
  );
}
