import 'package:flutter/services.dart';

typedef FallDetectedCallback = void Function(int timestamp);
typedef CancelAlertCallback = void Function();

/// Listens for fall/cancel events from the native watch layer
/// (Wear OS Data Layer on Android, WatchConnectivity on iOS).
class WatchCommunicationService {
  static const _channel = MethodChannel('fall_guardian/watch');

  FallDetectedCallback? _onFallDetected;
  CancelAlertCallback? _onCancelAlert;

  WatchCommunicationService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  void setFallDetectedCallback(FallDetectedCallback callback) {
    _onFallDetected = callback;
  }

  void setCancelAlertCallback(CancelAlertCallback callback) {
    _onCancelAlert = callback;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onFallDetected':
        final ts = (call.arguments as Map)['timestamp'] as int? ??
            DateTime.now().millisecondsSinceEpoch;
        _onFallDetected?.call(ts);
      case 'onAlertCancelled':
        _onCancelAlert?.call();
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _onFallDetected = null;
    _onCancelAlert = null;
  }

  /// Pushes threshold values to the connected watch(es).
  /// Silently no-ops if the watch is not connected or the platform rejects the call.
  static Future<void> pushThresholds({
    required double freeFall,
    required double impact,
    required double tilt,
    required int freeFallMs,
  }) async {
    try {
      await _channel.invokeMethod('sendThresholds', {
        'thresh_freefall': freeFall,
        'thresh_impact': impact,
        'thresh_tilt': tilt,
        'thresh_freefall_ms': freeFallMs,
      });
    } catch (_) {}
  }
}
