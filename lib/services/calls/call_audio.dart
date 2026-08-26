import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Where the call's audio is playing.
enum AudioRoute {
  /// The little speaker you hold to your ear. The default for a voice
  /// call, the way every phone has behaved since phones.
  earpiece,

  /// Loudspeaker.
  speaker,

  /// A paired Bluetooth headset or car kit.
  bluetooth,

  /// Wired headphones / headset.
  wired,
}

extension AudioRouteLabel on AudioRoute {
  String get label => switch (this) {
    AudioRoute.earpiece => 'Phone',
    AudioRoute.speaker => 'Speaker',
    AudioRoute.bluetooth => 'Bluetooth',
    AudioRoute.wired => 'Headphones',
  };
}

/// Audio routing and session management for a live call.
///
/// ## What this is actually for
///
/// Three things that all go wrong in different ways if nobody owns
/// them:
///
///   * **The audio session.** A call has to tell the OS it is a call,
///     not media playback. On Android that is `MODE_IN_COMMUNICATION`
///     plus a `voiceCommunication` usage; on iOS it is a
///     `playAndRecord` session in `voiceChat` mode. Without it the
///     volume keys adjust the wrong stream, the earpiece is not
///     available at all, and echo cancellation does not engage.
///
///   * **Audio focus.** This app also plays music and Bible audio in a
///     background service. Starting a call has to duck and hold focus,
///     and ending it has to give focus back — otherwise the member
///     hangs up into silence and has to restart their music by hand.
///
///   * **The route.** Bluetooth, wired, speaker, earpiece — including
///     the ones that appear and disappear mid-call when someone plugs
///     in headphones or walks away from their car.
///
/// ## Auto-selection
///
/// On [begin] the route is chosen the way a phone chooses it: a wired
/// headset wins if one is plugged in, then Bluetooth if something is
/// paired, otherwise the earpiece. Never speaker by default — a voice
/// call that starts on loudspeaker broadcasts a private conversation to
/// whoever is in the room, and this app carries prayer requests.
class CallAudio {
  CallAudio._();

  static final ValueNotifier<AudioRoute> _route =
      ValueNotifier<AudioRoute>(AudioRoute.earpiece);
  static final ValueNotifier<List<AudioRoute>> _available =
      ValueNotifier<List<AudioRoute>>(const [
        AudioRoute.earpiece,
        AudioRoute.speaker,
      ]);

  static Timer? _pollTimer;
  static bool _active = false;

  /// Whether the member has explicitly asked for speaker — set by
  /// [setRoute]/[toggleSpeaker] any time they choose it, including
  /// while the call is still ringing and [begin] has not run yet.
  /// Cleared on [end] so it never leaks into the next call.
  static bool _speakerRequested = false;

  /// The route in use. Listen to repaint the audio-output button.
  static ValueListenable<AudioRoute> get route => _route;

  /// What this handset can offer right now. Recomputed while a call is
  /// live so plugging in headphones mid-call adds the option.
  static ValueListenable<List<AudioRoute>> get available => _available;

  static AudioRoute get current => _route.value;
  static bool get isSpeakerOn => _route.value == AudioRoute.speaker;

  /// Configure the session and pick a starting route.
  ///
  /// Called once, as the call goes live. Every step is guarded: a
  /// handset that refuses one of these must still complete the call on
  /// whatever the platform default is, because "the call did not
  /// connect because we could not set the audio mode" is a worse
  /// outcome than a call that comes out of the wrong speaker.
  static Future<void> begin({bool preferSpeaker = false}) async {
    _active = true;
    try {
      if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration(
            // Tells Android this is a phone call: routes the earpiece,
            // engages the communication AEC, and points the volume keys
            // at the in-call stream.
            androidAudioMode: AndroidAudioMode.inCommunication,
            // Transient-exclusive: music pauses for the duration and
            // resumes when we give focus back in [end]. `mayDuck` would
            // leave the Library player quietly running under the call.
            androidAudioFocusMode:
                AndroidAudioFocusMode.gainTransientExclusive,
            androidAudioStreamType: AndroidAudioStreamType.voiceCall,
            androidAudioAttributesUsageType:
                AndroidAudioAttributesUsageType.voiceCommunication,
            androidAudioAttributesContentType:
                AndroidAudioAttributesContentType.speech,
            manageAudioFocus: true,
            // Several cheap Android handsets will not route a Bluetooth
            // MICROPHONE unless routing is forced. Without this, a
            // member on a car kit is heard by nobody.
            forceHandleAudioRouting: true,
          ),
        );
      } else if (Platform.isIOS) {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: preferSpeaker,
        );
        await Helper.ensureAudioSession();
      }
    } catch (e) {
      debugPrint('CallAudio.begin: session config failed: $e');
    }

    await _refreshAvailable();

    // Pick the route the way a phone would — but a member who already
    // tapped "speaker" while this call was still ringing (setRoute
    // applies immediately, it does not wait for begin) gets that choice
    // honoured rather than silently overwritten the moment media comes
    // up. Wired/Bluetooth still win over everything, the same as a real
    // phone: plugging in a headset should not be undone by a stale
    // speaker tap from ten seconds ago.
    final options = _available.value;
    AudioRoute initial;
    if (options.contains(AudioRoute.wired)) {
      initial = AudioRoute.wired;
    } else if (options.contains(AudioRoute.bluetooth)) {
      initial = AudioRoute.bluetooth;
    } else if (preferSpeaker || _speakerRequested) {
      initial = AudioRoute.speaker;
    } else {
      initial = AudioRoute.earpiece;
    }
    await setRoute(initial);

    // Devices come and go mid-call. Polling rather than listening
    // because flutter_webrtc exposes no device-change stream on either
    // platform; three seconds is fast enough that plugging in
    // headphones feels immediate and slow enough to be free.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshAvailable()),
    );
  }

  static Future<void> _refreshAvailable() async {
    final routes = <AudioRoute>{AudioRoute.speaker};
    // The earpiece exists on every phone, and nowhere else.
    if (Platform.isAndroid || Platform.isIOS) routes.add(AudioRoute.earpiece);

    try {
      final outputs = await Helper.audiooutputs;
      for (final device in outputs) {
        final label = device.label.toLowerCase();
        if (label.contains('bluetooth') ||
            label.contains('headset') && !label.contains('wired') ||
            label.contains('a2dp') ||
            label.contains('sco')) {
          routes.add(AudioRoute.bluetooth);
        }
        if (label.contains('wired') ||
            label.contains('headphone') ||
            label.contains('usb')) {
          routes.add(AudioRoute.wired);
        }
      }
    } catch (e) {
      // Enumeration is unsupported on some platforms and flaky on some
      // Android builds. Speaker + earpiece always work, so a failure
      // here costs the Bluetooth BUTTON, not Bluetooth itself —
      // setSpeakerphoneOnButPreferBluetooth still routes to a headset.
      debugPrint('CallAudio: output enumeration failed: $e');
    }

    final list = routes.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (!listEquals(list, _available.value)) _available.value = list;

    // The current route vanished — someone unplugged their headphones.
    // Fall back rather than leaving the call pointed at nothing.
    if (_active && !list.contains(_route.value)) {
      await setRoute(
        list.contains(AudioRoute.earpiece)
            ? AudioRoute.earpiece
            : AudioRoute.speaker,
      );
    }
  }

  /// Switch output. Safe to call before [begin] (it just records the
  /// choice) and after [end] (it no-ops).
  static Future<void> setRoute(AudioRoute next) async {
    try {
      switch (next) {
        case AudioRoute.speaker:
          await Helper.setSpeakerphoneOn(true);
          break;
        case AudioRoute.earpiece:
          await Helper.setSpeakerphoneOn(false);
          break;
        case AudioRoute.bluetooth:
          // Not `selectAudioOutput(deviceId)`: on iOS that only toggles
          // between the speaker and the preferred device, and on
          // Android the device ids for SCO are not stable across
          // handsets. This helper exists in flutter_webrtc precisely
          // because "prefer Bluetooth if there is one" is the thing
          // every calling app actually wants.
          await Helper.setSpeakerphoneOnButPreferBluetooth();
          break;
        case AudioRoute.wired:
          // A wired headset takes over the earpiece path, so turning
          // the speakerphone OFF is what selects it.
          await Helper.setSpeakerphoneOn(false);
          break;
      }
      _route.value = next;
      // Remember an explicit speaker choice so [begin] can honour it
      // even if it hasn't run yet (a tap during ringing). Any other
      // route is an explicit "not speaker", including the automatic
      // wired/Bluetooth fallback in [_refreshAvailable] — that is
      // correct too, since a device that took over the route makes a
      // stale speaker request moot.
      _speakerRequested = next == AudioRoute.speaker;
    } catch (e) {
      debugPrint('CallAudio.setRoute($next) failed: $e');
    }
  }

  /// Cycle to the next available route — what the single audio button
  /// on the call screen does when there are only two options.
  static Future<void> toggleSpeaker() =>
      setRoute(isSpeakerOn ? AudioRoute.earpiece : AudioRoute.speaker);

  /// Give the audio session back.
  ///
  /// Must run on EVERY exit path, including a crash-adjacent one, or
  /// the handset stays in communication mode: media plays out of the
  /// earpiece, the volume keys keep adjusting the call stream, and the
  /// member's music never comes back. Idempotent.
  static Future<void> end() async {
    _active = false;
    _speakerRequested = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        // Releases the communication device AND the audio focus we took
        // in [begin], which is what lets the Library player resume.
        await Helper.clearAndroidCommunicationDevice();
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration(
            androidAudioMode: AndroidAudioMode.normal,
            androidAudioFocusMode: AndroidAudioFocusMode.gainTransientMayDuck,
            androidAudioStreamType: AndroidAudioStreamType.music,
            androidAudioAttributesUsageType:
                AndroidAudioAttributesUsageType.media,
            androidAudioAttributesContentType:
                AndroidAudioAttributesContentType.music,
            manageAudioFocus: true,
          ),
        );
      } else if (Platform.isIOS) {
        await Helper.setAppleAudioIOMode(AppleAudioIOMode.none);
      }
    } catch (e) {
      debugPrint('CallAudio.end: session teardown failed: $e');
    }
    _route.value = AudioRoute.earpiece;
    _available.value = const [AudioRoute.earpiece, AudioRoute.speaker];
  }

  @visibleForTesting
  static void debugSet({AudioRoute? route, List<AudioRoute>? available}) {
    if (route != null) _route.value = route;
    if (available != null) _available.value = available;
  }
}
