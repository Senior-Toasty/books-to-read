// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:bookhunter/changelog_page.dart';
import 'package:bookhunter/search/book_result.dart';
import 'package:bookhunter/search/search_service.dart';
import 'package:bookhunter/library/library_store.dart';
import 'package:bookhunter/downloads/download_store.dart';
import 'package:bookhunter/reader/book_reader_page.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const ReadiculousApp());

class ReadiculousApp extends StatelessWidget {
  const ReadiculousApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Readiculous',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10131A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8C7CFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF191E28),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1B202B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    LibraryStore.load();
    DownloadStore.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String query, {SearchMode mode = SearchMode.all}) {
    if (query.trim().isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchResultsPage(query: query.trim(), initialMode: mode),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _discoverPage(),
            _libraryPage(),
            _downloadsPage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.library_books_outlined), selectedIcon: Icon(Icons.library_books), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
        ],
      ),
    );
  }


  Widget _downloadsPage() {
    return AnimatedBuilder(
      animation: Listenable.merge([DownloadStore.items, DownloadStore.queue]),
      builder: (context, _) {
        final files = DownloadStore.items.value;
        final tasks = DownloadStore.queue.value;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            const Text('Downloads', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Files are saved on this device for offline access.', style: TextStyle(color: Colors.white60)),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Download queue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              for (final task in tasks)
                Card(
                  color: const Color(0xFF191E28),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(task.status == DownloadStatus.failed ? 'Failed: ${task.error ?? 'Unknown error'}' : task.status.name, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      if (task.status == DownloadStatus.downloading) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: task.total > 0 ? task.progress : null),
                        Text(task.total > 0 ? '${(task.progress * 100).toStringAsFixed(0)}%' : 'Downloading…', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      ],
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (task.status == DownloadStatus.failed)
                          TextButton(onPressed: () => DownloadStore.retry(task.id), child: const Text('Retry')),
                        TextButton(onPressed: () => DownloadStore.removeTask(task.id), child: const Text('Remove')),
                      ]),
                    ]),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            Text('Downloaded files · ${files.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (files.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('Your downloaded books and audiobooks will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))),
              ),
            for (final file in files)
              Card(
                color: const Color(0xFF191E28),
                child: ListTile(
                  leading: Icon(file.isAudio ? Icons.headphones : Icons.menu_book, color: const Color(0xFFB5A9FF)),
                  title: Text(file.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${file.source} · ${(file.bytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
                  onTap: () => _openDownloaded(file),
                  trailing: IconButton(
                    tooltip: 'Delete download',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => DownloadStore.remove(file),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openDownloaded(DownloadedBook book) async {
    final extension = book.extension;
    if (const {'epub', 'pdf', 'txt'}.contains(extension)) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookReaderPage(path: book.path, title: book.title),
      ));
    } else {
      await OpenFilex.open(book.path);
    }
  }

  Widget _libraryPage() {
    return AnimatedBuilder(
      animation: Listenable.merge([LibraryStore.items, DownloadStore.items]),
      builder: (context, _) {
        final books = LibraryStore.items.value;
        final downloads = DownloadStore.items.value;
        if (books.isEmpty && downloads.isEmpty) {
          return _placeholderPage(Icons.library_books_rounded, 'Your library',
              'Save a title or download a book. Downloaded files stay here on this device.');
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            const Text('Your library', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text('${books.length + downloads.length} items · ${downloads.length} downloaded', style: const TextStyle(color: Colors.white60)),
            if (downloads.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Available offline', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              for (final file in downloads)
                Card(
                  color: const Color(0xFF191E28),
                  child: ListTile(
                    leading: Icon(file.isAudio ? Icons.headphones : Icons.menu_book, color: const Color(0xFFB5A9FF)),
                    title: Text(file.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${file.source} · Downloaded'),
                    onTap: () => _openDownloaded(file),
                    trailing: IconButton(
                      tooltip: 'Delete download',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => DownloadStore.remove(file),
                    ),
                  ),
                ),
            ],
            if (books.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Saved titles', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              for (final book in books)
                Card(
                  color: const Color(0xFF191E28),
                  child: ListTile(
                    leading: const Icon(Icons.bookmark, color: Color(0xFFB5A9FF)),
                    title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${book.authors.isEmpty ? book.source : book.authors} · ${book.source}', maxLines: 2),
                    trailing: IconButton(
                      tooltip: 'Remove from library',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => LibraryStore.remove(book),
                    ),
                    onTap: () async {
                      final uri = Uri.tryParse(book.url);
                      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _discoverPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset('assets/readiculous_icon.png', width: 104, height: 104, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.auto_stories_rounded, size: 72, color: Color(0xFFB5A9FF))),
            const SizedBox(height: 10),
            const Text('READICULOUS', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB5A9FF))),
            const Text('Find your next obsession', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'What’s new',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangelogPage())),
                icon: const Icon(Icons.new_releases_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text('A universe of books.', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Books, audiobooks, and stories worth getting lost in.', style: TextStyle(color: Colors.white.withValues(alpha: .65))),
        const SizedBox(height: 22),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Search title, author, or ISBN',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(tooltip: 'Search', onPressed: () => _search(_searchController.text), icon: const Icon(Icons.arrow_forward_rounded)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _formatCard(icon: Icons.menu_book_rounded, title: 'Ebooks', subtitle: 'Discover & read', tint: const Color(0xFF8C7CFF), onTap: () => _search(_searchController.text, mode: SearchMode.ebooks))),
            const SizedBox(width: 12),
            Expanded(child: _formatCard(icon: Icons.headphones_rounded, title: 'Audiobooks', subtitle: 'Find & listen', tint: const Color(0xFF54C6B3), onTap: () => _search(_searchController.text, mode: SearchMode.audiobooks))),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionHeading(title: 'Search is online', subtitle: 'Stage 2'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF191E28), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .06))),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.travel_explore_rounded, size: 26, color: Color(0xFFB5A9FF)),
              SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Search fourteen catalogues at once', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 5),
                Text('Google Books, Open Library, Gutenberg, Internet Archive, and LibriVox. Results are gathered in parallel.', style: TextStyle(color: Colors.white60, height: 1.4)),
              ])),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const _SectionHeading(title: 'Built for your shelves', subtitle: 'Coming next'),
        const SizedBox(height: 12),
        _featureRow(Icons.download_for_offline_rounded, 'Offline downloads', 'Keep books available without internet.'),
        _featureRow(Icons.bookmark_add_rounded, 'Reading progress', 'Pick up exactly where you left off.'),
        _featureRow(Icons.queue_music_rounded, 'Audiobook controls', 'Chapters, speed controls, and sleep timer.'),
      ],
    );
  }

  Widget _formatCard({required IconData icon, required String title, required String subtitle, required Color tint, required VoidCallback onTap}) {
    return Material(
      color: tint.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 118,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: tint.withValues(alpha: .22))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: tint, size: 24),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: Colors.white70)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _placeholderPage(IconData icon, String title, String description) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 56, color: const Color(0xFFB5A9FF)),
        const SizedBox(height: 18),
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(description, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
      ]),
    ));
  }
}

class SearchResultsPage extends StatefulWidget {
  const SearchResultsPage({super.key, required this.query, this.initialMode = SearchMode.all, this.searchService});

  final String query;
  final SearchMode initialMode;
  final SearchService? searchService;

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  late final SearchService _service = widget.searchService ?? SearchService();
  late SearchMode _mode = widget.initialMode;
  SearchResponse? _response;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.searchService == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await _service.search(widget.query);
      if (!mounted) return;
      setState(() { _response = response; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error; _loading = false; });
    }
  }

  List<BookResult> get _visible => (_response?.results ?? []).where((item) => item.matches(_mode)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Results for “${widget.query}”'), actions: [IconButton(onPressed: _load, tooltip: 'Retry search', icon: const Icon(Icons.refresh))]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SegmentedButton<SearchMode>(
            segments: const [
              ButtonSegment(value: SearchMode.all, label: Text('All'), icon: Icon(Icons.search)),
              ButtonSegment(value: SearchMode.ebooks, label: Text('Ebooks'), icon: Icon(Icons.menu_book)),
              ButtonSegment(value: SearchMode.audiobooks, label: Text('Audio'), icon: Icon(Icons.headphones)),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => setState(() => _mode = selection.first),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_response != null) Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(child: Text('${_visible.length} results · ${_response!.completedProviders} catalogues', style: const TextStyle(color: Colors.white70))),
            if (_response!.failures.isNotEmpty) Text('${_response!.failures.length} unavailable', style: const TextStyle(color: Colors.orangeAccent)),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text('Search failed: $_error', style: const TextStyle(color: Colors.redAccent))),
        if (_response != null && _response!.failures.isNotEmpty) _failureSummary(_response!.failures),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _visible.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: _visible.length,
                    itemBuilder: (context, index) => _resultCard(_visible[index]),
                  )),
      ]),
    );
  }

  Widget _failureSummary(List<ProviderFailure> failures) {
    final dnsFailure = failures.length == 14 &&
        failures.every((failure) => failure.message.toLowerCase().contains('failed host lookup') ||
            failure.message.toLowerCase().contains('socketexception'));
    return Column(children: [
      if (dnsFailure)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orangeAccent.withValues(alpha: .35)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.wifi_off_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Your phone could not resolve catalogue addresses (DNS). Check Wi-Fi or mobile data, airplane mode, VPN or Private DNS, then tap refresh.',
              style: TextStyle(fontSize: 12, height: 1.4),
            )),
          ]),
        ),
      ExpansionTile(
      dense: true,
      title: const Text('Some catalogues could not respond', style: TextStyle(fontSize: 13)),
      children: failures.map((failure) => ListTile(
        dense: true,
        title: Text(failure.provider),
        subtitle: Text(failure.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      )).toList(),
      ),
    ]);
  }

  Widget _emptyState() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_mode == SearchMode.audiobooks ? Icons.headphones : Icons.search_off, size: 50, color: Colors.white38),
        const SizedBox(height: 12),
        const Text('No results found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Try another title or author. Some catalogues may also be temporarily unavailable.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Search again')),
      ]),
    ));
  }

  Widget _resultCard(BookResult item) {
    final isAudio = item.format == BookFormat.audiobook;
    final formatLabel = switch (item.format) { BookFormat.ebook => 'Ebook', BookFormat.audiobook => 'Audiobook', BookFormat.catalogue => 'Catalogue' };
    return Card(
      color: const Color(0xFF191E28),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cover(item.coverUrl, item.format),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (item.authors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.authors, style: const TextStyle(color: Colors.white60, fontSize: 12))),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(formatLabel, isAudio ? const Color(0xFF54C6B3) : item.format == BookFormat.catalogue ? Colors.white54 : const Color(0xFFB5A9FF)),
              _chip(item.source, Colors.white54),
              if (item.year != null && item.year!.isNotEmpty) _chip(item.year!, Colors.white38),
            ]),
            if (item.accessLabel != null && item.accessLabel!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.accessLabel!, style: const TextStyle(fontSize: 11, color: Colors.white54))),
            if (item.description != null && item.description!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 7), child: Text(item.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54))),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (item.downloadUrl != null && item.format != BookFormat.catalogue)
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await DownloadStore.enqueue(item);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download started. It will appear in your Library when complete.')),
                      );
                    } catch (error) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not download this item: $error')),
                      );
                    }
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download'),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('No file', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              IconButton(
                tooltip: 'Save to library',
                onPressed: () async {
                  await LibraryStore.save(item);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved to your library on this device.')),
                  );
                },
                icon: const Icon(Icons.bookmark_add_outlined, color: Color(0xFFB5A9FF)),
              ),
              TextButton.icon(
                onPressed: () => _open(item.url),
                icon: Icon(isAudio ? Icons.headphones : Icons.open_in_new, size: 16),
                label: Text(isAudio ? 'Listen / open' : 'View edition'),
              ),
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _cover(String? url, BookFormat format) {
    final icon = format == BookFormat.audiobook ? Icons.headphones : format == BookFormat.catalogue ? Icons.library_books_outlined : Icons.menu_book;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(width: 74, height: 106, child: url == null
          ? Container(color: const Color(0xFF292E3A), child: Icon(icon, color: Colors.white38, size: 28))
          : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF292E3A), child: Icon(icon, color: Colors.white38, size: 28)))),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(30)),
    child: Text(label, style: TextStyle(fontSize: 10, color: color)),
  );

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This result has an invalid link.')));
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
    Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
  ]);
}
