import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/hymn_model.dart';
import '../../services/bible_service.dart';
import '../../services/library_launch_intent.dart';
import 'bible_tab.dart' show BibleReaderScreen;
import 'hymnal_tab.dart' show HymnReaderScreen;

/// The ways the Library home, search, Saved and the beliefs open a thing
/// in its section — one place, so they all land the same way.
///
/// Readers go on the ROOT navigator: callers may live inside a tab, and a
/// reader on the tab's navigator would keep the floating island over it.
class LibraryOpen {
  LibraryOpen._();

  /// [chapter] and [verse] are 0-based, like the reader.
  static Future<void> verse(
    BuildContext context,
    BibleBook book,
    int chapter, {
    int? verse,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BibleReaderScreen(
          book: book,
          chapter: chapter,
          scrollToVerse: verse,
        ),
      ),
    );
  }

  /// "John 3:16" → the reader at that verse. False if it doesn't resolve.
  static Future<bool> reference(BuildContext context, String raw) async {
    final ref = await BibleService.resolveReference(raw);
    if (ref == null || !context.mounted) return false;
    // A reference counts from 1; the reader from 0.
    await verse(
      context,
      ref.book,
      ref.chapter - 1,
      verse: ref.verse == null ? null : ref.verse! - 1,
    );
    return true;
  }

  static Future<void> hymn(BuildContext context, Hymn hymn) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HymnReaderScreen(hymns: [hymn], initialIndex: 0),
      ),
    );
  }

  /// Opens the EGW book itself, not just the shelf: the EGW tab consumes
  /// [LibraryLaunchIntent.egwItemId] once its shelf loads and makes the
  /// EPUB-or-PDF choice there.
  static Future<Object?> egwBook(BuildContext context, String itemId) {
    LibraryLaunchIntent.egwItemId = itemId;
    return context.pushNamed('library', extra: 3);
  }
}
