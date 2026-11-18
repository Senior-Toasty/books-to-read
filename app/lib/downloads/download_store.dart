import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/book_result.dart';

enum DownloadStatus { queued, downloading, paused, failed, completed }

class DownloadTask {
  const DownloadTask({required this.id, required this.title, required this.source, required this.url, required this.status, this.received = 0, this.total = 0, this.error});
  final String id, title, source, url;
  final DownloadStatus status;
  final int received, total;
  final String? error;
  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;
  DownloadTask copyWith({DownloadStatus? status, int? received, int? total, String? error, bool clearError = false}) => DownloadTask(id:id,title:title,source:source,url:url,status:status??this.status,received:received??this.received,total:total??this.total,error:clearError?null:error??this.error);
  Map<String,dynamic> toJson()=>{'id':id,'title':title,'source':source,'url':url,'status':status.name,'received':received,'total':total,'error':error};
  factory DownloadTask.fromJson(Map<String,dynamic> j)=>DownloadTask(id:j['id']?.toString()??'',title:j['title']?.toString()??'Untitled',source:j['source']?.toString()??'',url:j['url']?.toString()??'',status:DownloadStatus.values.firstWhere((s)=>s.name==j['status'],orElse:()=>DownloadStatus.queued),received:(j['received'] as num?)?.toInt()??0,total:(j['total'] as num?)?.toInt()??0,error:j['error']?.toString());
}

class DownloadedBook {
  const DownloadedBook({required this.title, required this.source, required this.path, required this.bytes});
  final String title, source, path;
  final int bytes;
  Map<String,dynamic> toJson()=>{'title':title,'source':source,'path':path,'bytes':bytes};
  factory DownloadedBook.fromJson(Map<String,dynamic> j)=>DownloadedBook(title:j['title']?.toString()??'Untitled',source:j['source']?.toString()??'',path:j['path']?.toString()??'',bytes:(j['bytes'] as num?)?.toInt()??0);
}

class DownloadStore {
  DownloadStore._();
  static const _itemsKey='readiculous.downloads.v2', _queueKey='readiculous.download_queue.v1';
  static final ValueNotifier<List<DownloadedBook>> items=ValueNotifier([]);
  static final ValueNotifier<List<DownloadTask>> queue=ValueNotifier([]);
  static bool _loaded=false, _running=false, _paused=false;
  static Completer<void>? _pauseGate;
  static Future<void> load() async {
    if(_loaded)return;
    final p=await SharedPreferences.getInstance();
    try {
      final a=jsonDecode(p.getString(_itemsKey)??'[]');
      if(a is List) items.value=a.whereType<Map>().map((e)=>DownloadedBook.fromJson(Map<String,dynamic>.from(e))).where((b)=>File(b.path).existsSync()).toList();
    } catch (_) { items.value=[]; }
    try {
      final a=jsonDecode(p.getString(_queueKey)??'[]');
      if(a is List) queue.value=a.whereType<Map>().map((e)=>DownloadTask.fromJson(Map<String,dynamic>.from(e))).where((t)=>t.status!=DownloadStatus.completed).map((t)=>t.status==DownloadStatus.downloading?t.copyWith(status:DownloadStatus.queued):t).toList();
    } catch (_) { queue.value=[]; }
    _loaded=true;
    await _persist();
    if(queue.value.any((t)=>t.status==DownloadStatus.queued)) unawaited(resume());
  }

  static Future<void> enqueue(BookResult book) async {
    await load();
    final url=book.downloadUrl;
    if(url==null || book.accessLabel!='Public-domain ebook') throw StateError('This result does not have a verified downloadable public-domain file.');
    _validateUrl(url);
    if(queue.value.any((t)=>t.url==url && t.status!=DownloadStatus.failed)) return;
    final task=DownloadTask(id:'${DateTime.now().microsecondsSinceEpoch}',title:book.title,source:book.source,url:url,status:DownloadStatus.queued);
    queue.value=[...queue.value,task];
    await _persist();
    unawaited(resume());
  }

  static Future<void> download(BookResult book)=>enqueue(book);
  static Future<void> pause() async { _paused=true; _pauseGate=Completer<void>(); queue.value=queue.value.map((t)=>(t.status==DownloadStatus.queued||t.status==DownloadStatus.downloading)?t.copyWith(status:DownloadStatus.paused):t).toList(); await _persist(); }
  static Future<void> resume() async {
    await load();
    _paused=false;
    if(_pauseGate!=null&&!_pauseGate!.isCompleted)_pauseGate!.complete();
    _pauseGate=null;
    queue.value=queue.value.map((t)=>t.status==DownloadStatus.paused?t.copyWith(status:DownloadStatus.queued):t).toList();
    await _persist();
    if(_running)return;
    _running=true;
    try {
      while(!_paused) {
        final index=queue.value.indexWhere((t)=>t.status==DownloadStatus.queued);
        if(index<0)break;
        await _downloadTask(queue.value[index]);
      }
    } finally { _running=false; }
  }
  static Future<void> retry(String id) async {
    queue.value=queue.value.map((t)=>t.id==id?t.copyWith(status:DownloadStatus.queued,received:0,total:0,clearError:true):t).toList();
    await _persist();
    unawaited(resume());
  }
  static Future<void> removeTask(String id) async { queue.value=queue.value.where((t)=>t.id!=id).toList(); await _persist(); }

  static Future<void> _downloadTask(DownloadTask task) async {
    final index=queue.value.indexWhere((t)=>t.id==task.id);
    if(index<0)return;
    _setTask(task.id,task.copyWith(status:DownloadStatus.downloading,received:0,total:0,clearError:true));
    final uri=_validateUrl(task.url);
    final folder=Directory('${(await getApplicationDocumentsDirectory()).path}/downloads');
    await folder.create(recursive:true);
    final ext=uri.path.toLowerCase().endsWith('.pdf')?'.pdf':uri.path.toLowerCase().contains('.epub')?'.epub':'.txt';
    final safe=task.title.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'),'').trim();
    final file=File('${folder.path}/${safe.isEmpty?'book':safe}-${task.id}$ext');
    final client=HttpClient();
    try {
      final req=await client.getUrl(uri).timeout(const Duration(seconds:30));
      req.headers.set(HttpHeaders.userAgentHeader,'Readiculous/0.3');
      final response=await req.close().timeout(const Duration(seconds:60));
      if(response.statusCode<200||response.statusCode>=300)throw HttpException('Source returned HTTP ${response.statusCode}');
      if(response.contentLength>100*1024*1024)throw HttpException('File exceeds 100 MB limit');
      final total=response.contentLength>0?response.contentLength:0;
      final sink=file.openWrite(); var bytes=0;
      try {
        await for(final chunk in response.timeout(const Duration(seconds:60))) {
          if(_paused) { _setTask(task.id,task.copyWith(status:DownloadStatus.paused,received:bytes,total:total)); await _pauseGate?.future; }
          if(_paused) break;
          _setTask(task.id,task.copyWith(status:DownloadStatus.downloading,received:bytes,total:total));
          bytes+=chunk.length;
          if(bytes>100*1024*1024)throw HttpException('File exceeds 100 MB limit');
          sink.add(chunk);
          _setTask(task.id,task.copyWith(status:DownloadStatus.downloading,received:bytes,total:total));
        }
        await sink.flush();
      } finally { await sink.close(); }
      if(_paused) { if(await file.exists())await file.delete(); return; }
      if(bytes==0)throw HttpException('The source returned an empty file');
      items.value=[...items.value,DownloadedBook(title:task.title,source:task.source,path:file.path,bytes:bytes)];
      _setTask(task.id,task.copyWith(status:DownloadStatus.completed,received:bytes,total:bytes));
      await _persist();
    } catch(error) {
      if(await file.exists())await file.delete();
      _setTask(task.id,task.copyWith(status:DownloadStatus.failed,error:error.toString()));
      await _persist();
    } finally { client.close(force:true); }
  }
  static void _setTask(String id,DownloadTask updated) { queue.value=queue.value.map((t)=>t.id==id?updated:t).toList(); }
  static Uri _validateUrl(String raw) {
    final uri=Uri.tryParse(raw);
    const hosts={'www.gutenberg.org','gutenberg.org'};
    if(uri==null||uri.scheme!='https'||!hosts.contains(uri.host.toLowerCase()))throw StateError('Only verified Project Gutenberg HTTPS downloads are currently supported.');
    return uri;
  }
  static Future<void> remove(DownloadedBook book) async {
    final f=File(book.path); if(await f.exists())await f.delete();
    items.value=items.value.where((b)=>b.path!=book.path).toList(); await _persist();
  }
  static Future<void> _persist() async {
    final p=await SharedPreferences.getInstance();
    await p.setString(_itemsKey,jsonEncode(items.value.map((b)=>b.toJson()).toList()));
    await p.setString(_queueKey,jsonEncode(queue.value.map((t)=>t.toJson()).toList()));
  }
}
