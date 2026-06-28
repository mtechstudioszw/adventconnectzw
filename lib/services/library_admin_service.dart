import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hymn_model.dart';
import '../models/library_item_model.dart';
import 'hymn_service.dart';

/// Super-admin writes for the in-app Library (gated server-side by the
/// `is_super_admin()` RLS policies added in patch_133). Powers the admin
/// "Manage Library" screen: curate structured hymns, and upload Music + EGW
/// PDFs into the `library` storage bucket.
class LibraryAdminService {
  LibraryAdminService._();
  static final SupabaseClient _client = Supabase.instance.client;

  // ---- Hymns (structured, searchable) --------------------------------------

  /// Every hymn including unpublished ones, ordered by number then title.
  static Future<List<Hymn>> fetchAllHymns() async {
    final rows = await _client
        .from('hymns')
        .select()
        .order('number', ascending: true, nullsFirst: false)
        .order('title', ascending: true);
    return (rows as List)
        .map((r) => Hymn.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Insert (when [id] is null) or update a hymn. Throws on RLS / network
  /// failure so the UI can surface it.
  static Future<void> saveHymn({
    String? id,
    int? number,
    required String title,
    required String lyrics,
    String language = 'Shona',
    String? category,
    String collection = 'kristu_munzwiyo',
    bool isPublished = true,
  }) async {
    final payload = <String, dynamic>{
      'number': number,
      'title': title.trim(),
      'lyrics': lyrics.trim(),
      'language': language.trim().isEmpty ? 'Shona' : language.trim(),
      'collection': collection,
      'category': (category == null || category.trim().isEmpty)
          ? null
          : category.trim(),
      'is_published': isPublished,
    };
    if (id == null) {
      await _client.from('hymns').insert(payload);
    } else {
      await _client.from('hymns').update(payload).eq('id', id);
    }
    HymnService.invalidate();
  }

  static Future<void> deleteHymn(String id) async {
    await _client.from('hymns').delete().eq('id', id);
    HymnService.invalidate();
  }

  // ---- Library items (Music + EGW books) -----------------------------------

  /// Every item of [kind] including unpublished, newest first.
  static Future<List<LibraryItem>> fetchAllItems(String kind) async {
    final rows = await _client
        .from('library_items')
        .select()
        .eq('kind', kind)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => LibraryItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Open the system file picker for the given [extensions] (e.g. ['pdf'] or
  /// ['mp3','m4a','aac','wav','ogg']). Returns the local path + display name,
  /// or null if cancelled. Upload is deferred to [uploadAndAddItem] so a
  /// cancelled form never leaves an orphan file in storage.
  static Future<({String path, String name})?> pickFile({
    required List<String> extensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) return null;
    return (path: path, name: picked.name);
  }

  /// Pick MANY files at once for a bulk upload (e.g. all the EGW books). Returns
  /// every picked file's path + name; empty if cancelled.
  static Future<List<({String path, String name})>> pickFiles({
    required List<String> extensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: true,
      withReadStream: false,
    );
    if (result == null) return const [];
    return result.files
        .where((f) => f.path != null)
        .map((f) => (path: f.path!, name: f.name))
        .toList();
  }

  /// Upload the picked file into the `library` bucket, then insert the catalog
  /// row pointing at it. One step so the file + row land together (or not at
  /// all). [kind] is 'music' | 'egw_book' | 'hymnal'.
  static Future<void> uploadAndAddItem({
    required String kind,
    required String title,
    required String filePath,
    required String fileName,
    String? author,
    String? language,
    int sortOrder = 0,
    bool isPublished = true,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final ext = _ext(fileName, fallback: kind == 'music' ? 'mp3' : 'pdf');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$kind/$ts.$ext';

    await _client.storage.from('library').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: _mimeFor(ext),
            cacheControl: '3600',
            upsert: false,
          ),
        );
    final fileUrl = _client.storage.from('library').getPublicUrl(storagePath);

    await _client.from('library_items').insert({
      'kind': kind,
      'title': title.trim(),
      'file_url': fileUrl,
      'author': (author == null || author.trim().isEmpty) ? null : author.trim(),
      'language':
          (language == null || language.trim().isEmpty) ? null : language.trim(),
      'sort_order': sortOrder,
      'is_published': isPublished,
    });
  }

  static Future<void> deleteItem(String id) async {
    await _client.from('library_items').delete().eq('id', id);
  }

  // ---- helpers -------------------------------------------------------------

  static String _ext(String filename, {required String fallback}) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1) return fallback;
    final e = filename.substring(dot + 1).toLowerCase();
    return e.isEmpty ? fallback : e;
  }

  static String _mimeFor(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }
}
