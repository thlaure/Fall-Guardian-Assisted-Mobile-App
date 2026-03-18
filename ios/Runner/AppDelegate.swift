import UIKit
import Flutter
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var channel: FlutterMethodChannel?
    private var watchSession: WatchSessionManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Called once the FlutterViewController is ready (scene-based lifecycle).
    override func applicationDidBecomeActive(_ application: UIApplication) {
        if channel == nil, let controller = window?.rootViewController as? FlutterViewController {
            channel = FlutterMethodChannel(
                name: "fall_guardian/watch",
                binaryMessenger: controller.binaryMessenger
            )
            watchSession = WatchSessionManager(channel: channel!)
            watchSession?.startSession()
        }
    }
}
