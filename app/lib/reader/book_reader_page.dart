import 'dart:io';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class BookReaderPage extends StatefulWidget {
  const BookReaderPage({super.key, required this.path, required this.title});
  final String path, title;
  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  PdfControllerPinch? _pdfController;
  EpubController? _epubController;
  late final String _extension;
  @override
  void initState() {
    super.initState();
    _extension = widget.path.toLowerCase().split('.').last;
    if (_extension == 'pdf') {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
    } else if (_extension == 'epub') {
      _epubController = EpubController(document: EpubDocument.openFile(widget.path));
    }
  }
  @override
  void dispose() {
    _pdfController?.dispose();
    _epubController?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: switch (_extension) {
      'pdf' => PdfViewPinch(controller: _pdfController!),
      'epub' => EpubView(
        controller: _epubController!,
        onDocumentError: (error) => debugPrint('EPUB reader error: $error'),
      ),
      'txt' => FutureBuilder<String>(
        future: File(widget.path).readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Could not open this text file: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return SelectionArea(child: SingleChildScrollView(padding: const EdgeInsets.all(22), child: Text(snapshot.data!, style: const TextStyle(fontSize: 17, height: 1.7))));
        },
      ),
      _ => const Center(child: Text('This file format is not supported by the reader.')),
    },
  );
}
