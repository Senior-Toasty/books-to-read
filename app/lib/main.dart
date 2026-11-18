// ignore_for_file: deprecated_member_use
// Keep the classic Material API while the Flutter SDK's new material_ui migration settles.
import 'package:flutter/material.dart';

void main() => runApp(const BookHunterApp());

class BookHunterApp extends StatelessWidget {
  const BookHunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookHunter',
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
        fontFamily: 'Roboto',
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _discoverPage(),
            _placeholderPage(Icons.library_books_rounded, 'Your library',
                'Books and audiobooks you save will live here.'),
            _placeholderPage(Icons.download_rounded, 'Downloads',
                'Your download queue and offline files will appear here.'),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Discover'),
          NavigationDestination(
              icon: Icon(Icons.library_books_outlined),
              selectedIcon: Icon(Icons.library_books),
              label: 'Library'),
          NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: 'Downloads'),
        ],
      ),
    );
  }

  Widget _discoverPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF8C7CFF).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.auto_stories_rounded,
                  color: Color(0xFFB5A9FF)),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BOOKHUNTER',
                    style: TextStyle(
                        letterSpacing: 2,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB5A9FF))),
                Text('Find your next obsession',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              ],
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Settings',
              onPressed: () {},
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text('A universe of books.',
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Books, audiobooks, and stories worth getting lost in.',
            style: TextStyle(color: Colors.white.withValues(alpha: .65))),
        const SizedBox(height: 22),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {},
          decoration: InputDecoration(
            hintText: 'Search title, author, or ISBN',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Clear search',
              onPressed: _searchController.clear,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _formatCard(
                icon: Icons.menu_book_rounded,
                title: 'Ebooks',
                subtitle: 'Discover & read',
                tint: const Color(0xFF8C7CFF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _formatCard(
                icon: Icons.headphones_rounded,
                title: 'Audiobooks',
                subtitle: 'Listen anywhere',
                tint: const Color(0xFF54C6B3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionHeading(title: 'Your discovery engine', subtitle: 'Coming online in Stage 2'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF191E28),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.travel_explore_rounded,
                  size: 26, color: Color(0xFFB5A9FF)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Search across sources',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(height: 5),
                    Text(
                      'The search engine is being connected. Results from multiple catalogues will appear here.',
                      style: TextStyle(color: Colors.white60, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const _SectionHeading(title: 'Built for your shelves', subtitle: 'All in one place'),
        const SizedBox(height: 12),
        _featureRow(Icons.download_for_offline_rounded, 'Offline downloads',
            'Keep your books available without internet.'),
        _featureRow(Icons.bookmark_add_rounded, 'Reading progress',
            'Pick up exactly where you left off.'),
        _featureRow(Icons.queue_music_rounded, 'Audiobook controls',
            'Chapters, speed controls, and sleep timer.'),
      ],
    );
  }

  Widget _formatCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color tint,
  }) {
    return Container(
      height: 118,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 24),
          const Spacer(),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderPage(IconData icon, String title, String description) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: const Color(0xFFB5A9FF)),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}
