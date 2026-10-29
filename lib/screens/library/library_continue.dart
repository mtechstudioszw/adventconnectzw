import 'package:flutter/material.dart';

import '../../models/hymn_model.dart';
import '../../models/library_item_model.dart';
import '../../services/bible_prefs_service.dart';
import '../../services/bible_service.dart';
import '../../services/hymn_service.dart';
import '../../services/library_service.dart';
import '../../services/sabbath_school_prefs.dart';
import 'bible_tab.dart' show BibleReaderScreen;
import 'egw_tab.dart' show EgwPrefs;
import 'library_open.dart';
import 'hymnal_tab.dart' show HymnPrefs, HymnReaderScreen;
import 'ss_lesson_screen.dart' show SsDayReaderScreen;

/// One "pick up where you left off" entry.
class ContinueEntry {
  const ContinueEntry({
    required this.kind,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.open,
  });

  /// Section name: Bible, Sabbath School, Hymnal, EGW.
  final String kind;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Opens the exact place. Completes when the member comes back.
  final Future<Object?> Function(BuildContext context) open;
}

/// The Continue row shared by the Library home and Home (owner, 29 Oct
/// 2026). Read from the positions each section already keeps — nothing
/// new is stored, so it can never disagree with the section itself.
///
/// Readers are pushed on the ROOT navigator: both callers live inside a
/// tab, and a reader pushed onto the tab's own navigator would keep the
/// floating island over the page.
class LibraryContinue {
  LibraryContinue._();

  /// EGW titles by id, fetched once a session rather than every reload.
  static final Map<String, LibraryItem> _egwBooksCache = {};

  /// Every notifier that means "a position may have moved". The Bible's
  /// last chapter and the hymnal's recents are written without a bump, so
  /// callers also reload when a route they pushed returns.
  static List<Listenable> get changes => [
    BiblePrefsService.revision,
    SabbathSchoolPrefs.revision,
    HymnPrefs.revision,
    EgwPrefs.revision,
  ];

  /// Everything with real progress, in a fixed order: Bible, Sabbath
  /// School, Hymnal, EGW. Empty for a member who has not started anything.
  static Future<List<ContinueEntry>> load() async {
    final items = <ContinueEntry>[];

    final pos = BiblePrefsService.lastPosition();
    if (pos != null) {
      final books = await BibleService.books();
      final (b, c) = pos;
      if (b < books.length && c < books[b].chapterCount) {
        final book = books[b];
        items.add(
          ContinueEntry(
            kind: 'Bible',
            icon: Icons.menu_book_rounded,
            title: '${book.name} ${c + 1}',
            subtitle: 'Chapter ${c + 1} of ${book.chapterCount}',
            open: (ctx) => Navigator.of(ctx, rootNavigator: true).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => BibleReaderScreen(book: book, chapter: c),
              ),
            ),
          ),
        );
      }
    }

    final ss = SabbathSchoolPrefs.lastRead();
    final dayPath = ss?['day_path']?.toString() ?? '';
    if (ss != null && dayPath.isNotEmpty) {
      items.add(
        ContinueEntry(
          kind: 'Sabbath School',
          icon: Icons.school_rounded,
          title: ss['lesson_title']?.toString() ?? 'Your lesson',
          subtitle: ss['day_title']?.toString() ?? '',
          open: (ctx) => Navigator.of(ctx, rootNavigator: true).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => SsDayReaderScreen(
                lang: ss['lang']?.toString() ?? 'en',
                quarterlyId: ss['quarterly_id']?.toString() ?? '',
                quarterlyTitle: ss['quarterly_title']?.toString() ?? '',
                lessonId: ss['lesson_id']?.toString() ?? '',
                lessonTitle: ss['lesson_title']?.toString() ?? '',
                days: const [],
                initialIndex: 0,
                singleDayPath: dayPath,
                singleDayTitle: ss['day_title']?.toString(),
              ),
            ),
          ),
        ),
      );
    }

    final recent = HymnPrefs.recentIds();
    if (recent.isNotEmpty) {
      final hymns = await HymnService.all();
      Hymn? hymn;
      for (final h in hymns) {
        if (h.id == recent.first) {
          hymn = h;
          break;
        }
      }
      if (hymn != null) {
        final h = hymn;
        items.add(
          ContinueEntry(
            kind: 'Hymnal',
            icon: Icons.queue_music_rounded,
            title: h.title,
            subtitle: h.number == null ? 'Last opened' : 'Hymn ${h.number}',
            open: (ctx) => Navigator.of(ctx, rootNavigator: true).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => HymnReaderScreen(hymns: [h], initialIndex: 0),
              ),
            ),
          ),
        );
      }
    }

    final egwId = EgwPrefs.lastOpenedId();
    if (egwId != null) {
      // Fetched once per id, not on every prefs bump: this runs whenever
      // a book is saved or opened anywhere in the app.
      var book = _egwBooksCache[egwId];
      if (book == null) {
        for (final item in await LibraryService.fetchItems('egw_book')) {
          _egwBooksCache[item.id] = item;
        }
        book = _egwBooksCache[egwId];
      }
      if (book != null) {
        items.add(
          ContinueEntry(
            kind: 'EGW',
            icon: Icons.auto_stories_rounded,
            title: book.title,
            subtitle: book.author ?? 'Ellen G. White',
            open: (ctx) => LibraryOpen.egwBook(ctx, egwId),
          ),
        );
      }
    }

    return items;
  }
}
