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
