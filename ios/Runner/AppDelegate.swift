import UIKit
import Flutter
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var watchSession: WatchSessionManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: any FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        let channel = FlutterMethodChannel(
            name: "fall_guardian/watch",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        watchSession = WatchSessionManager(channel: channel)
        watchSession?.startSession()
    }
}
