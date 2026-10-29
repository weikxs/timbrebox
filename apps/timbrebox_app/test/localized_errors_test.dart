import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';
import 'package:timbrebox_app/app/design/app_strings.dart';
import 'package:timbrebox_app/app/design/app_strings_more.dart';

void main() {
  tearDown(() => AppStrings.lang = AppLang.zh);

  test('every added string exists in both languages', () {
    expect(moreEnStrings.keys.toSet(), moreZhStrings.keys.toSet());
  });

  test('a source error follows the app language', () async {
    AppStrings.lang = AppLang.en;
    final source = RadioBrowserCatalogSource(readJson: (_, _) async => '[]');

    await expectLater(
      source.resolve(
        StreamRequest(
          ref: const MediaRef(sourceId: 'radio_browser', itemId: 'gone'),
          quality: 'live',
          cancellation: CancellationToken(),
        ),
      ),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          'The station stream is no longer valid — search again.',
        ),
      ),
    );
  });
}
