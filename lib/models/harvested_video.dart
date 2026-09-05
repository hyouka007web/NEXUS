/// Ein vom [VideoHarvesterEngine] gefundener Kandidat — Pendant zu Kotlins
/// `HarvestedVideo`.
class HarvestedVideo {
  final String title;
  final String url;
  final String host;
  final String type;
  final String status;
  final bool selected;

  const HarvestedVideo({
    required this.title,
    required this.url,
    required this.host,
    required this.type,
    required this.status,
    this.selected = true,
  });

  HarvestedVideo copyWith({bool? selected}) => HarvestedVideo(
        title: title,
        url: url,
        host: host,
        type: type,
        status: status,
        selected: selected ?? this.selected,
      );
}
