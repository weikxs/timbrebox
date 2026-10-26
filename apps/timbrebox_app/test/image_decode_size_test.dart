import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/widgets/track_artwork.dart';

/// Artwork is decoded at the size it is shown at, not at the source's size.
void main() {
  testWidgets('a cover tile decodes at its own pixel height', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    const track = CatalogTrack(
      id: 'a',
      title: 'Track',
      artist: 'Artist',
      sourceId: 'audius',
      sourceName: 'Audius',
      duration: Duration.zero,
      quality: 'public',
      artworkUrl: 'https://cdn.example/cover-1000.jpg',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: TrackArtwork(track: track, size: 46)),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    final resized = image as ResizeImage;
    expect(resized.height, 92);
    expect(resized.width, isNull); // Keeps the source's aspect ratio.
  });
}
