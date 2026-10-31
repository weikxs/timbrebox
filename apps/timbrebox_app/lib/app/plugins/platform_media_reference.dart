import 'media_extractor_process.dart';

/// Only page identities cross into the extraction process, never arbitrary URLs.
final class PlatformMediaReference {
  const PlatformMediaReference(
    this.platform,
    this.url, {
    this.id,
    this.handle,
    this.part,
  });
  final String platform;
  final Uri url;
  final String? id;
  final String? handle;
  final int? part;

  static const platforms = {'youtube', 'bilibili', 'douyin', 'tiktok'};
  static Never _invalid() => throw const MediaExtractionException(
    'invalid_media_reference',
    'A supported public video link is required.',
  );

  static PlatformMediaReference parse(String platform, String input) {
    if (!platforms.contains(platform) || input.length > 8192) _invalid();
    final match = RegExp(r'''https?://[^\s<>"'，。！？；（）【】]+''').firstMatch(input);
    final uri = match == null ? null : Uri.tryParse(match.group(0)!);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      _invalid();
    }
    final path = uri.pathSegments.toList();
    if (path.isNotEmpty && path.last.isEmpty) path.removeLast();
    final host = uri.host.toLowerCase();
    String? id;
    String? handle;
    int? part;
    Uri? url;
    switch (platform) {
      case 'youtube':
        if (host == 'youtu.be' && path.length == 1) id = path.first;
        if ({
          'youtube.com',
          'www.youtube.com',
          'm.youtube.com',
          'music.youtube.com',
        }.contains(host)) {
          if (uri.path == '/watch') id = uri.queryParameters['v'];
          if (path.length == 2 &&
              {'shorts', 'embed', 'live'}.contains(path.first)) {
            id = path[1];
          }
        }
        if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
          _invalid();
        }
        url = Uri.https('www.youtube.com', '/watch', {'v': id});
      case 'bilibili':
        if (host == 'b23.tv' &&
            path.length == 1 &&
            RegExp(r'^[A-Za-z0-9]+$').hasMatch(path.first)) {
          url = Uri.https(host, '/${path.first}');
          break;
        }
        if (!{
              'bilibili.com',
              'www.bilibili.com',
              'm.bilibili.com',
            }.contains(host) ||
            path.length != 2 ||
            path.first != 'video') {
          _invalid();
        }
        id = path[1];
        if (!RegExp(r'^BV[A-Za-z0-9]{10}$').hasMatch(id)) _invalid();
        if (uri.queryParameters.containsKey('p')) {
          part = int.tryParse(uri.queryParameters['p']!);
          if (part == null || part < 1 || part > 1000) _invalid();
        }
        url = Uri.https(
          'www.bilibili.com',
          '/video/$id',
          part == null ? null : {'p': '$part'},
        );
      case 'douyin':
        if (host == 'v.douyin.com' &&
            path.length == 1 &&
            RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(path.first)) {
          url = Uri.https(host, '/${path.first}/');
          break;
        }
        if (!{
          'douyin.com',
          'www.douyin.com',
          'www.iesdouyin.com',
        }.contains(host)) {
          _invalid();
        }
        if (path.length == 2 && path.first == 'video') id = path[1];
        if (path.length == 3 && path[0] == 'share' && path[1] == 'video') {
          id = path[2];
        }
        if (id == null || !RegExp(r'^\d{10,25}$').hasMatch(id)) _invalid();
        url = Uri.https('www.douyin.com', '/video/$id');
      case 'tiktok':
        if ({'vm.tiktok.com', 'vt.tiktok.com'}.contains(host) &&
            path.length == 1 &&
            RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(path.first)) {
          url = Uri.https(host, '/${path.first}/');
          break;
        }
        if (!{'tiktok.com', 'www.tiktok.com', 'm.tiktok.com'}.contains(host)) {
          _invalid();
        }
        if (path.length == 2 &&
            path.first == 't' &&
            RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(path[1])) {
          url = Uri.https('www.tiktok.com', '/t/${path[1]}/');
          break;
        }
        if (path.length != 3 ||
            !path.first.startsWith('@') ||
            path[1] != 'video') {
          _invalid();
        }
        handle = path.first.substring(1);
        id = path[2];
        if (!RegExp(r'^[A-Za-z0-9_.]{1,64}$').hasMatch(handle) ||
            !RegExp(r'^\d{10,25}$').hasMatch(id)) {
          _invalid();
        }
        url = Uri.https('www.tiktok.com', '/@$handle/video/$id');
    }
    if (url == null) _invalid();
    return PlatformMediaReference(
      platform,
      url,
      id: id,
      handle: handle,
      part: part,
    );
  }

  static PlatformMediaReference fromItem(String platform, Map item) {
    final id = platform == 'bilibili'
        ? item['videoId'] ?? item['id']
        : item['id'];
    if (id is! String || id.length > 64) _invalid();
    final address = switch (platform) {
      'youtube' => 'https://www.youtube.com/watch?v=$id',
      'bilibili' =>
        'https://www.bilibili.com/video/$id${item['part'] == null ? '' : '?p=${item['part']}'}',
      'douyin' => 'https://www.douyin.com/video/$id',
      'tiktok' => 'https://www.tiktok.com/@${item['handle']}/video/$id',
      _ => '',
    };
    final reference = parse(platform, address);
    // Interpolation must not turn crafted IDs/handles into a different identity.
    if (reference.id != id ||
        platform == 'tiktok' && reference.handle != item['handle']) {
      _invalid();
    }
    return reference;
  }
}
