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

    /// Called when watchOS app sends via transferUserInfo() (phone was not reachable)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        self.session(session, didReceiveMessage: userInfo)
    }

    /// Called when watchOS app sends a message via sendMessage()
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        switch message["event"] as? String {
        case "fall_detected":
            let timestamp = message["timestamp"] as? Int ??
                Int(Date().timeIntervalSince1970 * 1000)
            forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])
        case "alert_cancelled":
            forwardToFlutter("onAlertCancelled", arguments: nil)
        default:
            break
        }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        self.session(session, didReceiveMessage: message)
        replyHandler(["status": "received"])
    }

    /// Send threshold values to the paired Apple Watch via WCSession.
    func sendThresholds(_ thresholds: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = ["event": "set_thresholds", "thresholds": thresholds]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    private func forwardToFlutter(_ method: String, arguments: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod(method, arguments: arguments)
        }
    }
}
