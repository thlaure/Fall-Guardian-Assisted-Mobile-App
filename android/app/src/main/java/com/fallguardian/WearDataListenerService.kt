package com.fallguardian

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import java.nio.ByteBuffer

/**
 * Listens for messages sent by the Wear OS app via the Wearable MessageClient API.
 *
 * On /fall_event:
 *   • App in foreground  → invoke Flutter channel directly (FallAlertScreen appears immediately).
 *   • App in background  → show full-screen intent notification (wakes lock screen) AND start
 *                          the Flutter countdown immediately so the 30-second SMS timer runs
 *                          even if the user never taps the notification.
 *   • App killed         → show full-screen intent notification; MainActivity reads the
 *                          fall_timestamp intent extra on launch and starts FallAlertScreen.
 *
 * startActivity() from a background service is blocked on Android 10+, so the full-screen
 * intent notification is the correct mechanism for all non-foreground cases.
 */
class WearDataListenerService : WearableListenerService() {

    companion object {
        // Notification ID for the native wakeup notification. Must differ from
        // flutter_local_notifications' ID (1) to avoid cancelling each other.
        const val FALL_WAKEUP_NOTIF_ID = 2
        // Same channel ID as flutter_local_notifications so the user sees one
        // "Fall Alerts" entry in system notification settings.
        private const val CHANNEL_ID = "fall_guardian_alerts"
        private const val DATA_EVENT_TTL_MS = 2 * 60 * 1000L
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents.forEach { event ->
            if (event.type != DataEvent.TYPE_CHANGED) return@forEach
            if (!isTrustedDataItem(event)) {
                deleteDataItem(event)
                return@forEach
            }

            when (event.dataItem.uri.path) {
                "/fall_event" -> {
                    val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                    val timestamp = dataMap.getLong("timestamp", System.currentTimeMillis())
                    val updatedAt = dataMap.getLong("updatedAt", timestamp)
                    if (isStaleDataEvent(updatedAt)) {
                        deleteDataItem(event)
                        return@forEach
                    }
                    handleFallDetected(timestamp)
                }
                "/cancel_alert" -> handleCancelAlert()
            }
            deleteDataItem(event)
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        when (messageEvent.path) {
            "/cancel_alert" -> { handleCancelAlert(); return }
            "/fall_event" -> Unit
            else -> return
        }
        // Validate that the sender is an actually connected Wearable node.
        val connectedNodes = try {
            Tasks.await(Wearable.getNodeClient(this).connectedNodes)
        } catch (_: Exception) {
            return
        }
        if (connectedNodes.none { it.id == messageEvent.sourceNodeId }) return
        val timestamp = ByteBuffer.wrap(messageEvent.data).long
        handleFallDetected(timestamp)
    }

    private fun isTrustedDataItem(event: DataEvent): Boolean {
        val sourceNodeId = event.dataItem.uri.host ?: return false
        val connectedNodes = try {
            Tasks.await(Wearable.getNodeClient(this).connectedNodes)
        } catch (_: Exception) {
            return false
        }

        return connectedNodes.any { it.id == sourceNodeId }
    }

    private fun isStaleDataEvent(updatedAt: Long): Boolean {
        return System.currentTimeMillis() - updatedAt > DATA_EVENT_TTL_MS
    }

    private fun deleteDataItem(event: DataEvent) {
        Wearable.getDataClient(this).deleteDataItems(event.dataItem.uri)
    }

    private fun handleFallDetected(timestamp: Long) {
        val activity = MainActivity.getInstance()
        if (activity != null && activity.isInForeground) {
            // App is visible — invoke the Flutter channel directly.
            // No notification needed: Flutter will push FallAlertScreen immediately.
            activity.sendFallDetectedToFlutter(timestamp)
            return
        }

        // App is in the background or fully killed.
        //
        // On Android 10+ startActivity() from a background service is blocked, so we
        // cannot force the app to the foreground directly. Instead we use a full-screen
        // intent notification which:
        //   • On a locked/sleeping screen → shows as a full-screen activity (like an
        //     incoming call), turning the screen on via MainActivity's showWhenLocked /
        //     turnScreenOn attributes.
        //   • On an unlocked screen → shows as a heads-up banner the user can tap.
        //
        // If the activity is alive but backgrounded we also call sendFallDetectedToFlutter
        // immediately so the 30-second SMS countdown starts even if the user never taps
        // the notification. A dedup guard in MainActivity prevents a double FallAlertScreen
        // if the user later taps the notification (which fires onNewIntent with the same
        // timestamp).
        showFallNotification(timestamp)
        activity?.sendFallDetectedToFlutter(timestamp)
    }

    private fun showFallNotification(timestamp: Long) {
        val nm = getSystemService(NotificationManager::class.java)

        // Create the channel if it doesn't exist yet (idempotent — no-op if
        // flutter_local_notifications already created it with the same ID).
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Fall Alerts", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Urgent fall detection alerts" }
        )

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            `package` = packageName
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("fall_timestamp", timestamp)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("⚠️ Fall Detected")
            .setContentText("Open to cancel — emergency SMS sends in 30 seconds")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(pendingIntent)  // tap anywhere on the banner opens the app
            // Keep the notification visible until MainActivity cancels it.
            .setOngoing(true)

        // setFullScreenIntent makes Android show the alert as a full-screen activity
        // on the lock/sleeping screen (turning the display on via MainActivity's
        // showWhenLocked + turnScreenOn attributes).
        // On Android 14+ USE_FULL_SCREEN_INTENT is a runtime-grantable permission;
        // we check canUseFullScreenIntent() before setting it to avoid a no-op on
        // devices where the user has not granted it.
        if (Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()) {
            builder.setFullScreenIntent(pendingIntent, true)
        }

        nm.notify(FALL_WAKEUP_NOTIF_ID, builder.build())
    }

    private fun handleCancelAlert() {
        getSystemService(NotificationManager::class.java)
            ?.cancel(FALL_WAKEUP_NOTIF_ID)

        val prefs = getSharedPreferences("fall_guardian", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("pending_alert_cancelled", true).apply()

        MainActivity.getInstance()?.sendCancelAlertToFlutter()
    }
}
