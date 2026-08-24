import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/call_model.dart';

/// Thin, honest wrapper over the `call_*` RPCs.
///
/// Every method here is one round trip and no logic. That is the point:
/// all the rules — who may call whom, who may join, how many times, for
/// how long — live in patch_261 where the client cannot reach them.
/// Anything in this file that started making a decision would be a
/// decision an attacker gets to make too, because they can call the
/// RPCs directly with the anon key that ships in the APK.
///
/// The RPCs answer with either a call snapshot or
/// `{"error": CODE, "message": TEXT}`. [_unwrap] turns the second into
/// a [CallFailure] so callers can use ordinary try/catch, while the
/// transaction that produced it stays committed — which is what makes
/// "they were busy" still land in both people's history.
class CallApi {
  CallApi._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Long enough for a slow Harare 3G round trip, short enough that a
  /// dead network does not leave someone staring at "Calling…".
  static const _timeout = Duration(seconds: 15);

  static CallSession _unwrap(Object? raw) {
    if (raw is! Map) {
      throw const CallFailure('BAD_RESPONSE', 'Something went wrong.');
    }
    final json = raw.cast<String, dynamic>();
    final error = json['error'];
    if (error != null) {
      throw CallFailure(
        error.toString(),
        (json['message'] ?? 'Something went wrong.').toString(),
      );
    }
    return CallSession.fromJson(json);
  }

  /// Turns the transport's own failures into the same shape as a
  /// server refusal, so no call site has to know the difference
  /// between "the server said no" and "the server did not answer".
  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CallFailure {
      rethrow;
    } on TimeoutException {
      throw const CallFailure(
        'NETWORK',
        'The network is too slow right now. Please try again.',
      );
    } on PostgrestException catch (e) {
      // 42501 is what the write-rate-limit triggers raise (patch_191).
      if (e.code == '42501') {
        throw CallFailure(
          'RATE_LIMITED',
          e.hint ?? 'You have done that a lot in a short time. Please wait.',
        );
      }
      debugPrint('CallApi postgrest error: ${e.code} ${e.message}');
      throw const CallFailure('SERVER', 'Could not reach the call service.');
    } catch (e) {
      debugPrint('CallApi error: $e');
      throw const CallFailure('NETWORK', 'Could not reach the call service.');
    }
  }

  // ---- placing and answering -------------------------------------------

  /// Ring one person.
  ///
  /// [conversationId] is optional and is carried only so call history
  /// can deep-link back into the thread — it grants nothing.
  static Future<CallSession> startDirect({
    required String userId,
    String? conversationId,
  }) {
    return _guard(() async {
      final raw = await _client
          .rpc(
            'call_start',
            params: {
              'p_kind': 'direct',
              'p_target': userId,
              if (conversationId != null)
                'p_conversation': int.tryParse(conversationId),
            },
          )
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  /// Start (or join) the call for a group conversation.
  ///
  /// If a call is already running on this group the server JOINS it
  /// rather than opening a second room — otherwise the group ends up
  /// split across two calls, each half wondering where everyone is.
  /// [inviteUserIds] narrows who gets rung; null rings everyone, capped
  /// server-side at the participant limit.
  static Future<CallSession> startGroup({
    required String conversationId,
    List<String>? inviteUserIds,
  }) {
    return _guard(() async {
      final raw = await _client
          .rpc(
            'call_start',
            params: {
              'p_kind': 'group',
              'p_conversation': int.tryParse(conversationId),
              if (inviteUserIds != null && inviteUserIds.isNotEmpty)
                'p_invitees': inviteUserIds,
            },
          )
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  /// "My phone is actually alerting." Dispatching a push proves
  /// nothing — FCM queues for offline devices — so the caller's screen
  /// only says "Ringing" once this lands.
  static Future<CallSession> ringAck(String callId) {
    return _guard(() async {
      final raw = await _client
          .rpc('call_ring_ack', params: {'p_call': callId})
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  static Future<CallSession> accept(String callId) {
    return _guard(() async {
      final raw = await _client
          .rpc('call_accept', params: {'p_call': callId})
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  static Future<CallSession> reject(String callId) {
    return _guard(() async {
      final raw = await _client
          .rpc('call_reject', params: {'p_call': callId})
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  /// The caller gives up before anyone answers.
  static Future<CallSession> cancel(String callId) {
    return _guard(() async {
      final raw = await _client
          .rpc('call_cancel', params: {'p_call': callId})
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  /// Join a group call already in progress.
  static Future<CallSession> join(String callId) {
    return _guard(() async {
      final raw = await _client
          .rpc('call_join', params: {'p_call': callId})
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  /// Leave WITHOUT ending it for everyone else. In a 1:1 there is no
  /// such thing and the server finalises the call anyway.
  static Future<CallSession> leave(String callId) {
    return _guard(() async {
      final raw = await _client
          .rpc('call_leave', params: {'p_call': callId})
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  /// End it for EVERYONE. The server checks that this member is
  /// allowed to (creator, group admin, or super admin) — the UI hiding
  /// the button is a courtesy, not the control.
  static Future<CallSession> endForAll(String callId, {String? reason}) {
    return _guard(() async {
      final raw = await _client
          .rpc(
            'call_end',
            params: {'p_call': callId, 'p_reason': ?reason},
          )
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  static Future<CallSession> removeParticipant(String callId, String userId) {
    return _guard(() async {
      final raw = await _client
          .rpc(
            'call_remove_participant',
            params: {'p_call': callId, 'p_user': userId},
          )
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  // ---- liveness --------------------------------------------------------

  /// Tell the server this device is still here, and carry the telemetry
  /// that makes relay cost measurable.
  ///
  /// [relayed] is self-reported and the server treats it as telemetry
  /// only — nothing is authorised on it. It exists so a TURN bill can
  /// be attributed rather than guessed at.
  ///
  /// The returned snapshot is how a client learns about everything it
  /// missed while its Realtime socket was down, which makes this the
  /// backstop for the whole signalling layer.
  static Future<CallSession> heartbeat(
    String callId, {
    bool? muted,
    String? network,
    bool? relayed,
  }) {
    return _guard(() async {
      final raw = await _client
          .rpc(
            'call_heartbeat',
            params: {
              'p_call': callId,
              'p_muted': ?muted,
              'p_network': ?network,
              'p_relayed': ?relayed,
            },
          )
          .timeout(_timeout);
      return _unwrap(raw);
    });
  }

  /// What call am I in, according to the SERVER?
  ///
  /// Called on cold start and on every resume. This is what stops a
  /// ghost call surviving a force-quit: the app asks rather than
  /// trusting whatever was in memory, and a call the server has already
  /// swept comes back null.
  static Future<CallSession?> current() async {
    try {
      final raw = await _client.rpc('call_current').timeout(_timeout);
      if (raw is! Map) return null;
      final json = raw.cast<String, dynamic>();
      if (json['error'] != null) return null;
      return CallSession.fromJson(json);
    } catch (e) {
      debugPrint('CallApi.current failed: $e');
      return null;
    }
  }

  // ---- devices ---------------------------------------------------------

  /// Register where to ring this member.
  ///
  /// iOS needs a PushKit VoIP token, which is a DIFFERENT token from
  /// FCM's — Apple only lets a VoIP push through on the `.voip` topic,
  /// which FCM cannot publish to. Android uses the FCM token. Passing
  /// null for either leaves the stored value alone, so a refresh of one
  /// never wipes the other.
  static Future<void> registerDevice({
    String? voipToken,
    String? pushToken,
  }) async {
    if (_client.auth.currentUser == null) return;
    if ((voipToken ?? '').isEmpty && (pushToken ?? '').isEmpty) return;
    try {
      await _client
          .rpc(
            'call_register_device',
            params: {
              'p_platform': Platform.isIOS ? 'ios' : 'android',
              'p_voip_token': ?voipToken,
              'p_push_token': ?pushToken,
            },
          )
          .timeout(_timeout);
    } catch (e) {
      // A device that fails to register still receives in-app calls
      // over Realtime; it just will not ring when the app is killed.
      // Worth a log, never worth an error in someone's face.
      debugPrint('CallApi.registerDevice failed: $e');
    }
  }

  /// Sign-out. Stops this handset ringing for an account that is no
  /// longer on it.
  static Future<void> forgetDevice() async {
    try {
      await _client.rpc('call_forget_device').timeout(_timeout);
    } catch (e) {
      debugPrint('CallApi.forgetDevice failed: $e');
    }
  }

  // ---- history + usage -------------------------------------------------

  static Future<List<CallHistoryEntry>> history({
    int limit = 40,
    DateTime? before,
  }) async {
    try {
      final raw = await _client
          .rpc(
            'call_history',
            params: {
              'p_limit': limit,
              if (before != null) 'p_before': before.toUtc().toIso8601String(),
            },
          )
          .timeout(_timeout);
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((r) => CallHistoryEntry.fromJson(r.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('CallApi.history failed: $e');
      return const [];
    }
  }

  /// Clear MY log. Nobody else's view changes — history is
  /// reconstructed per participant, not read from a shared list.
  static Future<void> clearHistory({String? callId}) async {
    try {
      await _client
          .rpc(
            'call_history_clear',
            params: {'p_call': ?callId},
          )
          .timeout(_timeout);
    } catch (e) {
      debugPrint('CallApi.clearHistory failed: $e');
    }
  }

  static Future<CallUsage> usage() async {
    try {
      final raw = await _client.rpc('call_my_usage').timeout(_timeout);
      if (raw is! Map) return CallUsage.empty;
      return CallUsage.fromJson(raw.cast<String, dynamic>());
    } catch (e) {
      debugPrint('CallApi.usage failed: $e');
      return CallUsage.empty;
    }
  }

  // ---- ICE -------------------------------------------------------------

  /// Short-lived STUN/TURN servers for one call.
  ///
  /// Goes through the `call-ice-servers` Edge Function rather than
  /// shipping credentials in the app, because a credential in the APK
  /// is a permanent one — the APK is public. What comes back expires in
  /// minutes and is scoped to this member and this call.
  ///
  /// On failure this returns STUN only rather than throwing. Most calls
  /// connect without relay, so a TURN provider being down should cost
  /// the difficult calls, not all of them.
  static Future<IceConfig> iceServers(String callId) async {
    try {
      final res = await _client.functions
          .invoke('call-ice-servers', body: {'call_id': callId})
          .timeout(const Duration(seconds: 12));
      final data = res.data;
      if (data is Map && data['ice_servers'] is List) {
        return IceConfig(
          servers: (data['ice_servers'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList(),
          provider: (data['turn'] ?? 'none').toString(),
        );
      }
    } catch (e) {
      debugPrint('CallApi.iceServers failed, falling back to STUN: $e');
    }
    return IceConfig.stunOnly;
  }
}

/// What the media stack needs to find a path between two phones.
class IceConfig {
  const IceConfig({required this.servers, required this.provider});

  /// Raw ICE server maps, in the shape `RTCPeerConnection` expects.
  final List<Map<String, dynamic>> servers;

  /// Which TURN provider answered — 'hmac', 'cloudflare', 'metered',
  /// 'none' or 'error'. A NAME, never a credential; logged into
  /// call diagnostics so "why did that call fail" has an answer.
  final String provider;

  bool get hasTurn => provider != 'none' && provider != 'error';

  /// The no-TURN fallback. Real and usable — STUN alone connects
  /// whenever at least one side is not behind a symmetric NAT — it just
  /// fails on the restrictive mobile networks TURN exists for.
  static const stunOnly = IceConfig(
    servers: [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    provider: 'none',
  );
}
