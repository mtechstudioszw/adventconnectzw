import 'package:flutter/foundation.dart';

/// True on iOS builds. Used to hide donations, Premium and any other
/// payment entry point, because no In-App Purchase is configured and Apple
/// (Guideline 3.1.1) does not allow asking for money outside it.
///
/// Decided by the operating system at runtime. Never driven by a remote
/// flag, so there is no switch that can turn payments back on for iOS.
bool get kHidePayments =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// True on iOS builds. Hides the Music player (Library → Music, the Home
/// music cards and shortcut, Audio Bible and chapter narration).
///
/// Owner's decision, 29 Oct 2026: App Review rejected build 97 twice under
/// Guideline 2.5.4 because the app declares background audio, and keeping
/// it requires a screen recording he can't make. With music hidden there is
/// no background audio on iOS, so the `audio` background mode is removed
/// from Info.plist. Android keeps the full music player.
///
/// To bring music back on iOS: return false here AND put `audio` back in
/// UIBackgroundModes — then send App Review the recording they asked for.
bool get kHideMusic =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// True on iOS builds. No ad SDK is started on iPhone (29 Oct 2026, before
/// resubmitting to App Review).
///
/// Why: the Appodeal app key is registered for the Android app, so iOS
/// earned nothing; and serving ads on iOS properly needs an App Tracking
/// Transparency prompt (NSUserTrackingUsageDescription), the networks'
/// SKAdNetwork ids in Info.plist and matching App Privacy answers — none
/// of which exist yet. Shipping the SDK live without them is a rejection
/// risk (Guideline 5.1.2) for no money. Android keeps its ads.
///
/// To bring ads to iOS: create the iOS app in Appodeal, use its key on
/// iOS, add the ATT string and SKAdNetwork list, update the App Privacy
/// answers, then return false here.
bool get kHideAds => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// True on iOS builds. Advent AI is hidden on iPhone for now (owner,
/// 29 Oct 2026).
///
/// Google denied the Gemini project on 26 Sep 2026 (403 "Your project has
/// been denied access"), so the server switched the service off and every
/// question shows "paused". A reviewer finding a feature that doesn't work
/// is a Guideline 2.1 rejection, so iPhone hides it — the Chat inbox
/// button, the onboarding film's Advent AI scene and the /advent-ai route.
/// Android keeps it (it says "paused" there until the key is replaced).
///
/// To bring it back on iOS: replace GEMINI_API_KEY, set
/// app_config.ai_service_state = 'live', confirm it answers, then return
/// false here.
bool get kHideAdventAi =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
