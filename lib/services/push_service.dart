import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_bootstrap.dart';
import 'e2ee/e2ee_envelope.dart';
import 'e2ee/e2ee_service.dart';
import 'messaging_service.dart';
import 'notification_service.dart';

/// Top-level handler for FCM messages received while the app is in the
/// background or fully killed. Must be a free function (not a method)
/// because Flutter spawns it in a separate isolate.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // When notify-fcm sends a chat push DATA-ONLY (no `notification` block),
  // the system won't render it — so we render it here in the background
  // isolate WITH the inline Reply action + the sender's photo. Pushes that
  // still carry a `notification` block are rendered by the system as before;
  // we skip those to avoid a duplicate banner (backward-compatible if the
  // Edge Function hasn't been redeployed yet).
  if (message.notification != null) return;
  final refType = '${message.data['reference_type'] ?? ''}';
  if (refType != 'conversation') return;
  final refId = '${message.data['reference_id'] ?? ''}';
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await _renderIncomingChat(message, plugin);
  } catch (_) {
    // Best-effort — never crash the background isolate.
  }
  // Mark the message DELIVERED the instant this device receives the push in
  // the background, so the sender's tick goes ✓✓ even though the recipient
  // hasn't opened the app. Runs AFTER the notification render and is fully
  // guarded — Supabase init/network failures never break the push.
  if (refId.isNotEmpty) {
    try {
      // NOT startSupabaseInit(). This is a separate isolate, and a second
      // GoTrue client with autoRefreshToken:true rotates the SAME refresh
      // token — revoking the one the foreground app is holding and signing
      // the member out of a session that is still alive on the server.
      // See AppBootstrap.startSupabaseInitForBackgroundIsolate.
      await AppBootstrap.startSupabaseInitForBackgroundIsolate();
      await AppBootstrap.awaitSupabaseReady();
      await MessagingService.markConversationDelivered(refId);
    } catch (_) {
      // Falls back to marking on next app foreground, as before. An expired
      // access token here is a 401, and that is the intended trade.
    }
  }
}

/// Action id for the inline "Reply" button on chat-message notifications.
const String kReplyActionId = 'reply';

/// Top-level handler for taps/inline-replies delivered to a background
/// isolate (app killed). Inline replies submitted while the app is alive
/// go to [PushService._onLocalTap] in the main isolate instead; this is a
/// best-effort fallback for the rare case the app was torn down between
/// showing the heads-up and the user submitting the reply. Supabase may
/// not be initialised in this isolate, so the send is wrapped in a guard
/// and simply no-ops if it can't reach the backend.
@pragma('vm:entry-point')
void onPushBackgroundResponse(NotificationResponse response) {
  if (response.actionId != kReplyActionId) return;
  final text = response.input?.trim() ?? '';
  final payload = response.payload ?? '';
  if (text.isEmpty || payload.isEmpty) return;
  // Pull the conversation id out of the encoded payload.
  String convId = '';
  for (final pair in payload.split('&')) {
    final i = pair.indexOf('=');
    if (i <= 0) continue;
    if (Uri.decodeComponent(pair.substring(0, i)) == 'reference_id') {
      convId = Uri.decodeComponent(pair.substring(i + 1));
      break;
    }
  }
  if (convId.isEmpty) return;
  () async {
    try {
      await MessagingService.sendMessage(
        conversationId: convId,
        content: text,
      );
    } catch (_) {
      // Backend unreachable from this isolate — best effort only.
    }
  }();
}

/// FCM channel id shared by the class and the background isolate.
const String _kPushChannelId = 'advent_connect_zw_default';

/// Encode RemoteMessage.data into the `k=v&k=v` payload string the tap
/// handlers decode. Top-level so the background isolate can use it too.
String _encodePushPayload(Map<String, dynamic> data) => data.entries
    .map((e) =>
        '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
    .join('&');

/// Best-effort download of the sender's / group's photo for the circular
/// large icon. Returns null on any failure so the notification still shows.
Future<AndroidBitmap<Object>?> _largeIconFromUrl(String? url) async {
  if (url == null || url.trim().isEmpty) return null;
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close().timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) {
      client.close();
      return null;
    }
    final bytes = await consolidateHttpClientResponseBytes(resp);
    client.close();
    return ByteArrayAndroidBitmap(bytes);
  } catch (_) {
    return null;
  }
}

/// Whether a chat push refers to an encrypted message.
///
/// The Edge Function that builds these pushes stamps `e2ee_version`
/// alongside the body. Absent or 0 means a plaintext message — every push
/// sent before this feature, and every one from a member on an older
/// build — and those keep their server-built preview untouched.
bool _looksEncrypted(Map<String, dynamic> data) {
  final raw = '${data['e2ee_version'] ?? ''}';
  final version = int.tryParse(raw) ?? 0;
  return version > 0;
}

/// Render an incoming chat push (foreground or background isolate) with the
/// inline Reply action and the sender's photo as the large icon. Handles
/// both notification-carrying and data-only payloads.
Future<void> _renderIncomingChat(
  RemoteMessage message,
  FlutterLocalNotificationsPlugin plugin,
) async {
  final data = message.data;
  final notif = message.notification;
  final refType = '${data['reference_type'] ?? ''}';
  final refId = '${data['reference_id'] ?? ''}';
  final isConversation = refType == 'conversation' && refId.isNotEmpty;
  final title = notif?.title ?? '${data['title'] ?? 'Adventist Super App'}';
  var body = notif?.body ?? '${data['body'] ?? ''}';

  // E2EE: the server builds this push from `messages.content`, which for
  // an encrypted row is base64 — so the notification would read like a
  // wall of random characters. The DEVICE has the plaintext (it decrypted
  // and cached it when the message arrived over realtime), so rebuild the
  // preview here.
  //
  // This is how WhatsApp keeps message previews at all under E2EE: the
  // push itself never carries the text, the phone fills it in. If we have
  // not decrypted it yet — the app was killed, or the row landed while
  // offline — fall back to a neutral line rather than showing ciphertext.
  if (isConversation && _looksEncrypted(data)) {
    final messageId = '${data['message_id'] ?? ''}';
    final local = messageId.isEmpty
        ? null
        : E2eeService.cachedPlaintext(messageId);
    body = local ?? E2eeEnvelope.previewPlaceholder;
  }
  final largeIcon = isConversation
      ? await _largeIconFromUrl('${data['sender_photo'] ?? ''}')
      : null;

  // A live/new-video push carries the broadcast's own frame, the way
  // YouTube's does. The system renders `notification.image` itself when the
  // app is backgrounded; in the FOREGROUND we render the banner ourselves,
  // so the picture has to be attached here or it silently disappears.
  final imageUrl = refType == 'video'
      ? (notif?.android?.imageUrl ?? notif?.apple?.imageUrl ??
          '${data['image'] ?? ''}')
      : null;
  final bigPicture = await _largeIconFromUrl(imageUrl);
  final style = bigPicture == null
      ? null
      : BigPictureStyleInformation(
          bigPicture,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: true,
        );

  final id =
      refId.isNotEmpty ? refId.hashCode : (notif?.hashCode ?? title.hashCode);
  await plugin.show(
    id,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _kPushChannelId,
        'General notifications',
        channelDescription: 'In-app activity, messages, RSVPs and approvals.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        largeIcon: largeIcon,
        styleInformation: style,
        actions: isConversation
            ? <AndroidNotificationAction>[
                const AndroidNotificationAction(
                  kReplyActionId,
                  'Reply',
                  inputs: <AndroidNotificationActionInput>[
                    AndroidNotificationActionInput(label: 'Message'),
                  ],
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
              ]
            : null,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: _encodePushPayload(data),
  );
}

/// Wires Firebase Cloud Messaging into the app. The Supabase Edge
/// Function `notify-fcm` is what actually triggers a push when a row
/// lands in `public.notifications`; this class handles the device side
/// of that pipeline:
///
///   * Asks for notification permission once on first launch
///   * Pulls the FCM device token + saves it to `profiles.fcm_token`
///     so the Edge Function can target this device
///   * Subscribes to token refresh events
///   * Shows a heads-up notification when a push arrives in the
///     foreground (system handles background + killed)
///   * Lets you read the tap-event stream so app routes can deep-link
///     into events / prayers / chats / etc.
class PushService {
  PushService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'advent_connect_zw_default',
    'General notifications',
    description: 'In-app activity, messages, RSVPs and approvals.',
    importance: Importance.high,
  );

  static bool _initialized = false;
  static bool _bgHandlerRegistered = false;
  static final StreamController<RemoteMessage> _tapController =
      StreamController<RemoteMessage>.broadcast();
  static StreamSubscription<AuthState>? _authSub;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Registers ONLY the FCM background-message handler — nothing else.
  ///
  /// This is the one call that actually has to happen before runApp():
  /// it is what lets Android hand an incoming push to
  /// [_firebaseBackgroundHandler] when the app is fully killed. Every
  /// other line in [initialize] — local notifications, permission
  /// prompts, saving the token — is legitimately fine to defer, and
  /// stays deferred; this one line is not, which is why it is split out
  /// rather than left buried inside [initialize] behind a Supabase wait.
  ///
  /// Requires `Firebase.initializeApp()` to have already completed.
  /// Idempotent.
  static void registerBackgroundHandler() {
    if (_bgHandlerRegistered) return;
    _bgHandlerRegistered = true;
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  }

  /// Stream of taps on a push notification (foreground or
  /// system-tray-from-background). Listen from your router to deep-link
  /// to the source content using `message.data['reference_type']` etc.
  static Stream<RemoteMessage> get onMessageTap => _tapController.stream;

  /// Call from main() after Firebase.initializeApp(). Safe to call
  /// multiple times — subsequent calls no-op.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Background isolate handler — must register before runApp().
    //    Also exposed as [registerBackgroundHandler] so main() can call
    //    JUST this line, synchronously, before Firebase/Supabase/anything
    //    else — see that method's doc for why.
    registerBackgroundHandler();

    // 2. Local notifications plugin (used to render foreground pushes
    //    as a heads-up banner and to host the Android channel).
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onLocalTap,
      onDidReceiveBackgroundNotificationResponse: onPushBackgroundResponse,
    );

    final androidImpl = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_channel);
    await androidImpl?.requestNotificationsPermission();

    // 3. Ask FCM for permission (iOS-style — Android 13+ uses the same
    //    permission machinery; older Androids auto-grant).
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 4. Foreground messages → render via local notifications.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 5. Background tap (system tray) → forward to the tap stream.
    FirebaseMessaging.onMessageOpenedApp.listen(_tapController.add);

    // 6. Tap from killed state — initial message present in the stream
    //    of the new run.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _tapController.add(initial);

    // 7. Token refresh — Supabase profile stays in sync.
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((t) async {
      try {
        await NotificationService.updateFcmToken(t);
      } catch (e, st) {
        debugPrint('PushService: token refresh save failed: $e\n$st');
      }
    });

    // 8. Initial token + signed-in user → save now. The auth listener
    //    below handles the "user signs in later" case.
    await _maybeSaveTokenForCurrentUser();
    _authSub?.cancel();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _maybeSaveTokenForCurrentUser();
    });
  }

  /// Dismiss the tray notification for a conversation when the user opens it
  /// (WhatsApp parity: opening the chat clears its notification). The id
  /// mirrors [_renderIncomingChat] (`reference_id.hashCode`).
  static Future<void> cancelConversationNotification(String conversationId) async {
    if (conversationId.isEmpty) return;
    try {
      await _local.cancel(conversationId.hashCode);
    } catch (_) {
      // best-effort
    }
  }

  /// Clear the FCM token on the profile (call from sign-out so old
  /// devices stop receiving pushes for accounts that are no longer
  /// logged in). Best-effort — failures don't block sign-out.
  static Future<void> clearTokenForCurrentUser() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': null}).eq('id', user.id);
    } catch (e, st) {
      debugPrint('PushService: clear token failed: $e\n$st');
    }
  }

  static Future<void> _maybeSaveTokenForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) await NotificationService.updateFcmToken(token);
    } catch (e, st) {
      debugPrint('PushService: token save failed: $e\n$st');
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Even before we render the banner, optimistically mark the
    // conversation as delivered. notify-fcm (patch_032's webhook
    // pipeline) puts the conversation id in reference_id when the
    // notification originates from a chat message — flip every
    // undelivered incoming message in one server round-trip so the
    // sender's tick goes double the moment the push lands, not when
    // the recipient eventually opens the chat. Best-effort: failure
    // here just leaves the tick single until the chat screen runs
    // its own mark-delivered pass.
    final referenceType = '${message.data['reference_type'] ?? ''}';
    final referenceId = '${message.data['reference_id'] ?? ''}';
    if (referenceType == 'conversation' && referenceId.isNotEmpty) {
      unawaited(MessagingService.markConversationDelivered(referenceId));
    }

    // Watch pushes (new upload / live) can be muted from Settings →
    // Watch notifications. Foreground suppression happens here; the
    // server-side notif_categories check covers background delivery.
    if (referenceType == 'video' && !await watchPushesEnabled()) return;

    // Render the heads-up banner. Chat pushes get the inline Reply action +
    // the sender's photo via [_renderIncomingChat]. For data-only payloads
    // (notif == null) the banner is built from `data` — that's how chat
    // pushes arrive once notify-fcm sends them data-only. Non-chat data-only
    // payloads carry nothing to show, so skip those.
    final isConversation =
        referenceType == 'conversation' && referenceId.isNotEmpty;
    if (message.notification == null && !isConversation) return;
    await _renderIncomingChat(message, _local);
  }

  static const _kWatchPushPrefKey = 'watch_pushes_enabled';

  /// Local mirror of the Settings → "Watch — new videos & live" toggle,
  /// in SharedPreferences so the foreground handler (and background
  /// isolate, which can't touch Hive) can read it cheaply.
  static Future<void> setWatchPushesEnabled(bool enabled) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kWatchPushPrefKey, enabled);
    } catch (_) {/* best effort */}
  }

  static Future<bool> watchPushesEnabled() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(_kWatchPushPrefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static void _onLocalTap(NotificationResponse response) {
    // Inline "Reply" action on a chat notification — send the typed text
    // straight to the conversation instead of routing into the chat.
    if (response.actionId == kReplyActionId) {
      final text = response.input?.trim() ?? '';
      final data = _deserializePayload(response.payload);
      final convId = '${data['reference_id'] ?? ''}';
      if (text.isNotEmpty && convId.isNotEmpty) {
        () async {
          try {
            await MessagingService.sendMessage(
              conversationId: convId,
              content: text,
            );
            await MessagingService.markConversationRead(convId);
          } catch (_) {
            // Best-effort — a failed reply just isn't sent.
          }
        }();
      }
      return;
    }
    final data = _deserializePayload(response.payload);
    // Synthesize a minimal RemoteMessage so route listeners get the
    // same shape whether the tap came from foreground or background.
    final synthetic = RemoteMessage(data: data);
    _tapController.add(synthetic);
  }

  static Map<String, dynamic> _deserializePayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    final out = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      out[Uri.decodeComponent(pair.substring(0, i))] =
          Uri.decodeComponent(pair.substring(i + 1));
    }
    return out;
  }
}
