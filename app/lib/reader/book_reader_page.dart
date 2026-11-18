import 'dart:io';

import 'package:epub_view/epub_view.dart' hide DefaultBuilderOptions;
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class BookReaderPage extends StatefulWidget {
  const BookReaderPage({super.key, required this.path, required this.title, this.author = ''});
  final String path;
  final String title;
  final String author;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  PdfControllerPinch? _pdfController;
  EpubController? _epubController;
  late final String _extension;
  bool _epubLoaded = false;
  String? _readerError;

  @override
  void initState() {
    super.initState();
    _extension = widget.path.toLowerCase().split('.').last;
    if (_extension == 'pdf') {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.path),
      );
    } else if (_extension == 'epub') {
      _epubController = EpubController(
        document: EpubDocument.openFile(File(widget.path)),
      );
    } else if (_extension != 'txt') {
      _readerError = 'This downloaded file is a .$_extension file, not a readable ebook. '
          'The app will not pretend that an archive or audio file is a book.';
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _epubController?.dispose();
    super.dispose();
  }

  Widget _errorPanel(Object error) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_outlined, size: 48, color: Color(0xFFB5A9FF)),
              const SizedBox(height: 14),
              const Text('This book could not be opened',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(error.toString(),
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              const Text('The file is saved in your Library. You can remove it and download another available format.',
                  style: TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = widget.author.trim().isEmpty
        ? widget.title
        : '${widget.title} · ${widget.author}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _readerError != null
          ? _errorPanel(_readerError!)
          : switch (_extension) {
              'pdf' => PdfViewPinch(
                  controller: _pdfController!,
                  onDocumentError: (error) {
                    if (mounted) setState(() => _readerError = error.toString());
                  },
                  builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    documentLoaderBuilder: (_) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    pageLoaderBuilder: (_) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorBuilder: (_, error) => _errorPanel(error),
                  ),
                ),
              'epub' => Stack(
                  children: [
                    EpubView(
                      controller: _epubController!,
                      onDocumentLoaded: (_) {
                        if (mounted) setState(() => _epubLoaded = true);
                      },
                      onDocumentError: (error) {
                        if (mounted) {
                          setState(() => _readerError =
                              error?.toString() ?? 'The EPUB file could not be parsed.');
                        }
                      },
                    ),
                    if (!_epubLoaded)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0xFF10131A),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              'txt' => FutureBuilder<String>(
                  future: File(widget.path).readAsString(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return _errorPanel(snapshot.error!);
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.data!.trim().isEmpty) {
                      return _errorPanel('This text file is empty.');
                    }
                    return SelectionArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Text(snapshot.data!,
                            style: const TextStyle(fontSize: 17, height: 1.7)),
                      ),
                    );
                  },
                ),
              _ => _errorPanel('Unsupported file extension: $_extension'),
            },
    );
  }
}
