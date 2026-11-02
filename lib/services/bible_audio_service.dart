import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bible_translation.dart';
import '../models/library_item_model.dart';
import 'cache_service.dart';
import 'music_download_service.dart';
import 'music_player_service.dart';

/// One voice for the English audio Bible.
@immutable
class BibleNarrator {
  const BibleNarrator(this.id, this.name);
  final String id;
  final String name;
}

/// English audio Bible (2 Nov 2026).
///
/// Human narration of the Berean Standard Bible — public domain, served
/// by bible.helloao.org with three narrators. It is the only free,
/// licence-clean narrated English Bible available; there is no matching
/// KJV recording, so a KJV reader hears the BSB wording and the player
/// says so.
///
/// Playback and downloads ride on the Music player and its downloader:
/// lock-screen controls, background play and "play the downloaded file if
/// there is one" all come for free. A chapter is ~5–7 MB, so downloads are
/// per chapter or per book, never "the whole Bible" (several GB).
class BibleAudio {
  const BibleAudio._();

  static const narrators = <BibleNarrator>[
    BibleNarrator('hays', 'Barry Hays'),
    BibleNarrator('souer', 'Bob Souer'),
    BibleNarrator('david', 'David'),
  ];

  // Device-level choice (same voice for anyone using this phone).
  static const _kNarrator = 'pref:bible_narrator';

  /// The narrated text. Shown on the player so nobody thinks it is KJV.
  static const narratedTranslation = 'Berean Standard Bible';

  /// Roughly 190 KB of MP3 per verse (measured: John 3, 36 verses, 6.9 MB).
  static const _bytesPerVerse = 190 * 1024;

  /// English translations get the Play button. Shona, Hebrew and Greek have
  /// no narration to offer.
  static bool availableFor(BibleTranslation t) =>
      t.id == BibleTranslations.kjv.id || t.id == BibleTranslations.bsb.id;

  /// True when the narration's words differ from what is on screen.
  static bool wordingDiffers(BibleTranslation t) =>
      t.id != BibleTranslations.bsb.id;

  static BibleNarrator get narrator {
    final id = CacheService.readPref(_kNarrator);
    return narrators.firstWhere(
      (n) => n.id == id,
      orElse: () => narrators.first,
    );
  }

  static Future<void> setNarrator(BibleNarrator n) =>
      CacheService.writePref(_kNarrator, n.id);

  static String url(int bookIndex, int chapter, {BibleNarrator? voice}) {
    final code = BibleTranslations.codeFor(bookIndex) ?? 'GEN';
    final n = (voice ?? narrator).id;
    return 'https://audio.bible.helloao.org/api/BSB/$code/${chapter + 1}'
        '/audio/$n.mp3';
  }

  /// Stable, file-name-safe id: also the downloaded file's name.
  static String trackId(int bookIndex, int chapter, {BibleNarrator? voice}) =>
      'bibleaudio-bsb-$bookIndex-$chapter-${(voice ?? narrator).id}';

  static LibraryItem item(
    int bookIndex,
    int chapter,
    String bookName, {
    BibleNarrator? voice,
  }) {
    final v = voice ?? narrator;
    return LibraryItem(
      id: trackId(bookIndex, chapter, voice: v),
      kind: 'audio_bible',
      title: '$bookName ${chapter + 1}',
      fileUrl: url(bookIndex, chapter, voice: v),
      author: '$narratedTranslation · ${v.name}',
    );
  }

  /// Plays [chapter] and keeps going through the rest of the book, like
  /// an audiobook. Downloaded chapters play from the phone.
  static Future<void> play({
    required int bookIndex,
    required int chapter,
    required String bookName,
    required int chapterCount,
  }) async {
    final items = [
      for (var c = chapter; c < chapterCount; c++) item(bookIndex, c, bookName),
    ];
    await MusicDownloadService.warmPaths(items);
    await MusicPlayerService.instance.setQueueAndPlay(items, 0);
  }

  static bool isDownloaded(int bookIndex, int chapter) =>
      MusicDownloadService.isDownloaded(trackId(bookIndex, chapter));

  static Future<bool> downloadChapter(
    int bookIndex,
    int chapter,
    String bookName,
  ) => MusicDownloadService.download(item(bookIndex, chapter, bookName));

  static Future<void> removeChapter(int bookIndex, int chapter) =>
      MusicDownloadService.remove(trackId(bookIndex, chapter));

  /// How many of a book's chapters are on the phone (current narrator).
  static int downloadedInBook(int bookIndex, int chapterCount) {
    var n = 0;
    for (var c = 0; c < chapterCount; c++) {
      if (isDownloaded(bookIndex, c)) n++;
    }
    return n;
  }

  /// Estimated size in MB for [verses] verses of narration.
  static double estimateMb(int verses) => verses * _bytesPerVerse / 1048576;

  /// Book download in progress: book index → chapters done / total.
  static final ValueNotifier<Map<int, ({int done, int total})>> bookProgress =
      ValueNotifier(const {});

  static final Set<int> _cancelBooks = {};

  /// Downloads every chapter of a book, one at a time (kind to slow
  /// connections). Skips chapters already on the phone. Returns how many
  /// chapters failed.
  static Future<int> downloadBook(
    int bookIndex,
    String bookName,
    int chapterCount,
  ) async {
    _cancelBooks.remove(bookIndex);
    var failed = 0;
    for (var c = 0; c < chapterCount; c++) {
      if (_cancelBooks.contains(bookIndex)) break;
      _setBook(bookIndex, c, chapterCount);
      if (isDownloaded(bookIndex, c)) continue;
      final ok = await downloadChapter(bookIndex, c, bookName);
      if (!ok) failed++;
    }
    _clearBook(bookIndex);
    return failed;
  }

  static void cancelBook(int bookIndex) => _cancelBooks.add(bookIndex);

  static Future<void> removeBook(int bookIndex, int chapterCount) async {
    for (var c = 0; c < chapterCount; c++) {
      await removeChapter(bookIndex, c);
    }
  }

  static void _setBook(int book, int done, int total) {
    bookProgress.value = {
      ...bookProgress.value,
      book: (done: done, total: total),
    };
  }

  static void _clearBook(int book) {
    bookProgress.value = {...bookProgress.value}..remove(book);
  }
}
