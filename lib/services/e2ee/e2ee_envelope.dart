import 'package:flutter/foundation.dart';

import 'e2ee_service.dart';

/// The encrypted-message wire format, in one place.
///
/// An encrypted message reuses the existing `messages` row rather than
/// getting a table of its own: `content` carries base64 ciphertext and
/// three columns say how to open it. That keeps every existing feature —
/// replies, forwarding, reactions, receipts, reporting, deletion —
/// working untouched, because they all key off the row, not its body.
///
/// ## The placeholder rule
///
/// Anything that cannot be decrypted renders as [placeholder], never as
/// raw base64 and never as an empty bubble. Three separate cases land
/// here and they must all look the same to the member:
///
///  * a build too old to know this wire version;
///  * a message encrypted to a previous install of the app;
///  * a group message whose sender key has not arrived yet.
///
/// Distinguishing them in the UI would be honest and useless — there is
/// nothing the member can do differently in any of the three.
@immutable
class E2eeEnvelope {
  const E2eeEnvelope._();

  /// What an unreadable message reads as. Matches WhatsApp's wording
  /// closely enough to be familiar without pretending to be it.
  static const String placeholder = 'Waiting for this message';

  /// What gets written to `conversations.last_message` for an encrypted
  /// send.
  ///
  /// `last_message` is denormalised onto a row BOTH participants can
  /// read, and it is the one place the server would otherwise still hold
  /// readable message text — encrypting every message body and then
  /// copying the newest one out in the clear would be self-defeating.
  ///
  /// A sentinel rather than the ciphertext: the inbox never needs to
  /// decrypt this (it has the plaintext locally already, see
  /// [E2eeService.cachedPreview]), so shipping the ciphertext would put
  /// bytes on a row for no reader. Storing nothing at all is stronger
  /// and shorter.
  static const String previewSentinel = '\u{1F512}';

  /// True when a conversation's `last_message` is the sentinel rather
  /// than real text.
  static bool isSentinelPreview(String lastMessage) =>
      lastMessage.trim() == previewSentinel;

  /// What the inbox shows for an encrypted thread it has no local copy
  /// of — a fresh install, or a device that has never opened this chat.
  static const String previewPlaceholder = 'New message';

  /// Whether a raw `messages` row is encrypted.
  static bool isEncrypted(Map<String, dynamic> row) {
    final version = row['e2ee_version'];
    return version is num && version > 0;
  }

  /// Whether this build can open [row]'s wire version.
  ///
  /// A row stamped with a NEWER version than we know is not a corrupt
  /// message and must not be treated as one — it is a member on a later
  /// build, and the only correct response is the placeholder.
  static bool isReadableVersion(Map<String, dynamic> row) {
    final version = row['e2ee_version'];
    return version is num && version.toInt() <= E2eeService.wireVersion;
  }

  /// Decrypts one row's `content` in place, returning a new map.
  ///
  /// Rows that are not encrypted pass through untouched, which is what
  /// keeps every message sent before this feature — and every message
  /// from a member who has not upgraded — readable forever.
  ///
  /// Never throws. A thread with one bad message must still paint.
  static Future<Map<String, dynamic>> decryptRow(
    Map<String, dynamic> row, {
    required String conversationId,
    required bool isGroup,
    required String? myUserId,
  }) async {
    if (!isEncrypted(row)) return row;

    final senderId = row['sender_id']?.toString() ?? '';
    final messageId = row['id']?.toString() ?? '';

    // ALWAYS the local plaintext store first, before anything touches the
    // ratchet. This is not a cache in the "make it faster" sense — the
    // Double Ratchet opens a given message exactly once and throws on the
    // second attempt, and this app reads every message several times
    // (fetch on open, realtime delivery, tick reconcile). Without this,
    // a message would render correctly and then turn into the placeholder
    // moments later. See the note in E2eeStore.
    if (messageId.isNotEmpty) {
      final known = E2eeService.cachedPlaintext(messageId);
      if (known != null) return {...row, 'content': known};
    }

    // Our own outgoing rows. The ratchet cannot decrypt what it
    // encrypted, so if the store above did not have it — a reinstall, or
    // a message sent from another device — it is simply gone for us.
    if (myUserId != null && senderId == myUserId) {
      return {...row, 'content': placeholder, '_e2ee_own': true};
    }

    if (!isReadableVersion(row)) {
      return {...row, 'content': placeholder};
    }

    final deviceRaw = row['sender_device_id'];
    final typeRaw = row['ciphertext_type'];
    if (deviceRaw is! num || typeRaw is! num || senderId.isEmpty) {
      return {...row, 'content': placeholder};
    }

    final plaintext = isGroup
        ? await E2eeService.decryptGroup(
            conversationId: conversationId,
            senderUserId: senderId,
            senderDeviceId: deviceRaw.toInt(),
            ciphertextB64: row['content']?.toString() ?? '',
          )
        : await E2eeService.decryptDirect(
            senderUserId: senderId,
            senderDeviceId: deviceRaw.toInt(),
            ciphertextB64: row['content']?.toString() ?? '',
            type: typeRaw.toInt(),
          );

    // Remember it before returning. If this write is skipped the message
    // opens once and is unreadable on every subsequent read — the exact
    // failure the store above exists to prevent.
    if (plaintext != null && messageId.isNotEmpty) {
      await E2eeService.cachePlaintext(messageId, plaintext);
    }
    return {...row, 'content': plaintext ?? placeholder};
  }

  /// Decrypts a whole page of rows, oldest first.
  ///
  /// Order matters and is not an optimisation: the Double Ratchet
  /// advances per message, so decrypting a thread out of order makes
  /// later messages fail. Callers that fetch newest-first MUST reverse
  /// before calling this.
  static Future<List<Map<String, dynamic>>> decryptRows(
    List<Map<String, dynamic>> rows, {
    required String conversationId,
    required bool isGroup,
    required String? myUserId,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      out.add(
        await decryptRow(
          row,
          conversationId: conversationId,
          isGroup: isGroup,
          myUserId: myUserId,
        ),
      );
    }
    return out;
  }
}
