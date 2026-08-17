import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';
import 'highlight_text.dart';

/// Sabbath School highlights, following the ACCOUNT.
///
/// Founder decision, 19 Aug 2026. EGW's highlights are device-local and
/// sign-out clears them, which is right for a shared phone; he wanted these
/// to survive a reinstall and appear on a second device, so they live in
/// `public.ss_highlights` (patch_208) behind owner-only RLS.
///
/// ## Three rules this service exists to hold
///
/// **1. The wash appears on the frame the member taps.** Nothing waits on
/// the network, and nothing waits on disk. A highlight is a reading gesture
/// made dozens of times a session; a spinner on it would be absurd, and an
/// `await` before the repaint is the bug that made three other surfaces
/// look dead this same week.
///
/// **2. It works with no connection.** Sabbath School is explicitly an
/// offline-first surface — there is a "download this week" button. A
/// highlight made on a bus must not be lost, so every change is written to
/// a local mirror immediately and queued for the server.
///
/// **3. The server is the truth, eventually.** [load] flushes the queue
/// first, then replaces the mirror with what the account actually holds. So
/// a highlight removed on another device disappears here on the next open,
/// and a highlight made offline survives to reach it.
class SsHighlights {
  SsHighlights._();

  static const _table = 'ss_highlights';

  /// Local mirror of the account's highlights, and the queue of changes
  /// that have not reached it yet.
  ///
  /// Deliberately NOT `pref:`-prefixed. These mirror one account's content,
  /// so `clearUserData()` clearing them on sign-out is exactly right — the
  /// next member on a shared phone must not see the previous one's study,
  /// and their own copy comes back from the server on first open anyway.
  static const _kMirror = 'ss_highlights_v1';
  static const _kPending = 'ss_highlights_pending_v1';

  /// Bumped on every change so open readers repaint.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, Set<String>>? _cache;

  @visibleForTesting
  static void resetForTest() {
    _cache = null;
    revision.value = 0;
  }

  // ---- Local mirror -------------------------------------------------------

  static Map<String, Set<String>> _all() {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = CacheService.readPref(_kMirror);
    final out = <String, Set<String>>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((path, list) {
          out[path] = {for (final e in list as List) e.toString()};
        });
      } catch (_) {
        // A corrupt mirror is not worth losing the reader over; the next
        // `load` replaces it from the server wholesale.
      }
    }
    return _cache = out;
  }

  static void _saveMirror() {
    final encoded = jsonEncode(
      _all().map((path, set) => MapEntry(path, set.toList())),
    );
    unawaited(
      CacheService.writePref(_kMirror, encoded).catchError(
        (Object e) => debugPrint('SsHighlights: mirror write failed: $e'),
      ),
    );
  }

  /// Every passage highlighted in [readPath], newest last.
  static Set<String> forDay(String readPath) =>
      _all()[readPath] ?? const <String>{};

  static bool has(String readPath, String passage) =>
      forDay(readPath).contains(HighlightText.clean(passage));

  /// Ranges of [text] to paint, for one block of a day's HTML.
  static List<({int start, int end})> rangesIn(String text, String readPath) {
    final passages = forDay(readPath);
    if (passages.isEmpty) return const [];
    return HighlightText.rangesIn(text, passages);
  }

  // ---- Toggling -----------------------------------------------------------

  /// Adds or removes [passage], repainting on this frame.
  ///
  /// Returns true when the passage is now highlighted.
  static bool toggle(String readPath, String passage) {
    final clean = HighlightText.clean(passage);
    // A highlight of two characters is noise; of nothing at all is a bug.
    if (clean.length < 3) return false;

    final all = _all();
    final set = all.putIfAbsent(readPath, () => <String>{});
    final added = !set.contains(clean);
    if (added) {
      set.add(clean);
    } else {
      set.remove(clean);
      if (set.isEmpty) all.remove(readPath);
    }

    _saveMirror();
    _queue(readPath, clean, added: added);
    revision.value++;
    unawaited(_flush());
    return added;
  }

  // ---- The pending queue --------------------------------------------------

  static List<Map<String, dynamic>> _pending() {
    final raw = CacheService.readPref(_kPending);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void _writePending(List<Map<String, dynamic>> ops) {
    unawaited(
      CacheService.writePref(_kPending, jsonEncode(ops)).catchError(
        (Object e) => debugPrint('SsHighlights: queue write failed: $e'),
      ),
    );
  }

  static void _queue(String path, String passage, {required bool added}) {
    final ops = _pending()
      // Only the LAST intent for a passage matters. Highlighting and
      // unhighlighting the same sentence five times offline must not send
      // five round trips, and must not risk them landing out of order.
      ..removeWhere((o) => o['path'] == path && o['passage'] == passage)
      ..add({'path': path, 'passage': passage, 'add': added});
    _writePending(ops);
  }

  /// Sends whatever is queued. Silent on failure — it stays queued.
  static Future<void> _flush() async {
    final ops = _pending();
    if (ops.isEmpty) return;

    final client = _client;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;

    final done = <Map<String, dynamic>>[];
    for (final op in ops) {
      try {
        if (op['add'] == true) {
          await client.from(_table).upsert({
            'user_id': uid,
            'read_path': op['path'],
            'passage': op['passage'],
          }, onConflict: 'user_id,read_path,passage');
        } else {
          await client
              .from(_table)
              .delete()
              .eq('user_id', uid)
              .eq('read_path', op['path'] as String)
              .eq('passage', op['passage'] as String);
        }
        done.add(op);
      } catch (e) {
        debugPrint('SsHighlights: sync deferred: $e');
        // Stop at the first failure — the rest are almost certainly going to
        // fail for the same reason, and hammering a dead connection with the
        // whole queue is how a reader starts to stutter.
        break;
      }
    }
    if (done.isEmpty) return;
    _writePending(
      _pending()
        ..removeWhere(
          (o) => done.any(
            (d) => d['path'] == o['path'] && d['passage'] == o['passage'],
          ),
        ),
    );
  }

  // ---- Reconciling with the account ---------------------------------------

  /// Pulls this day's highlights from the account.
  ///
  /// Flushes anything queued first, so a highlight made offline is not
  /// erased by the very fetch that was meant to restore it. Failure is
  /// silent: the mirror is already on screen and is a perfectly good answer.
  static Future<void> load(String readPath) async {
    await _flush();

    final client = _client;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;

    try {
      final rows = await client
          .from(_table)
          .select('passage')
          .eq('user_id', uid)
          .eq('read_path', readPath);

      final server = {
        for (final r in rows as List) (r as Map)['passage'].toString(),
      };

      // Anything still queued is a local intent the server has not seen, so
      // it must survive being overwritten by the server's answer.
      final queued = _pending().where((o) => o['path'] == readPath);
      for (final op in queued) {
        final passage = op['passage'].toString();
        if (op['add'] == true) {
          server.add(passage);
        } else {
          server.remove(passage);
        }
      }

      final all = _all();
      final before = all[readPath];
      if (before != null &&
          before.length == server.length &&
          before.containsAll(server)) {
        return; // Nothing changed; do not repaint the page mid-read.
      }
      if (server.isEmpty) {
        all.remove(readPath);
      } else {
        all[readPath] = server;
      }
      _saveMirror();
      revision.value++;
    } catch (e) {
      debugPrint('SsHighlights: load failed, serving mirror: $e');
    }
  }

  /// Null when Supabase has not been initialised — which is every widget
  /// test. `Supabase.instance` THROWS rather than returning null, and that
  /// throw has taken down screens under test before.
  static SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
