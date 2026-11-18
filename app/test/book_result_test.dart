import 'package:bookhunter/search/book_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('book result survives JSON serialization for the saved library', () {
    const original = BookResult(
      title: 'The Example Book',
      authors: 'A. Writer',
      source: 'Project Gutenberg',
      url: 'https://www.gutenberg.org/ebooks/123',
      format: BookFormat.ebook,
      year: '1920',
      coverUrl: 'https://example.org/cover.jpg',
      description: 'A short description',
      accessLabel: 'Public-domain ebook',
    );

    final restored = BookResult.fromJson(original.toJson());

    expect(restored.title, original.title);
    expect(restored.authors, original.authors);
    expect(restored.source, original.source);
    expect(restored.url, original.url);
    expect(restored.format, original.format);
    expect(restored.year, original.year);
    expect(restored.coverUrl, original.coverUrl);
    expect(restored.description, original.description);
    expect(restored.accessLabel, original.accessLabel);
  });
}
