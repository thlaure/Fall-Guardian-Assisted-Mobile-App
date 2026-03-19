package com.fallguardian

import android.content.Intent
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import java.nio.ByteBuffer

/**
 * Listens for messages sent by the Wear OS app via the Wearable MessageClient API.
 * On /fall_event path: wakes phone app and forwards event to Flutter.
 */
class WearDataListenerService : WearableListenerService() {

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path == "/fall_event") {
            val timestamp = ByteBuffer.wrap(messageEvent.data).long
            handleFallDetected(timestamp)
        }
    }

    private fun handleFallDetected(timestamp: Long) {
        val activity = MainActivity.getInstance()
        if (activity != null) {
            activity.sendFallDetectedToFlutter(timestamp)
        } else {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("fall_timestamp", timestamp)
            }
            startActivity(intent)
        }
    }
}
