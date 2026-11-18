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
  void close() => _client.close();
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
      ('Library of Congress', _loc),
      ('Wikisource', _wikisource),
      ('OpenAlex', _openAlex),
      ('OAPEN', _oapen),
      ('OpenAIRE', _openAire),
      ('Crossref', _crossref),
      ('Wikidata', _wikidata),
      ('DOAB', _doab),
      ('Zenodo', _zenodo),
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
    final response = await _client.get(uri, headers: const {'Accept': 'application/json', 'User-Agent': 'BookHunter/0.1.0 (https://github.com/Senior-Toasty/books-to-read)'}).timeout(_timeout);
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
      final previewLink = _text(info['previewLink'], '');
      final preview = previewLink.isNotEmpty ? previewLink : _text(info['infoLink'], '');
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
        format: _openLibraryFormat(raw['ebook_access']),
        year: _text(raw['first_publish_year'], ''),
        coverUrl: coverId == null ? null : 'https://covers.openlibrary.org/b/id/${coverId}-M.jpg',
        accessLabel: _openLibraryAccess(raw['ebook_access']),
      );
    }).whereType<BookResult>().toList();
  }

  BookFormat _openLibraryFormat(dynamic value) => switch (value?.toString()) {
        'public' || 'borrowable' || 'printdisabled' => BookFormat.ebook,
        _ => BookFormat.catalogue,
      };

  String _openLibraryAccess(dynamic value) => switch (value?.toString()) {
        'public' => 'Public access reported',
        'borrowable' => 'Free borrowing may be available',
        'printdisabled' => 'Accessible lending',
        _ => 'Catalogue record; access not verified',
      };

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


  Future<List<BookResult>> _loc(String query) async {
    final uri = Uri.https('www.loc.gov', '/books/', {'fo': 'json', 'q': query, 'c': '10'});
    final data = await _getJson(uri);
    final items = data['results'];
    if (items is! List) return [];
    return items.map((raw) {
      if (raw is! Map) return null;
      final url = raw['url']?.toString();
      if (url == null || url.isEmpty) return null;
      final online = _join(raw['online_format']).toLowerCase();
      return BookResult(
        title: _text(raw['title'], 'Untitled'),
        authors: _join(raw['contributor']),
        source: 'Library of Congress',
        url: url,
        format: online.contains('pdf') || online.contains('image') ? BookFormat.ebook : BookFormat.catalogue,
        year: _text(raw['date'], ''),
        accessLabel: online.contains('pdf') || online.contains('image') ? 'Digitized item; access terms to check' : 'Catalogue record',
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _wikisource(String query) async {
    final uri = Uri.https('en.wikisource.org', '/w/api.php', {
      'action': 'query', 'list': 'search', 'srsearch': query, 'srnamespace': '0',
      'srlimit': '10', 'format': 'json', 'origin': '*', 'maxlag': '1',
    });
    final data = await _getJson(uri);
    final items = data['query'] is Map ? (data['query'] as Map)['search'] : null;
    if (items is! List) return [];
    return items.map((raw) {
      if (raw is! Map) return null;
      final title = _text(raw['title'], '');
      if (title.isEmpty) return null;
      return BookResult(
        title: title,
        authors: '',
        source: 'Wikisource',
        url: 'https://en.wikisource.org/wiki/${Uri.encodeComponent(title).replaceAll('%2F', '/') }',
        format: BookFormat.ebook,
        accessLabel: 'Free text candidate; check completeness',
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _openAlex(String query) async {
    final uri = Uri.https('api.openalex.org', '/works', {
      'search': query, 'per-page': '10',
      'select': 'id,display_name,publication_year,authorships,open_access,best_oa_location,primary_location',
    });
    final data = await _getJson(uri);
    final items = data['results'];
    if (items is! List) return [];
    return items.map((raw) {
      if (raw is! Map) return null;
      final oa = raw['open_access'] is Map ? (raw['open_access'] as Map)['is_oa'] == true : false;
      if (!oa) return null;
      final authorships = raw['authorships'];
      final authors = authorships is List ? authorships.map((entry) {
        if (entry is! Map) return '';
        final author = entry['author'];
        return author is Map ? _text(author['display_name'], '') : '';
      }).where((name) => name.isNotEmpty).join('; ') : '';
      final best = raw['best_oa_location'] is Map ? raw['best_oa_location'] as Map : const {};
      final primary = raw['primary_location'] is Map ? raw['primary_location'] as Map : const {};
      final url = _text(best['pdf_url'], '') .isNotEmpty
          ? _text(best['pdf_url'], '')
          : _text(best['landing_page_url'], '').isNotEmpty
              ? _text(best['landing_page_url'], '')
              : _text(primary['landing_page_url'], raw['id']?.toString() ?? '');
      if (url.isEmpty) return null;
      return BookResult(
        title: _text(raw['display_name'], 'Untitled'),
        authors: authors,
        source: 'OpenAlex',
        url: url,
        format: BookFormat.catalogue,
        year: _text(raw['publication_year'], ''),
        accessLabel: 'Open-access scholarly record; may not be the requested book',
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _oapen(String query) async {
    final uri = Uri.https('library.oapen.org', '/rest/search', {
      'query': 'dc.title:"${query.replaceAll('"', ' ')}"',
      'expand': 'metadata,bitstreams', 'limit': '10',
    });
    return _repositoryBooks(await _getJson(uri), 'OAPEN', 'https://library.oapen.org');
  }

  Future<List<BookResult>> _doab(String query) async {
    final uri = Uri.https('directory.doabooks.org', '/rest/search', {
      'query': 'dc.title:"${query.replaceAll('"', ' ')}"',
      'expand': 'metadata,bitstreams', 'limit': '10',
    });
    return _repositoryBooks(await _getJson(uri), 'DOAB', 'https://directory.doabooks.org');
  }

  List<BookResult> _repositoryBooks(Map<String, dynamic> data, String source, String base) {
    final items = _repositoryItems(data);
    return items.map((raw) {
      if (raw is! Map) return null;
      final title = _metadataValue(raw, 'dc.title').isNotEmpty
          ? _metadataValue(raw, 'dc.title')
          : _text(raw['name'], '');
      if (title.isEmpty) return null;
      final authors = [
        ..._metadataValues(raw, 'dc.contributor.author'),
        ..._metadataValues(raw, 'dc.contributor.editor'),
      ].join('; ');
      final year = _metadataValue(raw, 'dc.date.issued');
      final license = _metadataValue(raw, 'dc.rights.uri').isNotEmpty
          ? _metadataValue(raw, 'dc.rights.uri')
          : _metadataValue(raw, 'dc.rights');
      final handle = _text(raw['handle'], '');
      final uuid = _text(raw['uuid'], '');
      final landing = handle.isNotEmpty
          ? '$base/handle/$handle'
          : uuid.isNotEmpty ? '$base/items/$uuid' : '$base';
      return BookResult(
        title: title,
        authors: authors,
        source: source,
        url: landing,
        format: BookFormat.ebook,
        year: year,
        accessLabel: license.isNotEmpty ? 'Open-access catalogue; licence listed' : 'Open-access catalogue; verify licence',
        description: license.isEmpty ? null : 'Licence metadata: $license',
      );
    }).whereType<BookResult>().toList();
  }

  List<dynamic> _repositoryItems(Map<String, dynamic> data) {
    final searchResult = data['searchResult'];
    if (searchResult is Map) {
      final results = searchResult['searchResults'];
      if (results is Map && results['entry'] != null) {
        final entry = results['entry'];
        return entry is List ? entry : [entry];
      }
      if (results is List) return results;
    }
    for (final key in ['results', 'items']) {
      if (data[key] is List) return data[key] as List;
    }
    return [];
  }

  String _metadataValue(dynamic node, String wanted) {
    final values = _metadataValues(node, wanted);
    return values.isEmpty ? '' : values.first;
  }

  List<String> _metadataValues(dynamic node, String wanted) {
    final found = <String>[];
    void walk(dynamic value) {
      if (value is Map) {
        if (value['key']?.toString() == wanted && value['value'] != null) {
          walkText(value['value'], found);
        }
        if (value.containsKey(wanted)) walkText(value[wanted], found);
        for (final entry in value.entries) {
          if (entry.key.toString() != wanted && entry.key.toString() != 'value') walk(entry.value);
        }
      } else if (value is List) {
        for (final item in value) walk(item);
      }
    }
    walk(node is Map ? node['metadata'] ?? node : node);
    return found.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
  }

  void walkText(dynamic value, List<String> output) {
    if (value is String || value is num) {
      output.add(value.toString());
    } else if (value is List) {
      for (final item in value) walkText(item, output);
    } else if (value is Map) {
      if (value['value'] != null) walkText(value['value'], output);
      else if (value['name'] != null) walkText(value['name'], output);
    }
  }

  Future<List<BookResult>> _openAire(String query) async {
    final uri = Uri.https('api.openaire.eu', '/graph/v4/research-products', {
      'search': query, 'page': '1', 'page_size': '10',
    });
    final data = await _getJson(uri);
    final items = data['results'];
    if (items is! List) return [];
    return items.map((raw) {
      if (raw is! Map) return null;
      final title = _text(raw['mainTitle'], _text(raw['title'], ''));
      if (title.isEmpty) return null;
      final names = <String>[];
      _collectPeople(raw['authors'] ?? raw['author'], names);
      final instances = raw['instances'] is List ? raw['instances'] as List : const [];
      final first = instances.isNotEmpty && instances.first is Map ? instances.first as Map : const {};
      final id = _text(raw['id'], '');
      final url = _text(first['webUrl'], _text(first['url'], id.startsWith('http') ? id : 'https://explore.openaire.eu/search/publication?pid=${Uri.encodeComponent(id)}'));
      return BookResult(
        title: title,
        authors: names.join('; '),
        source: 'OpenAIRE',
        url: url,
        format: BookFormat.catalogue,
        year: _text(raw['publicationDate'], ''),
        accessLabel: 'Research record; verify book/full-text status',
        description: _text(raw['bestAccessRight'] is Map ? (raw['bestAccessRight'] as Map)['label'] : null, ''),
      );
    }).whereType<BookResult>().toList();
  }

  void _collectPeople(dynamic value, List<String> names) {
    if (value is String && value.trim().isNotEmpty) {
      names.add(value.trim());
    } else if (value is List) {
      for (final item in value) _collectPeople(item, names);
    } else if (value is Map) {
      for (final key in ['fullName', 'displayName', 'name']) {
        final candidate = value[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          names.add(candidate.trim());
          return;
        }
      }
      for (final child in value.values) _collectPeople(child, names);
    }
  }

  Future<List<BookResult>> _crossref(String query) async {
    final uri = Uri.https('api.crossref.org', '/works', {'query.bibliographic': query, 'rows': '20'});
    final data = await _getJson(uri);
    final message = data['message'];
    final items = message is Map ? message['items'] : null;
    if (items is! List) return [];
    const bookTypes = {'book', 'monograph', 'edited-book', 'reference-book', 'book-series', 'book-set', 'book-chapter'};
    return items.map((raw) {
      if (raw is! Map || !bookTypes.contains(raw['type']?.toString())) return null;
      final titles = raw['title'];
      final title = titles is List && titles.isNotEmpty ? _text(titles.first, '') : '';
      if (title.isEmpty) return null;
      final people = raw['author'] is List ? (raw['author'] as List).map((person) {
        if (person is! Map) return '';
        return '${_text(person['given'], '')} ${_text(person['family'], '')}'.trim();
      }).where((name) => name.isNotEmpty).join('; ') : '';
      final published = raw['published'] is Map ? raw['published'] as Map : raw['issued'] is Map ? raw['issued'] as Map : const {};
      final dateParts = published['date-parts'];
      final year = dateParts is List && dateParts.isNotEmpty && dateParts.first is List && (dateParts.first as List).isNotEmpty ? (dateParts.first as List).first.toString() : '';
      final doi = _text(raw['DOI'], '');
      final link = _text(raw['URL'], doi.isEmpty ? '' : 'https://doi.org/$doi');
      if (link.isEmpty) return null;
      return BookResult(
        title: title,
        authors: people,
        source: 'Crossref',
        url: link,
        format: BookFormat.catalogue,
        year: year,
        accessLabel: 'Bibliographic metadata only',
        description: 'Crossref metadata does not establish free full-text access.',
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _wikidata(String query) async {
    final uri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbsearchentities', 'search': query, 'language': 'en', 'format': 'json', 'limit': '10',
    });
    final data = await _getJson(uri);
    final items = data['search'];
    if (items is! List) return [];
    return items.map((raw) {
      if (raw is! Map) return null;
      final id = _text(raw['id'], '');
      final title = _text(raw['label'], '');
      if (id.isEmpty || title.isEmpty) return null;
      return BookResult(
        title: title,
        authors: '',
        source: 'Wikidata',
        url: 'https://www.wikidata.org/wiki/$id',
        format: BookFormat.catalogue,
        accessLabel: 'Bibliographic metadata only',
        description: _text(raw['description'], ''),
      );
    }).whereType<BookResult>().toList();
  }

  Future<List<BookResult>> _zenodo(String query) async {
    final uri = Uri.https('zenodo.org', '/api/records', {'q': 'metadata.title:"$query"', 'size': '10'});
    final data = await _getJson(uri);
    final hits = data['hits'];
    final items = hits is Map ? hits['hits'] : data['results'];
    if (items is! List) return [];
    return items.map((raw) {
      if (raw is! Map) return null;
      final metadata = raw['metadata'] is Map ? raw['metadata'] as Map : raw;
      final creators = metadata['creators'];
      final authors = creators is List ? creators.map((person) => person is Map ? _text(person['name'], '') : '').where((s) => s.isNotEmpty).join('; ') : '';
      final id = _text(raw['id'], '');
      final links = raw['links'] is Map ? raw['links'] as Map : const {};
      final url = _text(links['html'], id.isEmpty ? '' : 'https://zenodo.org/records/$id');
      if (url.isEmpty) return null;
      final license = metadata['license'] is Map ? _text((metadata['license'] as Map)['id'], _text((metadata['license'] as Map)['title'], '')) : '';
      final resource = metadata['resource_type'] is Map ? _text((metadata['resource_type'] as Map)['title'], '') : '';
      return BookResult(
        title: _text(metadata['title'], 'Untitled'),
        authors: authors,
        source: 'Zenodo',
        url: url,
        format: BookFormat.catalogue,
        year: _text(metadata['publication_date'], ''),
        accessLabel: 'Repository record; check file and licence',
        description: [if (resource.isNotEmpty) 'Resource type: $resource', if (license.isNotEmpty) 'Licence: $license'].join(' · '),
      );
    }).whereType<BookResult>().toList();
  }

  String _escapeSearch(String input) => input.replaceAll('"', '').replaceAll(RegExp(r'[^\w\s-]'), ' ').trim();
  String _text(dynamic value, String fallback) => value == null || value.toString().trim().isEmpty ? fallback : value.toString().trim();
  String _join(dynamic value) => value is List ? value.map((v) => v.toString()).where((s) => s.trim().isNotEmpty).join(', ') : _text(value, '');
  String? _https(String? value) => value == null ? null : value.replaceFirst('http://', 'https://');
}
