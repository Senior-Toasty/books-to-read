enum BookFormat { ebook, audiobook, catalogue }

enum SearchMode { all, ebooks, audiobooks }

class BookResult {
  const BookResult({
    required this.title,
    required this.authors,
    required this.source,
    required this.url,
    required this.format,
    this.year,
    this.coverUrl,
    this.description,
    this.accessLabel,
  });

  final String title;
  final String authors;
  final String source;
  final String url;
  final BookFormat format;
  final String? year;
  final String? coverUrl;
  final String? description;
  final String? accessLabel;

  String get dedupeKey =>
      '${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}|'
      '${authors.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}|'
      '${format.name}';

  Map<String, dynamic> toJson() => {
        'title': title, 'authors': authors, 'source': source, 'url': url,
        'format': format.name, 'year': year, 'coverUrl': coverUrl,
        'description': description, 'accessLabel': accessLabel,
      };

  factory BookResult.fromJson(Map<String, dynamic> json) => BookResult(
        title: json['title']?.toString() ?? '',
        authors: json['authors']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        format: BookFormat.values.firstWhere(
          (value) => value.name == json['format'],
          orElse: () => BookFormat.catalogue,
        ),
        year: json['year']?.toString(),
        coverUrl: json['coverUrl']?.toString(),
        description: json['description']?.toString(),
        accessLabel: json['accessLabel']?.toString(),
      );

  bool matches(SearchMode mode) => switch (mode) {
        SearchMode.all => true,
        SearchMode.ebooks => format != BookFormat.audiobook,
        SearchMode.audiobooks => format == BookFormat.audiobook,
      };
}

class ProviderFailure {
  const ProviderFailure(this.provider, this.message);
  final String provider;
  final String message;
}
