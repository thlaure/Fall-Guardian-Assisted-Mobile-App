import UIKit
import Flutter
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var channel: FlutterMethodChannel?
    private var watchSession: WatchSessionManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        channel = FlutterMethodChannel(
            name: "fall_guardian/watch",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        watchSession = WatchSessionManager(channel: channel!)
        watchSession?.startSession()
        channel!.setMethodCallHandler { [weak self] call, result in
            if call.method == "sendThresholds",
               let args = call.arguments as? [String: Any] {
                self?.watchSession?.sendThresholds(args)
            }
            result(nil)
        }
    }
}
