import 'dart:convert';

import 'package:bookhunter/search/book_result.dart';
import 'package:bookhunter/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('search combines ebook and audiobook providers', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'www.googleapis.com') {
        return http.Response(jsonEncode({'items': [
          {'volumeInfo': {'title': 'Dune', 'authors': ['Frank Herbert'], 'publishedDate': '1965', 'previewLink': 'https://books.google.test/dune', 'imageLinks': {'thumbnail': 'http://covers.test/dune.jpg'}}}
        ]}), 200);
      }
      if (request.url.host == 'openlibrary.org') {
        return http.Response(jsonEncode({'docs': [
          {'key': '/works/OL1W', 'title': 'Dune', 'author_name': ['Frank Herbert'], 'first_publish_year': 1965, 'cover_i': 12}
        ]}), 200);
      }
      if (request.url.host == 'gutendex.com') return http.Response(jsonEncode({'results': []}), 200);
      if (request.url.host == 'archive.org') {
        return http.Response(jsonEncode({'response': {'docs': [
          {'identifier': 'dune-audio', 'title': 'Dune audiobook', 'creator': 'Frank Herbert', 'mediatype': 'audio'}
        ]}}), 200);
      }
      if (request.url.host == 'www.loc.gov') return http.Response(jsonEncode({'results': [{'title': 'Dune Library edition', 'contributor': ['Frank Herbert'], 'url': 'https://loc.gov/item/dune', 'date': '1965', 'online_format': ['pdf']}]}), 200);
      if (request.url.host == 'en.wikisource.org') return http.Response(jsonEncode({'query': {'search': []}}), 200);
      if (request.url.host == 'api.openalex.org') return http.Response(jsonEncode({'results': []}), 200);
      if (request.url.host == 'library.oapen.org') return http.Response(jsonEncode({'searchResult': {'searchResults': {'entry': []}}}), 200);
      if (request.url.host == 'api.openaire.eu') return http.Response(jsonEncode({'results': []}), 200);
      if (request.url.host == 'api.crossref.org') return http.Response(jsonEncode({'message': {'items': []}}), 200);
      if (request.url.host == 'www.wikidata.org') return http.Response(jsonEncode({'search': []}), 200);
      if (request.url.host == 'directory.doabooks.org') return http.Response(jsonEncode({'searchResult': {'searchResults': {'entry': []}}}), 200);
      if (request.url.host == 'zenodo.org') return http.Response(jsonEncode({'hits': {'hits': []}}), 200);
      if (request.url.host == 'librivox.org') {
        return http.Response(jsonEncode({'books': [
          {'id': '123', 'title': 'Dune audiobook', 'authors': [{'last_name': 'Herbert'}], 'url_librivox': 'https://librivox.test/dune', 'coverart': 'http://covers.test/audio.jpg'}
        ]}), 200);
      }
      return http.Response('not found', 404);
    });

    final service = SearchService(client: client);
    final response = await service.search('Dune');
    expect(response.completedProviders, 14);
    expect(response.failures, isEmpty);
    expect(response.results.where((r) => r.format == BookFormat.ebook), hasLength(2));
    expect(response.results.where((r) => r.format == BookFormat.audiobook), hasLength(2));
    expect(response.results.any((r) => r.source == 'LibriVox'), isTrue);
    expect(response.results.any((r) => r.source == 'Library of Congress'), isTrue);
    expect(response.results.every((r) => r.coverUrl == null || r.coverUrl!.startsWith('https://')), isTrue);
    client.close();
  });

  test('search reports isolated provider failures without losing other results', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'www.googleapis.com') return http.Response('quota', 429);
      if (request.url.host == 'openlibrary.org') return http.Response(jsonEncode({'docs': []}), 200);
      if (request.url.host == 'gutendex.com') return http.Response(jsonEncode({'results': []}), 200);
      if (request.url.host == 'archive.org') return http.Response(jsonEncode({'response': {'docs': []}}), 200);
      if (request.url.host == 'librivox.org') return http.Response(jsonEncode({'books': []}), 200);
      if (request.url.host == 'www.loc.gov') return http.Response(jsonEncode({'results': []}), 200);
      if (request.url.host == 'en.wikisource.org') return http.Response(jsonEncode({'query': {'search': []}}), 200);
      if (request.url.host == 'api.openalex.org') return http.Response(jsonEncode({'results': []}), 200);
      if (request.url.host == 'library.oapen.org') return http.Response(jsonEncode({'searchResult': {'searchResults': {'entry': []}}}), 200);
      if (request.url.host == 'api.openaire.eu') return http.Response(jsonEncode({'results': []}), 200);
      if (request.url.host == 'api.crossref.org') return http.Response(jsonEncode({'message': {'items': []}}), 200);
      if (request.url.host == 'www.wikidata.org') return http.Response(jsonEncode({'search': []}), 200);
      if (request.url.host == 'directory.doabooks.org') return http.Response(jsonEncode({'searchResult': {'searchResults': {'entry': []}}}), 200);
      if (request.url.host == 'zenodo.org') return http.Response(jsonEncode({'hits': {'hits': []}}), 200);
      return http.Response('', 500);
    });
    final response = await SearchService(client: client).search('test');
    expect(response.failures, hasLength(1));
    expect(response.failures.first.provider, 'Google Books');
    client.close();
  });

  test('mode filter separates ebook and audiobook results', () {
    const ebook = BookResult(title: 'Title', authors: 'Author', source: 'Test', url: 'https://example.com', format: BookFormat.ebook);
    const audio = BookResult(title: 'Title', authors: 'Author', source: 'Test', url: 'https://example.com', format: BookFormat.audiobook);
    expect(ebook.matches(SearchMode.ebooks), isTrue);
    expect(ebook.matches(SearchMode.audiobooks), isFalse);
    expect(audio.matches(SearchMode.audiobooks), isTrue);
    expect(audio.matches(SearchMode.ebooks), isFalse);
  });
}
