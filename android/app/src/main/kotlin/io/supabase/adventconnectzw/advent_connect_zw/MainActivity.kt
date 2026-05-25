package io.supabase.adventconnectzw.advent_connect_zw

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth requires FlutterFragmentActivity on Android — the biometric
// prompt is built on AndroidX BiometricPrompt which needs a
// FragmentActivity host. Using plain FlutterActivity silently swallows
// the prompt: the toggle "succeeds" but no system dialog appears,
// which is exactly the bug the user reported.
class MainActivity : FlutterFragmentActivity()
