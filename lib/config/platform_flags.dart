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
