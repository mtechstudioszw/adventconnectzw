import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

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
