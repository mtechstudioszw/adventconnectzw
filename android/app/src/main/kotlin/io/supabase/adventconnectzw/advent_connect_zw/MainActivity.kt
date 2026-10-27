package io.supabase.adventconnectzw.advent_connect_zw

import com.ryanheise.audioservice.AudioServiceFragmentActivity

// Two plugins constrain this class, and AudioServiceFragmentActivity
// satisfies both:
//
// 1. local_auth needs a FragmentActivity host — the biometric prompt is
//    built on AndroidX BiometricPrompt. Plain FlutterActivity silently
//    swallows the prompt. AudioServiceFragmentActivity extends
//    FlutterFragmentActivity, so that still holds.
//
// 2. audio_service (under just_audio_background) needs the activity to
//    run on ITS shared FlutterEngine. On any other activity
//    AudioService.init throws "The Activity class declared in your
//    AndroidManifest.xml is wrong", MusicPlayerService falls back to plain
//    playback, and Android gets no media notification, lock-screen or
//    system media controls — while iOS, which has no such requirement,
//    works. That was the reported "music shows in-app but not in the
//    phone's media player" bug (27 Oct 2026).
//
// Side effect, by design of audio_service: the engine is not destroyed
// with the activity, so music keeps its state after the activity closes.
class MainActivity : AudioServiceFragmentActivity()
