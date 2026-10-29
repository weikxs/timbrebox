import 'package:timbrebox_core/timbrebox_core.dart';

import '../design/app_strings.dart';
import 'package:timbrebox_sources/timbrebox_sources.dart';

/// Parses the `url` a plugin's `getMediaSource` returned and checks it against
/// [policy] before anything plays, proxies or downloads it: a plugin must not
/// point the player at `file://` paths, the local machine or the LAN.
Future<Uri> checkedPluginStreamUri(
  String? url, {
  EgressPolicy policy = const EgressPolicy(),
}) async {
  final parsed = Uri.tryParse(url ?? '');
  if (url == null || url.isEmpty || parsed == null || !parsed.hasScheme) {
    throw SourceException(
      AppStrings.t('plugin.src.noUrl'),
      retryable: false,
      code: 'source_stream_unavailable',
    );
  }
  try {
    await policy.vet(parsed);
  } on EgressDeniedException catch (error) {
    throw SourceException(
      error.message,
      retryable: false,
      code: 'stream_url_blocked',
    );
  }
  return parsed;
}
