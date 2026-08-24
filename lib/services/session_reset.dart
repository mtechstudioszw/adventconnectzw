import 'package:flutter/foundation.dart';

import 'account_mode_service.dart';
import 'auth_service.dart';
import 'biometric_service.dart';
import 'cache_service.dart';
import 'cart_service.dart';
import 'calls/call_service.dart';
import 'messaging_service.dart';
import 'music_player_service.dart';
import 'premium_service.dart';
import 'e2ee/e2ee_service.dart';
import 'fundraiser_service.dart';
import 'presence_service.dart';
import 'typing_signal.dart';
import 'quiz_home_signal.dart';
import 'quiz_match_service.dart';
import 'usage_analytics.dart';
import 'voice_player_service.dart';

/// Everything that has to be forgotten when an account signs out.
///
/// ## Why this file exists
///
/// Signing out does not restart the Dart isolate. Every `static` field in
/// the app therefore survives it, and the next account to sign in on the
/// same phone inherits whatever the last one left behind — it paints the
/// stale value instantly, then corrects itself a beat later when the real
/// fetch lands. That "someone else's data for about a second" flash is
/// the bug this fixes.
///
/// Wiping storage is not enough on its own, for two separate reasons:
///
///  * `SecureStorageService.clearAll()` and `CacheService.clearUserData()`
///    only clear what is on DISK. In-memory notifiers keep their values.
///  * `clearUserData()` deliberately spares the whole `pref:` namespace so
///    device settings (theme, Sabbath) survive a sign-out. A few `pref:`
///    keys are user-scoped rather than device-scoped, and those have to be
///    deleted by name.
///
/// ## The rule for new code
///
/// If you add a static that holds anything belonging to the signed-in
/// member, reset it HERE. Do not add cleanup to a sign-out button: there
/// are three of them (profile, settings, the biometric lock screen) and
/// they each used to do a different subset, which is how
/// `CartService.clearOnSignOut()` and `AccountModeService.resetToPersonal()`
/// ended up written but never called from anywhere.
///
/// Device-scoped state deliberately stays: theme, Sabbath opt-in and
/// province, YouTube playback prefs, the rating-prompt cadence, the
/// onboarding-seen flag and the ad frequency caps. Those belong to the
/// handset, not the account.
class SessionReset {
  SessionReset._();

  /// Idempotent, and never throws — a failure here must not be able to
  /// block a sign-out. Each step is isolated so one bad service cannot
  /// stop the rest from clearing.
  ///
  /// Called from `AuthService.signOut()` and `AuthService.deleteAccount()`
  /// (awaited, so it completes before the login screen appears) and again
  /// from the `AuthChangeEvent.signedOut` listener in `main.dart`, which
  /// catches sessions that end without going through those — a revoked
  /// token, or a refresh that fails for good.
  static Future<void> onSignOut() async {
    // Calls go FIRST, and this one is not cosmetic like the rest of this
    // file. Everything else here is stale state; a live call is a live
    // microphone. If the member signs out mid-call, this is what leaves
    // the call, releases the mic, tears down the peer connections, gives
    // the audio session back, dismisses the system call UI, and drops
    // this handset's push tokens so it stops ringing for an account that
    // is no longer on it.
    await _step('calls', CallService.clearOnSignOut);
    await _step('messaging', MessagingService.clearOnSignOut);
    await _step('cart', CartService.clearOnSignOut);
    await _step('accountMode', AccountModeService.resetToPersonal);
    await _step('premium', PremiumService.clear);
    await _step('presence', PresenceService.stop);
    await _step('typingSignal', TypingSignal.stop);
    // Drops in-memory handles only. The Hive box and keystore entries are
    // namespaced per user id and deliberately survive — see E2eeService.stop.
    await _step('e2ee', () async => E2eeService.stop());
    await _step('usageAnalytics', UsageAnalytics.stop);

    // Audio keeps playing across a sign-out otherwise: the next member
    // arrives to the previous one's track sitting in the mini player.
    // stop() only pauses + clears the queue — it does NOT tear down the
    // platform instance, which is the swap that has killed background
    // music three times. Leave that alone.
    // Closures, not tear-offs: `X.instance.stop` resolves the singleton
    // (and boots its audio plugin) at the CALL site, which would throw
    // outside _step's try — on a headless test binding, every time.
    await _step('music', () => MusicPlayerService.instance.stop());
    await _step('voiceNote', () => VoicePlayerService.instance.stop());
    await _step('voiceChatId', () async {
      VoicePlayerService.openChatId.value = null;
    });

    // Biometric unlock is stored per user id, but the in-memory mirror is
    // a plain static and would otherwise carry over.
    await _step('biometric', () async {
      BiometricService.clearSessionOnSignOut();
    });

    // The verified-tick flag is cached for the session (it is granted by an
    // admin and cannot change mid-session). Without this, an unverified
    // member signing in after a verified one on the same phone would render
    // a gold tick on their own post preview — a badge they have not been
    // given, on the one surface whose job is to show them the truth.
    await _step('verifiedTick', () async {
      AuthService.clearVerifiedCache();
    });

    // The cached quiz identity is a static, and it also holds the live
    // match's Realtime channel open — the next account would arrive to the
    // previous player's name and a subscription to their match.
    await _step('quizMatch', () async {
      QuizMatchService.resetForSignOut();
    });

    // Home's cached live-invite count. Same reason as above — it is a
    // static notifier, so the next account would arrive to the previous
    // player's live dot lit on the Quiz pill.
    await _step('quizHomeSignal', () async {
      QuizHomeSignal.resetForSignOut();
    });

    // The iPhone fundraiser's in-memory campaign, which carries THIS
    // member's dismissal flag on it. Same static-notifier problem as the
    // two above: the disk copy is unprefixed and so `clearUserData()`
    // already takes it, but the notifier would hand the next account the
    // previous member's "I dismissed this" until the next refresh landed.
    await _step('fundraiser', () async {
      FundraiserService.resetForSignOut();
    });

    // User-scoped `pref:` keys. `clearUserData()` spares this namespace so
    // device settings survive, so these go by name.
    //
    // Story likes are the most visible of them: the viewer paints the
    // heart from this cache immediately and only then asks the server, so
    // a new account opened somebody else's story already hearted.
    await _step('storyLikes', () async {
      await CacheService.deletePrefsWithPrefix('pref:story_liked:');
    });
  }

  static Future<void> _step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, st) {
      debugPrint('SessionReset: $name failed: $e\n$st');
    }
  }
}
