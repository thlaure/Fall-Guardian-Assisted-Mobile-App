package com.fallguardian

import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {

    companion object {
        const val CHANNEL = "fall_guardian/watch"

        // WeakReference prevents Activity leak; @Volatile ensures cross-thread visibility.
        @Volatile
        private var weakInstance: java.lang.ref.WeakReference<MainActivity>? = null

        /** Thread-safe accessor — returns null if Activity is destroyed. */
        fun getInstance(): MainActivity? = weakInstance?.get()
    }

    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        weakInstance = java.lang.ref.WeakReference(this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
    }

    override fun onPause() {
        super.onPause()
        Wearable.getMessageClient(this).removeListener(this)
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path == "/fall_event") {
            val timestamp = ByteBuffer.wrap(messageEvent.data).long
            sendFallDetectedToFlutter(timestamp)
        }
    }

    /**
     * Called by WearDataListenerService (background) or onDataChanged (foreground)
     * when a fall event arrives from the watch.
     */
    fun sendFallDetectedToFlutter(timestamp: Long) {
        runOnUiThread {
            channel.invokeMethod("onFallDetected", mapOf("timestamp" to timestamp))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        weakInstance = null
    }
}
