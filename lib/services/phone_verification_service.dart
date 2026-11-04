import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';

/// Phone-number verification for new accounts — the anti-fake-account
/// step (owner, 3 Nov 2026: "email and password should be verified by a
/// phone number … if you use that old phone number, it won't work").
///
/// * One number, one account: Supabase Auth refuses a number already on
///   another account, so a spammer cannot reuse one SIM for a thousand
///   sign-ups.
/// * OFF until the owner switches it on in `app_config`
///   (`require_phone_verification`). It needs an SMS provider (Twilio,
///   MessageBird, Vonage…) set up in the Supabase dashboard first, and each
///   SMS costs money. While it is off [status] says `ok` and nothing in the
///   app changes.
/// * The database enforces it too (patch 311, `phone_ok()`), so skipping
///   this screen does not let an unverified account post or message.
class PhoneVerificationService {
  PhoneVerificationService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Owner, 4 Nov 2026: once switched on, EVERY account must verify, and
  /// an unverified account "will no longer work". The router reads this
  /// synchronously and sends every location to /verify-phone while it is
  /// true (router_config.dart), so no path — a notification tap, a shared
  /// link, the back button — reaches the rest of the app.
  ///
  /// Remembered on the device so a cold start blocks at once, before the
  /// network answers. User-scoped on purpose (no `pref:` prefix), so
  /// signing out clears it and the next account starts fresh.
  static final ValueNotifier<bool> required = ValueNotifier<bool>(false);
  static const _kRequired = 'phone_verification_required_v1';

  /// Load the remembered answer (call once at start-up).
  static void loadCached() {
    try {
      required.value = CacheService.readPref(_kRequired) == '1';
    } catch (_) {}
  }

  /// Ask the server and remember the answer. Returns it.
  ///
  /// Only a real server answer changes it. No network keeps the last
  /// answer — otherwise going offline would be a way round the block.
  static Future<bool> refresh() async {
    try {
      final r = await _client
          .rpc('my_phone_status')
          .timeout(const Duration(seconds: 6));
      await _set(r == 'required');
    } catch (_) {}
    return required.value;
  }

  static Future<void> _set(bool value) async {
    required.value = value;
    try {
      if (value) {
        await CacheService.writePref(_kRequired, '1');
      } else {
        await CacheService.deletePref(_kRequired);
      }
    } catch (_) {}
  }

  /// 'ok' or 'required'. Anything unexpected — patch not applied yet, no
  /// network — reads as 'ok': never trap a member on a screen because the
  /// server could not be asked.
  static Future<String> status() async {
    try {
      final r = await _client
          .rpc('my_phone_status')
          .timeout(const Duration(seconds: 6));
      return r == 'required' ? 'required' : 'ok';
    } catch (_) {
      return 'ok';
    }
  }

  /// Normalises what a member types to E.164. Local Zimbabwe numbers
  /// (07…) become +2637…; anything else must already start with + and a
  /// country code. Null when it cannot be a phone number.
  static String? normalise(String input, {String defaultCountryCode = '263'}) {
    var s = input.replaceAll(RegExp(r'[\s\-().]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    if (!s.startsWith('+')) {
      if (s.startsWith('0')) {
        s = '+$defaultCountryCode${s.substring(1)}';
      } else {
        return null;
      }
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(s)) return null;
    return s;
  }

  /// Sends the SMS code. Null on success, else a message to show.
  static Future<String?> sendCode(String e164) async {
    try {
      await _client.auth.updateUser(UserAttributes(phone: e164));
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  /// Confirms the SMS code. Null on success.
  static Future<String?> confirm(String e164, String code) async {
    final clean = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(clean)) {
      return 'Enter the 6-digit code we sent by SMS.';
    }
    try {
      await _client.auth.verifyOTP(
        phone: e164,
        token: clean,
        type: OtpType.phoneChange,
      );
      await _set(false);
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  static String friendlyError(Object e) {
    final msg = (e is AuthException ? e.message : e.toString()).toLowerCase();
    final status = e is AuthException ? e.statusCode : null;
    if (msg.contains('already') && msg.contains('registered') ||
        msg.contains('phone_exists') ||
        msg.contains('already been registered')) {
      return 'That number is already used by another account. Each number '
          'can verify one account only.';
    }
    if (status == '429' ||
        msg.contains('rate limit') ||
        msg.contains('too many') ||
        msg.contains('security purposes')) {
      return 'Too many codes requested. Wait a few minutes, then try again.';
    }
    if (msg.contains('expired') || msg.contains('invalid') || msg.contains('token')) {
      return 'That code is wrong or has expired. Request a new one.';
    }
    if (msg.contains('provider') || msg.contains('sms')) {
      return 'Phone verification is not available right now. Please try '
          'again later.';
    }
    if (msg.contains('socket') || msg.contains('network') ||
        msg.contains('failed host lookup')) {
      return 'No connection. Check your internet and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
