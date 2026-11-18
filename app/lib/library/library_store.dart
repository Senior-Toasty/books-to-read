import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/book_result.dart';

class LibraryStore {
  LibraryStore._();

  static const _storageKey = 'bookhunter.saved_books.v1';
  static final ValueNotifier<List<BookResult>> items =
      ValueNotifier<List<BookResult>>([]);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          items.value = decoded
              .whereType<Map>()
              .map((entry) => BookResult.fromJson(
                    Map<String, dynamic>.from(entry),
                  ))
              .toList();
        }
      } on FormatException {
        items.value = [];
      }
    }
    _loaded = true;
  }

  static Future<void> save(BookResult book) async {
    await load();
    if (items.value.any((saved) => saved.dedupeKey == book.dedupeKey)) return;
    items.value = [...items.value, book];
    await _persist();
  }

  static Future<void> remove(BookResult book) async {
    await load();
    items.value = items.value
        .where((saved) => saved.dedupeKey != book.dedupeKey)
        .toList();
    await _persist();
  }

  static Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(items.value.map((book) => book.toJson()).toList()),
    );
  }
}
