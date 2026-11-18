import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'book_result.dart';

typedef _ProviderSearch = Future<List<BookResult>> Function(String query);

class SearchResponse {
  const SearchResponse({
    required this.results,
    required this.failures,
    required this.completedProviders,
  });

  final List<BookResult> results;
  final List<ProviderFailure> failures;
  final int completedProviders;
}

class SearchService {
  SearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 14);

  Future<SearchResponse> search(String rawQuery, {SearchMode mode = SearchMode.all}) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const SearchResponse(results: [], failures: [], completedProviders: 0);

    final providers = <(String, _ProviderSearch)>[
      ('Google Books', _googleBooks),
      ('Open Library', _openLibrary),
      ('Project Gutenberg', _gutenberg),
      ('Internet Archive', _internetArchive),
      ('LibriVox', _librivox),
    ];

    final settled = await Future.wait(providers.map((provider) async {
      try {
        return (provider.$1, await provider.$2(query), null as String?);
      } catch (error) {
        return (provider.$1, <BookResult>[], error.toString());
      }
    }));

    final results = <BookResult>[];
    final failures = <ProviderFailure>[];
    final seen = <String>{};
    for (final outcome in settled) {
      if (outcome.$3 != null) {
        failures.add(ProviderFailure(outcome.$1, _cleanError(outcome.$3!)));
      }
      for (final result in outcome.$2.where((item) => item.matches(mode))) {
        if (seen.add(result.dedupeKey)) results.add(result);
      }
    }
    results.sort((a, b) {
      final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return title != 0 ? title : a.source.compareTo(b.source);
    });
    return SearchResponse(results: results, failures: failures, completedProviders: providers.length);
  }

  String _cleanError(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.length > 180 ? '${cleaned.substring(0, 177)}...' : cleaned;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: const {'Accept': 'application/json'}).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Unexpected JSON response');
    return decoded;
  }

  Future<List<BookResult>> _googleBooks(String query) async {
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {'q': query, 'maxResults': '20', 'printType': 'books'});
    final data = await _getJson(uri);
    final items = data['items'];
    if (items is! List) return [];
    return items.map((raw) {
      if (raw is! Map) return null;
      final info = raw['volumeInfo'] is Map ? raw['volumeInfo'] as Map : const {};
      final access = raw['accessInfo'] is Map ? raw['accessInfo'] as Map : const {};
      final authors = _join(info['authors']);
      final cover = info['imageLinks'] is Map ? (info['imageLinks'] as Map)['thumbnail']?.toString() : null;
      final preview = info['previewLink']?.toString() ?? info['infoLink']?.toString();
      if (preview == null || preview.isEmpty) return null;
      return BookResult(
        title: _text(info['title'], 'Untitled'),
        authors: authors,
        source: 'Google Books',
        url: preview,
        format: BookFormat.ebook,
        year: _text(info['publishedDate'], ''),
        coverUrl: _https(cover),
        description: _text(info['description'], ''),
        accessLabel: _googleAccess(access),
      );
    }).whereType<BookResult>().toList();
  }

  String _googleAccess(Map access) {
    final status = access['accessViewStatus']?.toString();
    if (status == 'FULL_PUBLIC_DOMAIN' || status == 'FULL_OPEN_ACCESS') return 'Full access reported';
    if (status == 'PARTIAL') return 'Preview only';
    if (access['epub'] is Map && (access['epub'] as Map)['isAvailable'] == true) return 'EPUB availability reported';
    if (access['pdf'] is Map && (access['pdf'] as Map)['isAvailable'] == true) return 'PDF availability reported';
    return 'Access not verified';
  }

  Future<List<BookResult>> _openLibrary(String query) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {'q': query, 'limit': '20'});
    final data = await _getJson(uri);
    final docs = data['docs'];
    if (docs is! List) return [];
    return docs.map((raw) {
      if (raw is! Map) return null;
      final key = raw['key']?.toString();
      if (key == null || !key.startsWith('/works/')) return null;
      final coverId = raw['cover_i'];
      return BookResult(
        title: _text(raw['title'], 'Untitled'),
        authors: _join(raw['author_name']),
        source: 'Open Library',
        url: 'https://openlibrary.org$key',
        format: BookFormat.ebook,
        year: _text(raw['first_publish_year'], ''),
        coverUrl: coverId == null ? null : 'https://covers.openlibrary.org/b/id/${coverId}-M.jpg',
        accessLabel: _text(raw['ebook_access'], 'Catalogue record'),
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _gutenberg(String query) async {
    final uri = Uri.https('gutendex.com', '/books', {'search': query, 'page': '1'});
    final data = await _getJson(uri);
    final books = data['results'];
    if (books is! List) return [];
    return books.map((raw) {
      if (raw is! Map) return null;
      final formats = raw['formats'] is Map ? raw['formats'] as Map : const {};
      final url = formats['text/html']?.toString() ??
          formats['application/epub+zip']?.toString() ??
          formats['application/pdf']?.toString();
      if (url == null || url.isEmpty) return null;
      final authors = raw['authors'] is List
          ? (raw['authors'] as List).map((author) => author is Map ? author['name']?.toString() ?? '' : '').where((name) => name.isNotEmpty).join(', ')
          : '';
      final cover = formats['image/jpeg']?.toString();
      return BookResult(
        title: _text(raw['title'], 'Untitled'),
        authors: authors,
        source: 'Project Gutenberg',
        url: url,
        format: BookFormat.ebook,
        coverUrl: _https(cover),
        accessLabel: 'Public-domain ebook',
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _internetArchive(String query) async {
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': 'title:${_escapeSearch(query)} AND mediatype:(texts OR audio)',
      'fl[]': 'identifier,title,creator,date,mediatype,description',
      'fl[1]': 'identifier',
      'fl[2]': 'title',
      'fl[3]': 'creator',
      'fl[4]': 'date',
      'fl[5]': 'mediatype',
      'rows': '25',
      'page': '1',
      'output': 'json',
    });
    final data = await _getJson(uri);
    final docs = data['response'] is Map ? (data['response'] as Map)['docs'] : null;
    if (docs is! List) return [];
    return docs.map((raw) {
      if (raw is! Map) return null;
      final identifier = raw['identifier']?.toString();
      if (identifier == null || identifier.isEmpty) return null;
      final media = raw['mediatype']?.toString().toLowerCase();
      final audio = media == 'audio';
      return BookResult(
        title: _text(raw['title'], 'Untitled'),
        authors: _join(raw['creator']),
        source: 'Internet Archive',
        url: 'https://archive.org/details/$identifier',
        format: audio ? BookFormat.audiobook : BookFormat.ebook,
        year: _text(raw['date'], ''),
        coverUrl: 'https://archive.org/services/img/$identifier',
        description: _text(raw['description'], ''),
        accessLabel: audio ? 'Audio catalogue record' : 'Text catalogue record',
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _librivox(String query) async {
    final uri = Uri.https('librivox.org', '/api/feed/audiobooks/', {
      'format': 'json',
      'search': query,
      'limit': '20',
    });
    final data = await _getJson(uri);
    final books = data['books'];
    if (books is! List) return [];
    return books.map((raw) {
      if (raw is! Map) return null;
      final id = raw['id']?.toString();
      final page = raw['url_librivox']?.toString() ?? (id == null ? '' : 'https://librivox.org/$id');
      if (page.isEmpty) return null;
      final authors = raw['authors'] is List
          ? (raw['authors'] as List).map((author) => author is Map ? author['last_name']?.toString() ?? '' : '').where((name) => name.isNotEmpty).join(', ')
          : '';
      return BookResult(
        title: _text(raw['title'], 'Untitled audiobook'),
        authors: authors,
        source: 'LibriVox',
        url: page,
        format: BookFormat.audiobook,
        coverUrl: _https(raw['coverart']?.toString()),
        description: _text(raw['description'], ''),
        accessLabel: 'Free public-domain audiobook',
      );
    }).whereType<BookResult>().toList();
  }

  String _escapeSearch(String input) => input.replaceAll('"', '').replaceAll(RegExp(r'[^\w\s-]'), ' ').trim();
  String _text(dynamic value, String fallback) => value == null || value.toString().trim().isEmpty ? fallback : value.toString().trim();
  String _join(dynamic value) => value is List ? value.map((v) => v.toString()).where((s) => s.trim().isNotEmpty).join(', ') : _text(value, '');
  String? _https(String? value) => value == null ? null : value.replaceFirst('http://', 'https://');
}
