import Foundation
import WatchConnectivity
import Flutter

/// Receives messages from the watchOS app via WCSession
/// and forwards fall events to Flutter via MethodChannel.
class WatchSessionManager: NSObject, WCSessionDelegate {

    private let channel: FlutterMethodChannel

    /// Set to true when the phone alert is cancelled so the watch poll gets the right answer.
    private var alertCancelledFlag = false

    // MARK: - Watch→phone cancel polling (simulator only)
    //
    // WCSession phone←watch is also broken in the iOS simulator when the watchOS
    // app is deployed via xcrun simctl.  We mirror the phone→watch file-IPC trick:
    // the watchOS sim writes /tmp/com.fallguardian.cancelFromWatch; the iOS sim
    // polls it and forwards onAlertCancelled to Flutter when found.

    private var watchCancelPollTask: Task<Void, Never>?
    private var fallEventPollTask: Task<Void, Never>?

    /// Continuously polls for a fall event written by the watchOS simulator.
    /// WCSession watch→phone sendMessage is broken in the simulator; the watch writes
    /// /tmp/com.fallguardian.fallEvent with the ms-since-epoch timestamp instead.
    func startPollingForFallEvent() {
        fallEventPollTask?.cancel()
        #if targetEnvironment(simulator)
        fallEventPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                let path = "/tmp/com.fallguardian.fallEvent"
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(atPath: path)
                let timestamp = Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? Int(Date().timeIntervalSince1970 * 1000)
                NSLog("[WCSession][Phone] fallEvent poll: flag file found → timestamp=\(timestamp)")
                resetCancelContext()
                forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])
                startPollingForWatchCancel()
            }
        }
        #endif
    }

    /// Start polling for a cancel signal written by the watchOS simulator.
    /// Called as soon as a fall event is forwarded to Flutter.
    func startPollingForWatchCancel() {
        watchCancelPollTask?.cancel()
        #if targetEnvironment(simulator)
        watchCancelPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                let path = "/tmp/com.fallguardian.cancelFromWatch"
                guard FileManager.default.fileExists(atPath: path) else { continue }
                try? FileManager.default.removeItem(atPath: path)
                NSLog("[WCSession][Phone] watchCancel poll: flag file found → forwarding onAlertCancelled")
                forwardToFlutter("onAlertCancelled", arguments: nil)
                return
            }
        }
        #endif
    }

    func stopPollingForWatchCancel() {
        watchCancelPollTask?.cancel()
        watchCancelPollTask = nil
    }

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    func startSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        startPollingForFallEvent()
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

    /// Called when watchOS app sends a message via sendMessage() without a reply handler.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        switch message["event"] as? String {
        case "fall_detected":
            resetCancelContext()  // new fall resets cancel state + applicationContext
            let timestamp = message["timestamp"] as? Int ??
                Int(Date().timeIntervalSince1970 * 1000)
            forwardToFlutter("onFallDetected", arguments: ["timestamp": timestamp])
            startPollingForWatchCancel()  // watch→phone IPC fallback for simulator
        case "alert_cancelled":
            forwardToFlutter("onAlertCancelled", arguments: nil)
        default:
            break
        }
    }

    /// Called when watchOS app sends a message via sendMessage() WITH a reply handler.
    /// The watch uses this for the cancel-status poll.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        switch message["event"] as? String {
        case "query_cancel_status":
            NSLog("[WCSession][Phone] query_cancel_status → cancelled=\(alertCancelledFlag)")
            replyHandler(["cancelled": alertCancelledFlag])
        default:
            self.session(session, didReceiveMessage: message)
            replyHandler(["status": "received"])
        }
    }

    /// Send a cancel-alert signal to the paired Apple Watch.
    /// Also marks the flag so watch polls get the right answer immediately.
    func sendCancelAlert() {
        alertCancelledFlag = true
        stopPollingForWatchCancel()  // phone handled the cancel; stop watch poll
        // Simulator IPC: write a flag file that the watchOS sim process can poll.
        // Both sims are macOS processes sharing /tmp, so this is guaranteed to work
        // regardless of WCSession state (isReachable is often false in the sim).
        #if targetEnvironment(simulator)
        try? "cancelled".write(
            toFile: "/tmp/com.fallguardian.cancelAlert",
            atomically: true, encoding: .utf8
        )
        #endif
        guard WCSession.default.activationState == .activated else {
            NSLog("[WCSession][Phone] sendCancelAlert: not activated")
            return
        }
        NSLog("[WCSession][Phone] sendCancelAlert: isReachable=\(WCSession.default.isReachable)")
        let message: [String: Any] = ["event": "alert_cancelled"]
        // Three delivery paths for real devices, most→least real-time:
        // 1. sendMessage — immediate when reachable
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        // 2. transferUserInfo — background queue
        WCSession.default.transferUserInfo(message)
        // 3. applicationContext — persistent state
        try? WCSession.default.updateApplicationContext(["alertCancelled": true])
    }

    /// Reset the cancel context when a new fall begins so the watch does not
    /// immediately re-cancel a subsequent alert.
    func resetCancelContext() {
        alertCancelledFlag = false
        stopPollingForWatchCancel()
        try? WCSession.default.updateApplicationContext(["alertCancelled": false])
        #if targetEnvironment(simulator)
        try? FileManager.default.removeItem(atPath: "/tmp/com.fallguardian.cancelAlert")
        try? FileManager.default.removeItem(atPath: "/tmp/com.fallguardian.cancelFromWatch")
        try? FileManager.default.removeItem(atPath: "/tmp/com.fallguardian.fallEvent")
        #endif
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
