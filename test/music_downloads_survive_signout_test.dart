import 'dart:convert';
import 'dart:io';

import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/music_download_service.dart';
import 'package:advent_connect_zw/services/music_prefs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Founder, 3 Aug 2026 (#8): *"download-for-offline does not work."*
///
/// It worked. Then a sign-out ate the receipts.
///
/// [CacheService.clearUserData] deletes **every** key that does not start
/// with `pref:`, and it runs on every sign-out. The downloads index was a
/// bare `music_downloads_v1`, so signing out wiped the app's entire memory
/// of what had been downloaded. The audio files themselves stayed on disk —
/// orphaned, invisible and un-deletable through the UI — while the
/// "Downloaded" filter went to zero, every Save button reverted to un-saved,
/// and playback quietly went back to streaming.
///
/// Nothing announced any of this, which is why it reads as "the feature
/// doesn't work" rather than "the feature forgot". Exactly the same trap as
/// the quiz sound settings, from the same direction.
///
/// Downloads are DEVICE-level — the bytes belong to the phone, not to the
/// account — so the fix is the `pref:` prefix, not user-scoping.
void main() {
  late Directory dir;
  late Box<String> box;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('music_downloads_test');
    Hive.init(dir.path);
    box = await Hive.openBox<String>('test_box');
    await CacheService.debugUseBox(box);
  });

  tearDown(() async {
    await CacheService.debugUseBox(null);
    await box.deleteFromDisk();
    await Hive.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // Windows sometimes still holds the file handle; the temp dir is
      // disposable either way.
    }
  });

  test('the downloads index survives a sign-out', () async {
    // Stand in for a completed download. Writing the index directly keeps
    // this a storage test — the HTTP path is not what broke.
    await CacheService.writePref(
      'pref:music_downloads_v1',
      jsonEncode({'track-1': 'track-1.mp3'}),
    );
    expect(MusicDownloadService.isDownloaded('track-1'), isTrue);

    await CacheService.clearUserData();

    expect(
      MusicDownloadService.isDownloaded('track-1'),
      isTrue,
      reason: 'sign-out must not delete the record of downloaded audio',
    );
    expect(MusicDownloadService.downloadedCount, 1);
  });

  test('an index written under the old key is still readable', () async {
    // Anyone updating into this build has their index under the old name.
    await box.put(
      'music_downloads_v1',
      jsonEncode({'track-2': 'track-2.mp3'}),
    );

    expect(
      MusicDownloadService.isDownloaded('track-2'),
      isTrue,
      reason: 'the fix must not orphan downloads people already have',
    );
  });

  test('playback speed is a device setting and survives a sign-out', () async {
    await MusicPrefsService.setSpeed(1.5);
    expect(MusicPrefsService.speed(), 1.5);

    await CacheService.clearUserData();

    expect(MusicPrefsService.speed(), 1.5);
  });

  test('likes and history are personal and are cleared on sign-out', () async {
    // The other half of the decision: these four keys are deliberately NOT
    // prefixed, so a shared phone never hands one member's listening
    // history to the next one. Pinned so a future tidy-up cannot quietly
    // promote them into the surviving namespace.
    await MusicPrefsService.toggleLike('track-3');
    expect(MusicPrefsService.liked(), contains('track-3'));

    await CacheService.clearUserData();

    expect(MusicPrefsService.liked(), isEmpty);
  });
}
