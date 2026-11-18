import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/book_result.dart';

class DownloadedBook {
  const DownloadedBook({required this.title, required this.source, required this.path, required this.bytes});
  final String title;
  final String source;
  final String path;
  final int bytes;

  Map<String, dynamic> toJson() => {'title': title, 'source': source, 'path': path, 'bytes': bytes};
  factory DownloadedBook.fromJson(Map<String, dynamic> json) => DownloadedBook(
    title: json['title']?.toString() ?? 'Untitled',
    source: json['source']?.toString() ?? '',
    path: json['path']?.toString() ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
  );
}

class DownloadStore {
  DownloadStore._();
  static const _key = 'bookhunter.downloads.v1';
  static final ValueNotifier<List<DownloadedBook>> items = ValueNotifier([]);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          items.value = decoded.whereType<Map>()
            .map((entry) => DownloadedBook.fromJson(Map<String, dynamic>.from(entry)))
            .where((book) => File(book.path).existsSync()).toList();
        }
      } catch (_) {
        items.value = [];
      }
    }
    _loaded = true;
    await _persist();
  }

  static Future<void> download(BookResult book) async {
    await load();
    final rawUrl = book.downloadUrl;
    if (rawUrl == null || book.accessLabel != 'Public-domain ebook') {
      throw StateError('This result does not have a verified downloadable public-domain file.');
    }
    final uri = Uri.tryParse(rawUrl);
    const allowedHosts = {'www.gutenberg.org', 'gutenberg.org'};
    if (uri == null || uri.scheme != 'https' || !allowedHosts.contains(uri.host.toLowerCase())) {
      throw StateError('The download link is not from an approved source.');
    }
    final extension = uri.path.toLowerCase().endsWith('.pdf') ? '.pdf' :
      uri.path.toLowerCase().contains('.epub') ? '.epub' : '.txt';
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/downloads');
    await folder.create(recursive: true);
    final safeTitle = book.title.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '').trim();
    final file = File('${folder.path}/${safeTitle.isEmpty ? 'book' : safeTitle}-${DateTime.now().millisecondsSinceEpoch}$extension');
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'BookHunter/0.2');
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Source returned HTTP ${response.statusCode}');
      }
      if (response.contentLength > 100 * 1024 * 1024) throw HttpException('File exceeds 100 MB limit');
      final sink = file.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 60))) {
          bytes += chunk.length;
          if (bytes > 100 * 1024 * 1024) throw HttpException('File exceeds 100 MB limit');
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (bytes == 0) throw HttpException('The source returned an empty file');
      final saved = DownloadedBook(title: book.title, source: book.source, path: file.path, bytes: bytes);
      items.value = [...items.value, saved];
      await _persist();
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> remove(DownloadedBook book) async {
    final file = File(book.path);
    if (await file.exists()) await file.delete();
    items.value = items.value.where((item) => item.path != book.path).toList();
    await _persist();
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.value.map((book) => book.toJson()).toList()));
  }
}
