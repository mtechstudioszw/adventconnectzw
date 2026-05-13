# Build a signed, obfuscated Android App Bundle for Play Store upload.
#
# Prereqs:
#   - android/key.properties must exist (cp android/key.properties.example
#     and fill in your keystore + admobAndroidAppId).
#   - $env:ADMOB_ANDROID_BANNER must be set to your real banner unit id.
#     (iOS banner is optional unless you also build for iOS here.)
#
# Output:
#   build/app/outputs/bundle/release/app-release.aab
#   build/debug-info/  <- keep this, you'll upload to Crashlytics for
#                        readable stack traces.

$ErrorActionPreference = "Stop"

if (-not (Test-Path "android/key.properties")) {
    Write-Error "android/key.properties not found. Copy android/key.properties.example and fill it in."
    exit 1
}

if (-not $env:ADMOB_ANDROID_BANNER) {
    Write-Error "ADMOB_ANDROID_BANNER env var not set. Get it from the AdMob console (ca-app-pub-XXX/YYY)."
    exit 1
}

# iOS banner is optional in this script — only matters if you're also
# producing an iOS build from here.
$iosBanner = if ($env:ADMOB_IOS_BANNER) { $env:ADMOB_IOS_BANNER } else { "ca-app-pub-3940256099942544/2934735716" }

Write-Host "==> flutter clean"
flutter clean

Write-Host "==> flutter pub get"
flutter pub get

Write-Host "==> flutter build appbundle (obfuscated)"
flutter build appbundle `
    --release `
    --obfuscate `
    --split-debug-info=build/debug-info `
    --dart-define="ADMOB_ANDROID_BANNER=$env:ADMOB_ANDROID_BANNER" `
    --dart-define="ADMOB_IOS_BANNER=$iosBanner"

Write-Host ""
Write-Host "Done. Upload artifacts:"
Write-Host "  build/app/outputs/bundle/release/app-release.aab  -> Play Console"
Write-Host "  build/debug-info/                                  -> Crashlytics symbols"
