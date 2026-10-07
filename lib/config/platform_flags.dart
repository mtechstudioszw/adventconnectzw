import 'package:flutter/foundation.dart';

/// True on iOS builds. Used to hide donations, Premium and any other
/// payment entry point, because no In-App Purchase is configured and Apple
/// (Guideline 3.1.1) does not allow asking for money outside it.
///
/// Decided by the operating system at runtime. Never driven by a remote
/// flag, so there is no switch that can turn payments back on for iOS.
bool get kHidePayments =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
