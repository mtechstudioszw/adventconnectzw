import Flutter
import UIKit

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
