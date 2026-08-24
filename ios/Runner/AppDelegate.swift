import Flutter
import UIKit
import PushKit
import flutter_callkit_incoming

// =====================================================================
//  AppDelegate — Flutter bootstrap + PushKit (VoIP) for incoming calls
//
//  ## Why PushKit is here and not in Dart
//
//  An incoming call has to reach a phone whose app is not running. On
//  iOS there is exactly one mechanism for that — an APNs **VoIP** push
//  delivered to PushKit — and it is only reachable from native code,
//  before any Flutter engine exists. Firebase Messaging cannot do it:
//  Apple requires the `<bundle-id>.voip` topic and
//  `apns-push-type: voip`, and FCM only ever publishes to the app's
//  normal topic. That is why supabase/functions/call-push signs its own
//  APNs JWT and talks to Apple directly.
//
//  ## The bargain Apple enforces
//
//  Every VoIP push MUST result in a call being reported to CallKit,
//  synchronously, in `didReceiveIncomingPushWith`. An app that takes a
//  VoIP push and reports nothing is terminated by the system, and
//  repeated offences get its VoIP privileges revoked.
//
//  This is why the `cancel` branch below still reports the call before
//  ending it. It looks wrong — we are showing an incoming call purely
//  in order to dismiss it — and it is not: it is the only compliant way
//  to handle "the caller hung up while your phone was ringing".
//
//  ## What this file deliberately does NOT do
//
//  It does not answer, negotiate media, or touch Supabase. It reports
//  the call to the system and stops. Everything after the member taps
//  Accept happens in Dart (lib/services/calls/call_service.dart), which
//  by then has a session and can ask the server what is actually going
//  on rather than trusting a push payload.
//
//  ## Unverified
//
//  This project has never been built for iOS — there is no Apple
//  Developer account yet and the whole app is developed on Windows. The
//  code below is written against the current PushKit/CallKit contracts
//  and the flutter_callkit_incoming 3.1.5 Swift API, but it has not been
//  compiled. Treat the first iOS build as the real test of this file.
//  See docs/CALLING_SETUP.md.
// =====================================================================

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Held for the process lifetime. A PKPushRegistry that goes out of
  /// scope stops delivering, and the symptom is the worst kind: pushes
  /// arrive in development (where something else retains it) and
  /// silently stop in release.
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerForVoIPPushes()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // -------------------------------------------------------------------
  //  PushKit registration
  // -------------------------------------------------------------------

  private func registerForVoIPPushes() {
    // Main queue, not a background one. CallKit must be driven from the
    // main thread, and the delegate callback below reports a call
    // directly.
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }
}

// =====================================================================
//  PKPushRegistryDelegate
// =====================================================================

extension AppDelegate: PKPushRegistryDelegate {

  /// The VoIP token. A DIFFERENT token from FCM's, stored in a different
  /// column (`user_call_devices.voip_token`), because they are issued by
  /// different services and are not interchangeable.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    // The plugin forwards this to Dart, where CallKitBridge stores it
    // via the call_register_device RPC.
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  /// The token was revoked — the app was reinstalled, or iOS rotated it.
  /// Clearing it here would need a Supabase session we do not have in
  /// this context; the stale row is harmless (APNs simply rejects it)
  /// and is overwritten by the next `didUpdate`.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  /// A call is arriving (or being cancelled).
  ///
  /// The payload keys are the flat `data` map built by
  /// supabase/functions/call-push/index.ts. Keep the two in step.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let dict = payload.dictionaryPayload
    let callId = (dict["call_id"] as? String) ?? ""
    let action = (dict["action"] as? String) ?? "ring"
    let callerName = (dict["caller_name"] as? String) ?? "Adventist Super App"
    let callerPhoto = (dict["caller_photo"] as? String) ?? ""
    let isGroup = (dict["call_kind"] as? String) == "group"

    // A payload with no call id is not something we can report a call
    // for. Reporting a placeholder would put a fake call on the
    // member's screen, so this bails — accepting the small risk that
    // Apple counts it as an unreported push, which is the lesser harm
    // and cannot happen unless call-push is broken.
    guard !callId.isEmpty else {
      completion()
      return
    }

    // `Data` here is flutter_callkit_incoming's, NOT Foundation's.
    // Unqualified it resolves to Foundation.Data and nothing compiles.
    let data = flutter_callkit_incoming.Data(
      id: callId,
      nameCaller: callerName,
      // Deliberately not a phone number: members are identified by
      // account in this app, and CallKit would otherwise display one the
      // app never shows anywhere else.
      handle: isGroup ? "Group call" : "Adventist Super App",
      // 0 = audio. There is no video calling in this app.
      type: 0
    )
    data.appName = "Adventist Super App"
    data.avatar = callerPhoto
    data.supportsVideo = false
    data.supportsDTMF = false
    data.supportsHolding = false
    data.supportsGrouping = false
    data.supportsUngrouping = false
    data.maximumCallGroups = 1
    data.maximumCallsPerCallGroup = 1
    // Voice calls placed in this app must not land in the phone's system
    // call history: that log is shared with the dialler and would leak
    // who a member called to anyone holding the handset.
    data.includesCallsInRecents = false
    // flutter_webrtc owns the audio session (see CallAudio in Dart). Two
    // things configuring it fight, and the symptom is a first call after
    // launch with no audio at all.
    data.configureAudioSession = false
    data.extra = ["call_id": callId, "is_group": isGroup] as NSDictionary

    if action == "cancel" {
      // READ THE HEADER BEFORE SIMPLIFYING THIS.
      //
      // The caller hung up while this phone was ringing. We still have
      // to report a call, because Apple terminates an app that consumes
      // a VoIP push without reporting one — so report it and end it in
      // the same breath. CallKit collapses the two, and the member sees
      // the ringing screen disappear, which is exactly what they want.
      //
      // If the call was already reported (the usual case — the `ring`
      // push arrived first), CallKit treats the duplicate UUID as a
      // no-op and the `endCall` below is what actually does the work.
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?
        .showCallkitIncoming(data, fromPushKit: true)
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(data)
      completion()
      return
    }

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?
      .showCallkitIncoming(data, fromPushKit: true)
    completion()
  }
}
