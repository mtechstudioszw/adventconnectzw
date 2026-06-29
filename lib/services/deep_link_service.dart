import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../config/router_config.dart';

/// Routes inbound `io.supabase.adventconnect://<type>/<id>` links into the
/// app. These are the links emitted by the `*-share` Supabase Edge
/// Functions (event-share, product-share, job-share, seller-share): the
/// shared web page tries to open the scheme and, if the app is installed,
/// Android/iOS hand the Uri to us here. When the app ISN'T installed the
/// web page falls back to the Play Store, so the same shared link both
/// deep-links members and recruits new installs.
///
/// Mirrors the push-notification deep-link switch in main.dart — same
/// reference_type → route mapping, just sourced from a Uri host instead
/// of an FCM data payload.
class DeepLinkService {
  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;
  static bool _started = false;

  /// Wire up cold-start + warm deep links. Safe to call once after the
  /// router and Supabase are ready (see main.dart).
  static Future<void> initialize() async {
    if (_started) return;
    _started = true;

    // Warm links: app already running, user taps a shared link.
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _route(uri, isColdStart: false),
      onError: (Object e) => debugPrint('DeepLinkService stream error: $e'),
    );

    // Cold start: app was launched BY the link. Handle after the splash
    // has finished its own routing so we push on top of /home instead of
    // being wiped out when the splash calls go('/home').
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        unawaited(_route(initial, isColdStart: true));
      }
    } catch (e) {
      debugPrint('DeepLinkService initial link failed: $e');
    }
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  static Future<void> _route(Uri uri, {required bool isColdStart}) async {
    // Only act on our own scheme; ignore https/other.
    if (uri.scheme != 'io.supabase.adventconnect') return;

    final type = uri.host; // event | product | job | seller | login-callback
    // The Supabase auth callback comes through the same scheme but is
    // owned by supabase_flutter — leave it alone.
    if (type == 'login-callback') return;

    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (id.isEmpty) return;

    if (isColdStart) await _waitUntilPastSplash();

    try {
      switch (type) {
        case 'event':
          appRouter.pushNamed('event_details', pathParameters: {'id': id});
          break;
        case 'product':
          appRouter.pushNamed('product_details', pathParameters: {'id': id});
          break;
        case 'job':
          appRouter.pushNamed('job_details', pathParameters: {'id': id});
          break;
        case 'seller':
          // seller-share keys on the seller's auth_user_id, which is
          // exactly the seller_profile route's :userId path param.
          appRouter.pushNamed('seller_profile', pathParameters: {'userId': id});
          break;
        case 'video':
          // YouTube Watch deep link → open the in-app player by video id.
          appRouter.pushNamed('watch_video', pathParameters: {'id': id});
          break;
        default:
          // Unknown host — nothing to open.
          break;
      }
    } catch (e, st) {
      debugPrint('DeepLinkService route failed for $type/$id: $e\n$st');
    }
  }

  /// Polls until the router has left the splash / biometric-lock screens
  /// (or times out) so a cold-start deep link lands on top of the real
  /// home stack. The splash normally routes within ~1–2s.
  static Future<void> _waitUntilPastSplash() async {
    for (var i = 0; i < 40; i++) {
      final loc = appRouter.routerDelegate.currentConfiguration.uri.path;
      if (loc != '/splash' && loc != '/biometric-lock') return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}
