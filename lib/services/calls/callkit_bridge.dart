import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'call_api.dart';

/// Something the system call UI is telling us the member did.
enum CallKitAction { accept, decline, ended, timeout, toggleMute, callback }

class CallKitEvent {
  const CallKitEvent(this.action, this.callId, {this.muted});
  final CallKitAction action;
  final String callId;
  final bool? muted;
}

/// The bridge to the platform's own call UI.
///
/// ## Why a normal notification is not enough
///
/// The brief's hardest requirement is that an incoming call reaches a
/// phone whose app is closed. A Supabase Realtime subscription cannot
/// do that — there is no process to receive it. A heads-up notification
/// can be dismissed with a swipe, does not show over the lock screen,
/// and on Android 14+ cannot be full-screen at all without being a
/// declared calling app.
///
/// So calls use the mechanisms the platforms provide for calls:
///
///   **iOS — CallKit + PushKit.** An APNs VoIP push wakes the app
///   before it is running and the system draws its native incoming-call
///   screen. This is the ONLY way, and Apple enforces the bargain: an
///   app that receives a VoIP push and fails to report a call is
///   terminated. That is why [reportCancelled] still reports the call
///   before ending it.
///
///   **Android — full-screen intent + a phoneCall foreground service.**
///   A high-priority data-only FCM message wakes the app, and the
///   plugin raises a full-screen notification that shows over the lock
///   screen. The foreground service (declared by the plugin, type
///   `phoneCall|microphone`) is what keeps the microphone working when
///   the app is not in front — without it Android 12+ silently mutes a
///   backgrounded call.
///
/// ## Every call ends twice
///
/// Once in our own state machine, once in the system UI. They are
/// separate ledgers and both have to be closed, or the member is left
/// with a call screen for a call that finished — and on iOS, with an
/// app the system will eventually kill. Every terminal path in
/// [CallService] calls [reportEnded].
class CallKitBridge {
  CallKitBridge._();

  static final _controller = StreamController<CallKitEvent>.broadcast();

  /// Actions taken in the system call UI. [CallService] listens.
  static Stream<CallKitEvent> get events => _controller.stream;

  static StreamSubscription<CallEvent?>? _sub;
  static bool _initialized = false;

  /// Call ids we have shown a system UI for, so [reportEnded] can be
  /// called blindly on every exit path without asking the plugin.
  static final Set<String> _shown = <String>{};

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _sub?.cancel();
    _sub = FlutterCallkitIncoming.onEvent.listen(_onEvent);

    // iOS hands the PushKit token over asynchronously, sometimes after
    // a delay on first launch. Ask once now; the DID_UPDATE event below
    // catches the refresh case.
    if (Platform.isIOS) {
      unawaited(_syncVoipToken());
    }
  }

  static void _onEvent(CallEvent? event) {
    if (event == null) return;
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        _emit(CallKitAction.accept, callKitParams);
        break;
      case CallEventActionCallDecline(:final callKitParams):
        _emit(CallKitAction.decline, callKitParams);
        break;
      case CallEventActionCallEnded(:final callKitParams):
        _emit(CallKitAction.ended, callKitParams);
        break;
      // These three carry only the CallKit UUID, not the full params.
      // That is fine, and is why [_params] sets `id` to our own call id
      // rather than minting a fresh UUID: the plugin's id IS the call
      // id, so an event that hands back nothing else is still
      // addressable. Do not "improve" [_params] to generate its own
      // UUID — these three cases would stop resolving to a call.
      case CallEventActionCallTimeout(:final id):
        _emitId(CallKitAction.timeout, id);
        break;
      case CallEventActionCallCallback(:final id):
        _emitId(CallKitAction.callback, id);
        break;
      case CallEventActionCallToggleMute(:final id, :final isMuted):
        // iOS only — the mute button on the CallKit screen. Without
        // this the system UI and our own screen disagree about whether
        // the microphone is live, which is the worst possible thing for
        // a mute button to do.
        if (id.isNotEmpty) {
          _controller.add(
            CallKitEvent(CallKitAction.toggleMute, id, muted: isMuted),
          );
        }
        break;
      case CallEventActionDidUpdateDevicePushTokenVoip():
        unawaited(_syncVoipToken());
        break;
      default:
        break;
    }
  }

  static void _emit(CallKitAction action, CallKitParams params) =>
      _emitId(action, _callIdOf(params));

  static void _emitId(CallKitAction action, String callId) {
    if (callId.isEmpty) return;
    _controller.add(CallKitEvent(action, callId));
  }

  /// Our own call id, which we stash in `extra` because the plugin's
  /// `id` must be a UUID and is used as the CallKit UUID.
  static String _callIdOf(CallKitParams params) {
    final extra = params.extra;
    final fromExtra = extra?['call_id'];
    if (fromExtra is String && fromExtra.isNotEmpty) return fromExtra;
    return params.id;
  }

  static Future<void> _syncVoipToken() async {
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token != null && token.isNotEmpty) {
        await CallApi.registerDevice(voipToken: token);
      }
    } catch (e) {
      debugPrint('CallKitBridge: VoIP token sync failed: $e');
    }
  }

  /// Register this handset for call pushes.
  ///
  /// Android rings via FCM, iOS via PushKit — two different tokens from
  /// two different services, stored in separate columns, because FCM
  /// cannot deliver a VoIP push at all.
  static Future<void> registerDevice() async {
    try {
      if (Platform.isAndroid) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await CallApi.registerDevice(pushToken: token);
        }
      } else if (Platform.isIOS) {
        await _syncVoipToken();
      }
    } catch (e) {
      debugPrint('CallKitBridge.registerDevice failed: $e');
    }
  }

  /// Ask for the permissions an incoming call needs, at the point the
  /// member first uses calling — never on launch.
  ///
  /// Android 14+ gates `USE_FULL_SCREEN_INTENT` behind a per-app
  /// setting for anything that is not a declared calling app. We are
  /// one, so it is usually granted automatically; when it is not, this
  /// opens the settings page rather than silently degrading to a banner
  /// the member will never see on a locked phone.
  static Future<void> ensurePermissions() async {
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Allow call notifications',
        'rationaleMessagePermission':
            'Adventist Super App needs this to tell you about incoming calls.',
        'postNotificationMessageRequired':
            'Without notification permission you will not see incoming calls '
            'when the app is closed. Please enable it in Settings.',
      });
      if (Platform.isAndroid) {
        final canFullScreen =
            await FlutterCallkitIncoming.canUseFullScreenIntent();
        if (!canFullScreen) {
          await FlutterCallkitIncoming.requestFullIntentPermission();
        }
      }
    } catch (e) {
      debugPrint('CallKitBridge.ensurePermissions failed: $e');
    }
  }

  /// Raise the system incoming-call UI.
  static Future<void> showIncoming({
    required String callId,
    required String callerName,
    String? callerPhoto,
    bool isGroup = false,
  }) async {
    _shown.add(callId);
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(
        _params(
          callId: callId,
          name: callerName,
          photo: callerPhoto,
          isGroup: isGroup,
        ),
      );
    } catch (e) {
      debugPrint('CallKitBridge.showIncoming failed: $e');
    }
  }

  /// Tell the system we are placing a call, so it appears in the phone's
  /// own recents and the audio session is set up the same way an
  /// inbound call sets it up.
  static Future<void> reportOutgoing({
    required String callId,
    required String peerName,
    String? peerPhoto,
    bool isGroup = false,
  }) async {
    _shown.add(callId);
    try {
      await FlutterCallkitIncoming.startCall(
        _params(
          callId: callId,
          name: peerName,
          photo: peerPhoto,
          isGroup: isGroup,
        ),
      );
    } catch (e) {
      debugPrint('CallKitBridge.reportOutgoing failed: $e');
    }
  }

  /// Media is up — start the system's own call timer.
  static Future<void> reportConnected(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (e) {
      debugPrint('CallKitBridge.reportConnected failed: $e');
    }
  }

  /// Close the system's ledger for this call. Idempotent, and safe to
  /// call for a call that was never shown.
  static Future<void> reportEnded(String callId) async {
    if (callId.isEmpty) return;
    _shown.remove(callId);
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      debugPrint('CallKitBridge.reportEnded failed: $e');
    }
  }

  /// The caller gave up while our phone was still ringing.
  ///
  /// Identical to [reportEnded] today, and kept separate because the
  /// iOS rule behind it is easy to break by accident: a VoIP push MUST
  /// result in a reported call. The cancel push is delivered to a
  /// device that has already reported this call, so ending it is
  /// correct — but if this ever becomes "just dismiss the UI without
  /// telling CallKit", iOS will start killing the app.
  static Future<void> reportCancelled(String callId) => reportEnded(callId);

  /// Belt-and-braces teardown for sign-out and cold start: leave no
  /// system call UI pointing at a call this session knows nothing about.
  static Future<void> endAll() async {
    _shown.clear();
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('CallKitBridge.endAll failed: $e');
    }
  }

  /// Call ids the system currently shows a UI for. Used on cold start
  /// to reconcile against the server: anything here that the server
  /// does not know about is a ghost and gets ended.
  static Future<List<String>> activeCallIds() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return calls
          .whereType<CallKitParams>()
          .map(_callIdOf)
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('CallKitBridge.activeCalls failed: $e');
      return const [];
    }
  }

  static CallKitParams _params({
    required String callId,
    required String name,
    String? photo,
    bool isGroup = false,
  }) {
    return CallKitParams(
      // The plugin uses this as the CallKit UUID on iOS, and our call
      // ids ARE UUIDs (patch_260), so it can be passed straight through.
      id: callId,
      nameCaller: name,
      appName: 'Adventist Super App',
      avatar: (photo ?? '').isEmpty ? null : photo,
      // Deliberately not a phone number. Members are identified by
      // account here, and putting a number on the system call screen
      // would disclose one that the app does not otherwise show (§40).
      handle: isGroup ? 'Group call' : 'Adventist Super App',
      // 0 = audio. This app has no video calling, and saying so keeps
      // the system UI from offering a camera button that does nothing.
      type: 0,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      extra: {'call_id': callId, 'is_group': isGroup},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        isShowCallID: false,
        // ================================================================
        //  THE RINGTONE. Without this line an incoming call is SILENT.
        // ================================================================
        //
        // Founder report, 25 Aug 2026: "when user a calls u you see its
        // ringing but dosent make sound". This is why, and it is one
        // missing field rather than anything subtle.
        //
        // `AndroidParams.ringtonePath` has no default in the plugin —
        // omit it and it passes null through to the sound player, which
        // then plays nothing. Everything else worked: the full-screen UI
        // appeared, the buttons worked, the call connected. It just did
        // not make a noise, which for an incoming call is most of the
        // feature.
        //
        // `system_ringtone_default` is a literal the plugin special-cases
        // (CallkitSoundPlayerManager.kt) to mean "whatever this handset
        // rings with". That is the right choice over bundling our own:
        // a member has already chosen a ringtone they will hear and
        // recognise from another room, and it respects Do Not Disturb,
        // silent mode and per-contact overrides for free.
        ringtonePath: 'system_ringtone_default',
        // Shows the full-screen UI over the lock screen — the whole
        // point of a call notification.
        isShowFullLockedScreen: true,
        isImportant: true,
        isFullScreen: true,
        // The two buttons on the full-screen Android UI. These live on
        // AndroidParams, not on CallKitParams — iOS draws CallKit's own
        // Accept/Decline and has no say in their wording.
        textAccept: 'Accept',
        textDecline: 'Decline',
        // Brand navy, so the incoming-call screen belongs to this app
        // rather than looking like a generic dialler.
        backgroundColor: '#0D1B3E',
        actionColor: '#1565C0',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        // Same fix as Android's. CallKit is generally better-behaved
        // about falling back to the system ringtone, but stating it
        // means the two platforms cannot diverge silently.
        ringtonePath: 'system_ringtone_default',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        // Voice calls placed in this app should not land in the phone's
        // system call history — that history is shared with the dialler
        // and would leak who a member called to anyone holding the
        // handset (§40).
        includesCallsInRecents: false,
        // flutter_webrtc owns the audio session (see CallAudio); two
        // things configuring it fight, and the symptom is a call with
        // no audio on the first attempt after launch.
        configureAudioSession: false,
      ),
    );
  }
}

/// Handle a call push that arrived in the FCM background isolate.
///
/// Called from `push_service.dart`'s background handler. Runs in a
/// separate isolate with no Supabase session and no app state, so it
/// does exactly one thing: raise the system call UI (or dismiss it).
/// Everything else — accepting, media, signalling — happens in the main
/// isolate once the member taps Accept and the app is brought up.
///
/// Returns true when the message was a call push and has been handled,
/// so the caller knows to stop.
@pragma('vm:entry-point')
Future<bool> handleCallPushInBackground(RemoteMessage message) async {
  final data = message.data;
  if ('${data['type'] ?? ''}' != 'call') return false;

  final callId = '${data['call_id'] ?? ''}';
  if (callId.isEmpty) return true;

  final action = '${data['action'] ?? 'ring'}';
  try {
    if (action == 'cancel') {
      await FlutterCallkitIncoming.endCall(callId);
      return true;
    }
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitBridge._params(
        callId: callId,
        name: '${data['caller_name'] ?? 'Adventist Super App'}',
        photo: '${data['caller_photo'] ?? ''}',
        isGroup: '${data['call_kind'] ?? 'direct'}' == 'group',
      ),
    );
  } catch (e) {
    debugPrint('handleCallPushInBackground failed: $e');
  }
  return true;
}
