// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookhunter/main.dart';
import 'package:bookhunter/search/search_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('BookHunter home renders discover and format cards', (tester) async {
    await tester.pumpWidget(const ReadiculousApp());
    expect(find.text('READICULOUS'), findsOneWidget);
    expect(find.text('Ebooks'), findsOneWidget);
    expect(find.text('Audiobooks'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
  });

  testWidgets('navigation opens library and downloads placeholders', (tester) async {
    await tester.pumpWidget(const ReadiculousApp());
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Your library'), findsOneWidget);
    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Downloads'), findsWidgets);
  });

  testWidgets('search results screen provides filters', (tester) async {
    final client = MockClient((request) async {
      if (request.url.host == 'www.googleapis.com') return http.Response(jsonEncode({'items': []}), 200);
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
      return http.Response('', 404);
    });
    await tester.pumpWidget(MaterialApp(home: SearchResultsPage(query: 'Dune', searchService: SearchService(client: client))));
    await tester.pumpAndSettle();
    expect(find.text('Results for “Dune”'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Ebooks'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    expect(find.text('No results found'), findsOneWidget);
    client.close();
  });
}
