import 'package:flutter/material.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});
  static const entries = [
    ('0.4.0', 'November 2026', [
      'Download supported ebooks and audiobooks directly inside Readiculous.',
      'Keep downloaded files in your Library for offline access.',
      'Download queue shows progress and errors.',
      'Read ebooks in the built-in reader; open audio files with a compatible player.',
      'Restored a visible app logo using a generated PNG asset.',
    ]),
    ('0.3.0', 'November 2026', [
      'New in-app changelog.',
      'Readiculous branding and refreshed app icon.',
      'Initial offline ebook downloads.',
    ]),
    ('0.2.0', 'November 2026', [
      'Saved library and downloads shelf.',
      'Search across fourteen book and audiobook catalogues.',
      'Improved catalogue error reporting.',
    ]),
    ('0.1.0', 'November 2026', [
      'Initial Readiculous discovery experience.',
    ]),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('What’s new')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Readiculous updates', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('A little record of what has changed.', style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 18),
      for (final entry in entries) Card(
        color: const Color(0xFF191E28),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(entry.$1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), Text(entry.$2, style: const TextStyle(color: Colors.white54, fontSize: 12))]),
          const SizedBox(height: 10),
          for (final change in entry.$3) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  ', style: TextStyle(color: Color(0xFFB5A9FF))), Expanded(child: Text(change, style: const TextStyle(height: 1.4)))])),
        ])),
      ),
    ]),
  );
}
