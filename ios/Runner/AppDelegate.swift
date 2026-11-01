import Flutter
import UIKit
import UserNotifications
import PushKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Voice calls (restored 1 Nov 2026). Held for the process lifetime: a
  /// PKPushRegistry that goes out of scope silently stops delivering.
  private var voipRegistry: PKPushRegistry?

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Notifications while the app is OPEN. iOS hands a notification that
    // arrives in the foreground to the notification centre's delegate and
    // shows nothing unless that delegate says so. With no delegate set,
    // neither firebase_messaging (which turns the push into onMessage)
    // nor flutter_local_notifications (which draws the in-app banner)
    // ever hears about it — so pushes appeared only when the app was
    // closed. FlutterAppDelegate forwards these callbacks to every
    // plugin; this line is the setup flutter_local_notifications documents
    // for iOS, and it must run before plugins register (implicit engine).
    UNUserNotificationCenter.current().delegate =
      self as? UNUserNotificationCenterDelegate

    // Ask iOS for an APNs token at launch (needs no permission).
    application.registerForRemoteNotifications()

    // Incoming calls: the ONLY way to wake a closed iPhone app to ring is
    // an APNs VoIP push delivered to PushKit (supabase/functions/call-push
    // sends it). Main queue: CallKit must be driven from the main thread.
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  // Record what iOS answered, so Dart can report it to push_diagnostics.
  // "flutter." prefix = the key shared_preferences reads on iOS.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    UserDefaults.standard.set("ok len=\(deviceToken.count)", forKey: "flutter.apns_native")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    UserDefaults.standard.set("fail \(error)", forKey: "flutter.apns_native")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}

// =====================================================================
//  PushKit (VoIP) — incoming calls. Restored from commit 24ab90b.
//
//  Apple's rule: EVERY VoIP push must report a call to CallKit, right
//  here, or iOS kills the app and eventually revokes its VoIP pushes.
//  That is why the `cancel` branch reports the call and then ends it.
//  This file never answers or touches Supabase — after Accept, Dart
//  (lib/services/calls/call_service.dart) takes over.
// =====================================================================

extension AppDelegate: PKPushRegistryDelegate {

  /// The VoIP token (different from FCM's), sent to Dart, which stores it
  /// with call_register_device.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  /// A call is arriving (or being cancelled). Payload keys come from
  /// supabase/functions/call-push/index.ts — keep the two in step.
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
    guard !callId.isEmpty else {
      completion()
      return
    }

    // flutter_callkit_incoming's Data, not Foundation's.
    let data = flutter_callkit_incoming.Data(
      id: callId,
      nameCaller: callerName,
      handle: isGroup ? "Group call" : "Adventist Super App",
      type: 0  // audio only
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
    // Keep app calls out of the phone's shared Recents list.
    data.includesCallsInRecents = false
    // flutter_webrtc owns the audio session; two owners = silent first call.
    data.configureAudioSession = false
    data.extra = ["call_id": callId, "is_group": isGroup] as NSDictionary

    if action == "cancel" {
      // Caller hung up while ringing: report, then end (Apple's rule).
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
