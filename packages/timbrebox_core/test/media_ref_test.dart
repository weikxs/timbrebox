import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test('round trips source and item identifiers', () {
    const ref = MediaRef(sourceId: 'youtube', itemId: 'a/b c');

    expect(MediaRef.parse(ref.toString()), ref);
  });

  test('rejects a non TimbreBox media reference', () {
    expect(
      () => MediaRef.parse('https://example.com/song'),
      throwsFormatException,
    );
  });

  test('rejects invalid source identifiers', () {
    expect(
      () => SourceDescriptor(
        id: 'YouTube',
        name: 'YouTube',
        capabilities: const [],
      ),
      throwsArgumentError,
    );
  });
}
