/// A media candidate discovered by the NEXUS Video Harvester.
///
/// Context is intentionally limited to information the page/WebView exposes
/// to the application. HttpOnly cookies, DRM keys and protected browser
/// internals are never extracted.
class HarvestedVideo {
  final String title;
  final String url;
  final String host;
  final String type;
  final String status;
  final bool selected;
  final String source;
  final String pageUrl;
  final String referrer;
  final String userAgent;
  final Map<String, String> headers;
  final String cookies;
  final String quality;
  final List<MediaVariant> variants;

  const HarvestedVideo({
    required this.title,
    required this.url,
    required this.host,
    required this.type,
    required this.status,
    this.selected = true,
    this.source = 'UNKNOWN',
    this.pageUrl = '',
    this.referrer = '',
    this.userAgent = '',
    this.headers = const {},
    this.cookies = '',
    this.quality = '',
    this.variants = const [],
  });

  HarvestedVideo copyWith({
    bool? selected,
    String? status,
    String? source,
    String? pageUrl,
    String? referrer,
    String? userAgent,
    Map<String, String>? headers,
    String? cookies,
    String? quality,
    List<MediaVariant>? variants,
  }) => HarvestedVideo(
        title: title,
        url: url,
        host: host,
        type: type,
        status: status ?? this.status,
        selected: selected ?? this.selected,
        source: source ?? this.source,
        pageUrl: pageUrl ?? this.pageUrl,
        referrer: referrer ?? this.referrer,
        userAgent: userAgent ?? this.userAgent,
        headers: headers ?? this.headers,
        cookies: cookies ?? this.cookies,
        quality: quality ?? this.quality,
        variants: variants ?? this.variants,
      );
}

class MediaVariant {
  final String url;
  final String quality;
  final int bandwidth;
  final String codecs;
  final String mimeType;

  const MediaVariant({
    required this.url,
    this.quality = '',
    this.bandwidth = 0,
    this.codecs = '',
    this.mimeType = '',
  });
}
