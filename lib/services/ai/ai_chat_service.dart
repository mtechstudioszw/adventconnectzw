import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import 'ai_balance_service.dart';

/// One Advent AI conversation, as listed in the history drawer.
class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.messageCount = 0,
    this.preview,
  });

  final String id;

  /// Server-side rollup: the opening question, trimmed. Never null in
  /// practice, but a conversation created and abandoned before its first
  /// message has nothing to name it.
  final String title;

  final DateTime updatedAt;
  final int messageCount;

  /// Short excerpt of the latest message, maintained by trigger, so the
  /// list row needs no second query per conversation.
  final String? preview;

  factory AiConversation.fromJson(Map<String, dynamic> j) => AiConversation(
        id: j['id'] as String,
        title: (j['title'] as String?)?.trim().isNotEmpty == true
            ? j['title'] as String
            : 'New conversation',
        updatedAt:
            DateTime.tryParse(j['updated_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
        preview: (j['last_preview'] as String?)?.trim(),
      );
}

/// One turn. `pending` is a local-only state — the server never stores a
/// half-written answer, so a message that was streaming when the app died
/// simply is not there on reload rather than being stuck forever.
enum AiMessageStatus { complete, pending, failed }

class AiMessage {
  AiMessage({
    required this.role,
    required this.content,
    this.id,
    this.status = AiMessageStatus.complete,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final String role; // 'user' | 'assistant'
  String content;
  AiMessageStatus status;
  final DateTime createdAt;

  bool get isUser => role == 'user';

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: (j['id'] as num?)?.toInt(),
        role: j['role'] as String? ?? 'assistant',
        content: j['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
      );
}

/// What went wrong, in the app's own vocabulary.
///
/// Mirrors the closed set of codes the edge function returns. Anything
/// unrecognised maps to [unknown] rather than being shown — a raw
/// provider or Postgres string must never reach a member.
enum AiSendError {
  offline,
  unauthenticated,
  tooLong,
  rateLimited,
  outOfCredit,
  freePoolClosed,
  blocked,
  serviceSuspended,
  providerFailed,
  unknown,
}

class AiSendException implements Exception {
  const AiSendException(this.error);
  final AiSendError error;
}

/// Hands the caller a way to stop an answer part-way through.
///
/// # What stopping does and does not do
///
/// It closes the HTTP client, which drops the SSE connection. Whatever
/// had already streamed is kept and returned — a stopped answer is a
/// short answer, not a lost one.
///
/// It does **not** cancel the work on the server, and it must not be
/// mistaken for a refund. The unit was debited before the provider was
/// called (see `advent-ai/index.ts` step 5), the edge function goes on to
/// finish the answer and persist both turns, and reopening the
/// conversation later shows the full text. That is deliberate: refunding
/// a member who read half an answer and stopped it would make "stop" a
/// free-questions button, and the provider has already been paid either
/// way.
class AiSendCancel {
  bool _cancelled = false;
  void Function()? _abort;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _abort?.call();
  }
}

/// Conversations, messages, and the streaming send.
///
/// # Where the security actually lives
///
/// Nowhere in this file. Every call here is either an RLS-protected
/// table read (the member can only ever see their own rows) or a call to
/// the `advent-ai` edge function, which re-derives the caller from the
/// JWT and decides for itself whether they may send. This class cannot
/// grant itself anything, and a modified build of it still cannot.
class AiChatService {
  AiChatService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// How many messages a page holds. Conversations can run long and
  /// loading all of one on open would stall the screen on a slow phone.
  static const int pageSize = 30;

  // ------------------------------------------------------------------
  //  Conversations
  // ------------------------------------------------------------------

  static Future<List<AiConversation>> conversations({int limit = 50}) async {
    final rows = await _db
        .from('ai_conversations')
        .select('id, title, updated_at, message_count, last_preview')
        .eq('archived', false)
        .order('updated_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => AiConversation.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Create an empty conversation and return its id.
  ///
  /// `user_id` is set by the RLS policy's WITH CHECK against auth.uid(),
  /// not passed from here — a client that names an owner is a client
  /// that can name someone else's.
  static Future<String> createConversation() async {
    final row = await _db
        .from('ai_conversations')
        .insert({'user_id': _db.auth.currentUser!.id})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> renameConversation(String id, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    await _db
        .from('ai_conversations')
        .update({'title': clean.substring(0, clean.length.clamp(0, 120))})
        .eq('id', id);
  }

  /// Deletes the conversation and, by cascade, its messages. The ledger
  /// rows survive on purpose — money records outlive the thing they were
  /// spent on, so deleting a chat cannot erase what it cost.
  static Future<void> deleteConversation(String id) async {
    await _db.from('ai_conversations').delete().eq('id', id);
  }

  // ------------------------------------------------------------------
  //  Messages
  // ------------------------------------------------------------------

  /// One page, oldest-last. [before] is the oldest id already held, so
  /// paging back is keyset-based rather than an OFFSET that shifts when
  /// a new message lands.
  static Future<List<AiMessage>> messages(
    String conversationId, {
    int? before,
  }) async {
    var q = _db
        .from('ai_messages')
        .select('id, role, content, created_at')
        .eq('conversation_id', conversationId)
        .eq('status', 'complete');
    if (before != null) q = q.lt('id', before);

    final rows = await q.order('id', ascending: false).limit(pageSize);
    return (rows as List)
        .map((r) => AiMessage.fromJson(Map<String, dynamic>.from(r)))
        .toList()
        .reversed
        .toList();
  }

  // ------------------------------------------------------------------
  //  Send
  // ------------------------------------------------------------------

  /// Send a question and stream the answer.
  ///
  /// [onDelta] fires for each chunk as it arrives. Returns the complete
  /// text. Throws [AiSendException] with a code the UI can turn into
  /// copy — never a raw error.
  ///
  /// The member's own turn is NOT written here. The edge function
  /// persists both turns together once the answer succeeds, so a failed
  /// send leaves no orphaned question in the transcript for the member
  /// to wonder about.
  static Future<String> send({
    required String conversationId,
    required String message,
    required void Function(String delta) onDelta,
    AiSendCancel? cancel,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final session = _db.auth.currentSession;
    if (session == null) throw const AiSendException(AiSendError.unauthenticated);

    final uri = Uri.parse('${SupabaseConfig.url}/functions/v1/advent-ai');
    final req = http.Request('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer ${session.accessToken}',
        'apikey': SupabaseConfig.anonKey,
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'conversation_id': conversationId,
        'message': message,
      });

    final client = http.Client();
    final buffer = StringBuffer();

    // Closing the client is what actually stops the stream; everything
    // else is bookkeeping. Registered before the first await so a cancel
    // that lands while the request is still in flight is not missed.
    cancel?._abort = client.close;
    if (cancel?.isCancelled ?? false) {
      client.close();
      return '';
    }

    try {
      final res = await client.send(req).timeout(timeout);

      // A non-200 is a JSON error body, not a stream.
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw AiSendException(_codeFrom(body, res.statusCode));
      }

      // The jailbreak path answers as plain JSON rather than SSE — it
      // has nothing to stream and paying for a stream frame to deliver
      // one canned sentence would be silly.
      if (res.headers['content-type']?.contains('application/json') ?? false) {
        final body = await res.stream.bytesToString();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final content = decoded['content'] as String? ?? '';
        onDelta(content);
        return content;
      }

      // ---- SSE ------------------------------------------------------
      // Chunk boundaries do not respect frame boundaries, so a partial
      // line is held back rather than parsed. Parsing half a JSON object
      // shows up as randomly dropped words in the answer.
      var pending = '';
      await for (final chunk
          in res.stream.transform(utf8.decoder).timeout(timeout)) {
        if (cancel?.isCancelled ?? false) break;
        pending += chunk;
        final lines = pending.split('\n');
        pending = lines.removeLast();

        for (final line in lines) {
          final t = line.trim();
          if (!t.startsWith('data:')) continue;
          final payload = t.substring(5).trim();
          if (payload.isEmpty) continue;

          Map<String, dynamic> frame;
          try {
            frame = jsonDecode(payload) as Map<String, dynamic>;
          } catch (_) {
            continue; // one bad frame must not kill a good answer
          }

          final err = frame['error'] as String?;
          if (err != null) throw AiSendException(_codeFrom(err, 500));

          final delta = frame['delta'] as String?;
          if (delta != null && delta.isNotEmpty) {
            buffer.write(delta);
            onDelta(delta);
          }

          // The authoritative balance rides back with the final frame,
          // so the composer updates from the server's figure rather than
          // decrementing a local guess.
          final bal = frame['balance'];
          if (bal is Map) {
            AiBalanceService.adopt(
              AiBalance.fromJson(Map<String, dynamic>.from(bal)),
            );
          }
        }
      }

      // A stopped answer is a short answer, not a failure — including the
      // case where nothing had arrived yet. Never throws, so the screen
      // does not have to tell the difference between "it broke" and "I
      // pressed stop".
      if (cancel?.isCancelled ?? false) return buffer.toString();

      if (buffer.isEmpty) throw const AiSendException(AiSendError.providerFailed);
      return buffer.toString();
    } on AiSendException {
      rethrow;
    } on TimeoutException {
      // Same rule: a stop that races the timeout is still a stop.
      if (cancel?.isCancelled ?? false) return buffer.toString();
      throw const AiSendException(AiSendError.providerFailed);
    } catch (_) {
      // Closing the client to cancel surfaces here as a broken
      // connection, because that is exactly what it is. Checked BEFORE
      // the offline story below, or every stop would be reported to the
      // member as "you're offline".
      if (cancel?.isCancelled ?? false) return buffer.toString();

      // Socket, DNS, TLS — the request never landed. Presented as
      // offline because that is what it is from the member's side, and
      // "check your connection" is actionable where "provider failed"
      // is not.
      throw const AiSendException(AiSendError.offline);
    } finally {
      cancel?._abort = null;
      client.close();
    }
  }

  /// Map a server code onto the app's vocabulary. Unrecognised strings
  /// fail to [AiSendError.unknown] rather than leaking through.
  static AiSendError _codeFrom(String body, int status) {
    final b = body.toLowerCase();
    if (b.contains('rate_limited')) return AiSendError.rateLimited;
    if (b.contains('out_of_credit')) return AiSendError.outOfCredit;
    if (b.contains('free_pool_closed')) return AiSendError.freePoolClosed;
    if (b.contains('service_suspended')) return AiSendError.serviceSuspended;
    if (b.contains('provider_failed')) return AiSendError.providerFailed;
    if (b.contains('too_long')) return AiSendError.tooLong;
    if (b.contains('blocked')) return AiSendError.blocked;
    if (b.contains('unauthenticated') || status == 401) {
      return AiSendError.unauthenticated;
    }
    return AiSendError.unknown;
  }
}
