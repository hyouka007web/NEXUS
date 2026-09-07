class QuickLink {
  final String label;
  final String url;

  const QuickLink({required this.label, required this.url});

  Map<String, dynamic> toJson() => {'label': label, 'url': url};

  factory QuickLink.fromJson(Map<String, dynamic> json) => QuickLink(
        label: json['label'] as String,
        url: json['url'] as String,
      );
}
