import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/story_model.dart';
import '../directory_service.dart';
import 'e2ee_service.dart';
import 'media_crypto.dart';

/// What a story's envelope holds once opened.
@immutable
class StoryEnvelope {
  const StoryEnvelope({this.text, this.caption, this.key});
  final String? text;
  final String? caption;
  final MediaKey? key;

  String encode() => jsonEncode({
    'story': 1,
    'text': ?text,
    'caption': ?caption,
    if (key != null) ...key!.toMeta(),
  });

  static StoryEnvelope? decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['story'] != 1) return null;
      MediaKey? key;
      if (j['k'] != null && j['n'] != null) {
        key = MediaKey.fromMeta({
          MediaCrypto.metaKey: {'k': j['k'], 'n': j['n']},
        });
      }
      return StoryEnvelope(
        text: j['text'] as String?,
        caption: j['caption'] as String?,
        key: key,
      );
    } catch (_) {
      return null;
    }
  }
}

/// End-to-end encrypted stories (patch_300).
///
/// Stories are friends-only, so each one has a known audience when it is
/// posted. The photo is sealed with its own AES key; the key, the text and
/// the caption go in an envelope that is encrypted once per friend's
/// current phone over the same 1:1 Signal session chat uses.
class StoryCrypto {
  const StoryCrypto._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Same switch as chat. Off → stories post exactly as before.
  static bool get shouldEncrypt => E2eeService.isEncryptionOn;

  static String _cacheId(String storyId) => 'story:$storyId';

  /// Remember our own envelope — the ratchet can't reopen what it sealed.
  static Future<void> rememberOwn(String storyId, StoryEnvelope env) =>
      E2eeService.cachePlaintext(_cacheId(storyId), env.encode());

  /// Encrypts [env] for every friend's current phone and stores the wraps.
  /// Friends on builds without keys are skipped (they see "update the
  /// app"). Never throws; returns how many friends got a key.
  static Future<int> distribute(String storyId, StoryEnvelope env) async {
    try {
      final friends = await DirectoryService.fetchFriends();
      final plaintext = env.encode();
      final rows = <Map<String, Object>>[];
      for (final f in friends) {
        final sealed = await E2eeService.encryptForUser(
          userId: f.userId,
          plaintext: plaintext,
        );
        if (sealed == null) continue;
        rows.add({
          'u': f.userId,
          'd': sealed.deviceId,
          's': sealed.payload.senderDeviceId,
          'c': sealed.payload.ciphertext,
          't': sealed.payload.type,
        });
      }
      if (rows.isEmpty) return 0;
      final n = await _client.rpc(
        'story_add_keys',
        params: {'p_story': storyId, 'p_rows': rows},
      );
      return (n as num?)?.toInt() ?? rows.length;
    } catch (e) {
      debugPrint('StoryCrypto.distribute: $e');
      return 0;
    }
  }

  /// Opens every encrypted story in [stories] that this phone can. One
  /// round trip for the wraps; opened envelopes are cached so a story is
  /// decrypted once. Unencrypted stories pass through unchanged.
  static Future<List<Story>> openAll(List<Story> stories) async {
    final encrypted = stories.where((s) => s.isEncrypted).toList();
    if (encrypted.isEmpty) return stories;

    final opened = <String, StoryEnvelope>{};
    final missing = <String>[];
    for (final s in encrypted) {
      final cached = E2eeService.cachedPlaintext(_cacheId(s.id));
      final env = cached == null ? null : StoryEnvelope.decode(cached);
      if (env != null) {
        opened[s.id] = env;
      } else {
        missing.add(s.id);
      }
    }

    final device = E2eeService.deviceId;
    if (missing.isNotEmpty && device != null) {
      try {
        final rows = await _client.rpc(
          'story_keys_for',
          params: {'p_stories': missing, 'p_device': device},
        );
        final byId = {for (final s in encrypted) s.id: s};
        for (final raw in (rows as List? ?? const [])) {
          final r = Map<String, dynamic>.from(raw as Map);
          final id = '${r['story_id']}';
          final story = byId[id];
          if (story == null) continue;
          final plain = await E2eeService.decryptDirect(
            senderUserId: story.authorId,
            senderDeviceId: (r['sender_device'] as num).toInt(),
            ciphertextB64: '${r['ciphertext']}',
            type: (r['ciphertext_type'] as num).toInt(),
          );
          final env = plain == null ? null : StoryEnvelope.decode(plain);
          if (env != null) {
            await E2eeService.cachePlaintext(_cacheId(id), plain!);
            opened[id] = env;
          }
        }
      } catch (e) {
        debugPrint('StoryCrypto.openAll: $e');
      }
    }

    return [
      for (final s in stories)
        if (!s.isEncrypted)
          s
        else if (opened[s.id] != null)
          s.opened(
            textContent: opened[s.id]!.text,
            caption: opened[s.id]!.caption,
            mediaKey: opened[s.id]!.key,
          )
        else
          s.opened(locked: true),
    ];
  }

  static final Map<String, Future<String>> _decrypting = {};

  /// Local path of an encrypted story photo, decrypted once and cached.
  static Future<String> photoPath(Story story) {
    return _decrypting[story.id] ??= _decryptPhoto(story);
  }

  static Future<String> _decryptPhoto(Story story) async {
    final key = story.mediaKey;
    if (key == null) throw StateError('No key for this story.');
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/story_plain');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    final file = File('${cacheDir.path}/${story.id}');
    if (file.existsSync() && file.lengthSync() > 0) return file.path;
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(story.mediaUrl));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('story photo ${resp.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      await file.writeAsBytes(
        MediaCrypto.decrypt(Uint8List.fromList(builder.takeBytes()), key),
        flush: true,
      );
      return file.path;
    } catch (e) {
      _decrypting.remove(story.id);
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Wipe decrypted story photos (sign-out).
  static Future<void> clear() async {
    _decrypting.clear();
    try {
      final dir = await getApplicationSupportDirectory();
      final d = Directory('${dir.path}/story_plain');
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
  }
}
