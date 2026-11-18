import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookhunter/main.dart';
import 'package:bookhunter/search/search_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('BookHunter home renders discover and format cards', (tester) async {
    await tester.pumpWidget(const BookHunterApp());
    expect(find.text('BOOKHUNTER'), findsOneWidget);
    expect(find.text('Ebooks'), findsOneWidget);
    expect(find.text('Audiobooks'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Search five catalogues at once'), findsOneWidget);
  });

  testWidgets('navigation opens library and downloads placeholders', (tester) async {
    await tester.pumpWidget(const BookHunterApp());
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
