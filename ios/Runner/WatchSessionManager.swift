import Foundation
import WatchConnectivity
import Flutter

/// Receives messages from the watchOS app via WCSession
/// and forwards fall events to Flutter via MethodChannel.
class WatchSessionManager: NSObject, WCSessionDelegate {

    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    func startSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Session activated — ready to receive messages
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate() // re-activate on Apple Watch switch
    }

    /// Called when watchOS app sends a message via sendMessage()
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard (message["event"] as? String) == "fall_detected" else { return }
        let timestamp = message["timestamp"] as? Int ??
            Int(Date().timeIntervalSince1970 * 1000)
        forwardFallToFlutter(timestamp: timestamp)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        self.session(session, didReceiveMessage: message)
        replyHandler(["status": "received"])
    }

    private func forwardFallToFlutter(timestamp: Int) {
        DispatchQueue.main.async {
            self.channel.invokeMethod(
                "onFallDetected",
                arguments: ["timestamp": timestamp]
            )
        }
    }
}
