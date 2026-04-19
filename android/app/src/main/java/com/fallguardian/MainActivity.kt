package com.fallguardian

import android.app.NotificationManager
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import android.util.Base64
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "fall_guardian/watch"
        const val SECURE_STORAGE_CHANNEL = "fall_guardian/secure_storage"
        const val PREFS_NAME = "fall_guardian"
        const val PENDING_THRESHOLDS_KEY = "pending_thresholds_json"
        const val PENDING_CANCEL_KEY = "pending_alert_cancelled"
        private const val SECURE_STORE_KEY_ALIAS = "fall_guardian_secure_store"
        private const val SECURE_STORE_PREFIX = "secure:"

        // WeakReference prevents Activity leak; @Volatile ensures cross-thread visibility.
        @Volatile
        private var weakInstance: java.lang.ref.WeakReference<MainActivity>? = null

        /** Thread-safe accessor — returns null if Activity is destroyed. */
        fun getInstance(): MainActivity? = weakInstance?.get()
    }

    private lateinit var channel: MethodChannel
    private lateinit var secureStorageChannel: MethodChannel
    private val prefs: SharedPreferences by lazy {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }

    // Tracks the last timestamp forwarded to Flutter so we never push two
    // FallAlertScreens for the same fall event.  This can happen when the app
    // is backgrounded: WearDataListenerService calls sendFallDetectedToFlutter()
    // immediately (to start the SMS countdown) and also shows a notification;
    // when the user taps the notification onNewIntent fires with the same
    // timestamp — the dedup check here silently drops the duplicate.
    @Volatile private var lastForwardedTimestamp = Long.MIN_VALUE

    /** True when the activity is currently visible to the user. */
    val isInForeground: Boolean
        get() = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        weakInstance = java.lang.ref.WeakReference(this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        secureStorageChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURE_STORAGE_CHANNEL
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendThresholds" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) sendThresholdsToWatch(args)
                    result.success(null)
                }
                "sendCancelAlert" -> {
                    sendCancelAlertToWatch()
                    result.success(null)
                }
                // Direct SMS send via Android SmsManager — no compose UI shown.
                // Flutter calls this on Android instead of flutter_sms (which
                // always opens the SMS app in v3.0.1).
                "sendSms" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    val message = args?.get("message") as? String ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val recipients = args?.get("recipients") as? List<String> ?: emptyList()
                    try {
                        // On Android 12+ (API 31) SmsManager.getDefault() is deprecated;
                        // use the context-based variant instead.
                        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            getSystemService(SmsManager::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            SmsManager.getDefault()
                        }
                        recipients.forEach { phone ->
                            // divideMessage splits long texts into 160-char chunks
                            // automatically, then sends them as a multipart SMS.
                            val parts = smsManager.divideMessage(message)
                            smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                            Log.d("MainActivity", "sendSms: sent to $phone")
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "sendSms failed", e)
                        result.error("SMS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        secureStorageChannel.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            val key = args?.get("key") as? String
            when (call.method) {
                "read" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Missing key", null)
                        return@setMethodCallHandler
                    }
                    result.success(readSecureValue(key))
                }
                "write" -> {
                    val value = args?.get("value") as? String
                    if (key == null || value == null) {
                        result.error("INVALID_ARGS", "Missing key/value", null)
                        return@setMethodCallHandler
                    }
                    writeSecureValue(key, value)
                    result.success(null)
                }
                "delete" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Missing key", null)
                        return@setMethodCallHandler
                    }
                    deleteSecureValue(key)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        flushPendingCancelToFlutter()
        flushPendingThresholdsToWatch()
        requestFullScreenIntentPermissionIfNeeded()
        // Handle fall event launched via intent (activity was not running)
        if (isTrustedIntent(intent)) {
            intent?.getLongExtra("fall_timestamp", Long.MIN_VALUE)
                ?.takeIf { it != Long.MIN_VALUE }
                ?.let { sendFallDetectedToFlutter(it) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Handle fall event when activity is already running (singleTop)
        if (isTrustedIntent(intent)) {
            intent.getLongExtra("fall_timestamp", Long.MIN_VALUE)
                .takeIf { it != Long.MIN_VALUE }
                ?.let { sendFallDetectedToFlutter(it) }
        }
    }

    /**
     * Returns true only when the intent originates from this same package.
     * WearDataListenerService sends internal intents, so same-package intents must pass.
     * External apps crafting a fall_timestamp intent are rejected.
     */
    private fun isTrustedIntent(intent: Intent?): Boolean {
        if (intent == null) return true
        if (intent.hasExtra("fall_timestamp").not()) return true
        return intent.`package` == packageName || callingActivity?.packageName == packageName
    }

    /**
     * Called by WearDataListenerService (background) or onNewIntent (notification tap)
     * when a fall event arrives from the watch.
     *
     * The dedup guard prevents a second FallAlertScreen when the app is backgrounded:
     * WearDataListenerService calls this immediately (so the 30-second SMS timer starts)
     * and also shows a notification. If the user taps the notification, onNewIntent
     * fires with the same timestamp — without dedup we would push FallAlertScreen twice.
     */
    fun sendFallDetectedToFlutter(timestamp: Long) {
        if (timestamp == lastForwardedTimestamp) return  // duplicate — already in progress
        lastForwardedTimestamp = timestamp
        runOnUiThread {
            Log.d("MainActivity", "sendFallDetectedToFlutter: timestamp=$timestamp")
            // Cancel the native wakeup notification shown by WearDataListenerService
            // when the app was backgrounded or killed — FallAlertScreen takes over.
            getSystemService(NotificationManager::class.java)
                ?.cancel(WearDataListenerService.FALL_WAKEUP_NOTIF_ID)
            channel.invokeMethod("onFallDetected", mapOf("timestamp" to timestamp))
        }
    }

    fun sendCancelAlertToFlutter() {
        prefs.edit().putBoolean(PENDING_CANCEL_KEY, false).apply()
        runOnUiThread {
            Log.d("MainActivity", "sendCancelAlertToFlutter: forwarding cancel to Flutter")
            channel.invokeMethod("onAlertCancelled", null)
        }
    }

    private fun sendCancelAlertToWatch() {
        val payload = """{"event":"alert_cancelled"}""".toByteArray(Charsets.UTF_8)
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                Log.d("MainActivity", "sendCancelAlertToWatch: ${nodes.size} node(s) found")
                nodes.forEach { node ->
                    Log.d("MainActivity", "sendCancelAlertToWatch: sending to ${node.displayName}")
                    Wearable.getMessageClient(this)
                        .sendMessage(node.id, "/cancel_alert", payload)
                        .addOnSuccessListener { Log.d("MainActivity", "sendCancelAlertToWatch: sent OK") }
                        .addOnFailureListener { e -> Log.e("MainActivity", "sendCancelAlertToWatch: failed", e) }
                }
                if (nodes.isEmpty()) Log.w("MainActivity", "sendCancelAlertToWatch: no connected nodes")
            }
            .addOnFailureListener { e -> Log.e("MainActivity", "sendCancelAlertToWatch: getNodeClient failed", e) }
    }

    private fun sendThresholdsToWatch(thresholds: Map<String, Any>) {
        val json = org.json.JSONObject(thresholds)
        val payload = json.toString().toByteArray(Charsets.UTF_8)
        prefs.edit().putString(PENDING_THRESHOLDS_KEY, json.toString()).apply()
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.w("MainActivity", "sendThresholdsToWatch: no connected nodes, keeping pending payload")
                    return@addOnSuccessListener
                }
                var pendingSends = nodes.size
                var failed = false
                nodes.forEach { node ->
                    Wearable.getMessageClient(this)
                        .sendMessage(node.id, "/thresholds", payload)
                        .addOnSuccessListener {
                            pendingSends--
                            if (pendingSends == 0 && !failed) {
                                prefs.edit().remove(PENDING_THRESHOLDS_KEY).apply()
                            }
                        }
                        .addOnFailureListener { e ->
                            failed = true
                            Log.e("MainActivity", "Failed to send thresholds to watch", e)
                        }
                }
            }
            .addOnFailureListener { e ->
                Log.w("MainActivity", "No connected nodes for threshold sync", e)
            }
    }

    private fun flushPendingThresholdsToWatch() {
        val raw = prefs.getString(PENDING_THRESHOLDS_KEY, null) ?: return
        val json = try {
            org.json.JSONObject(raw)
        } catch (e: Exception) {
            Log.e("MainActivity", "flushPendingThresholdsToWatch: invalid pending payload", e)
            prefs.edit().remove(PENDING_THRESHOLDS_KEY).apply()
            return
        }
        val thresholds = buildMap<String, Any> {
            if (json.has("thresh_freefall")) put("thresh_freefall", json.getDouble("thresh_freefall"))
            if (json.has("thresh_impact")) put("thresh_impact", json.getDouble("thresh_impact"))
            if (json.has("thresh_tilt")) put("thresh_tilt", json.getDouble("thresh_tilt"))
            if (json.has("thresh_freefall_ms")) put("thresh_freefall_ms", json.getInt("thresh_freefall_ms"))
        }
        if (thresholds.isNotEmpty()) sendThresholdsToWatch(thresholds)
    }

    private fun flushPendingCancelToFlutter() {
        if (!prefs.getBoolean(PENDING_CANCEL_KEY, false)) return
        sendCancelAlertToFlutter()
    }

    /**
     * On Android 14+ (API 34), USE_FULL_SCREEN_INTENT requires an explicit user grant
     * via system settings — declaring it in the manifest is not enough.
     * Without it, fall alerts cannot wake the screen or show over the lock screen.
     * We prompt once (tracked via SharedPreferences) so the user isn't bothered
     * on every launch after they have already granted it.
     */
    private fun requestFullScreenIntentPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.canUseFullScreenIntent()) return
        val alreadyPrompted = prefs.getBoolean("full_screen_intent_prompted", false)
        if (alreadyPrompted) return
        prefs.edit().putBoolean("full_screen_intent_prompted", true).apply()
        startActivity(
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        weakInstance = null
    }

    private fun readSecureValue(key: String): String? {
        val encoded = prefs.getString(SECURE_STORE_PREFIX + key, null) ?: return null
        return try {
            decrypt(encoded)
        } catch (e: Exception) {
            Log.e("MainActivity", "readSecureValue failed for $key", e)
            prefs.edit().remove(SECURE_STORE_PREFIX + key).apply()
            null
        }
    }

    private fun writeSecureValue(key: String, value: String) {
        val encrypted = encrypt(value)
        prefs.edit().putString(SECURE_STORE_PREFIX + key, encrypted).apply()
    }

    private fun deleteSecureValue(key: String) {
        prefs.edit().remove(SECURE_STORE_PREFIX + key).apply()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        return Base64.encodeToString(iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(encrypted, Base64.NO_WRAP)
    }

    private fun decrypt(payload: String): String {
        val parts = payload.split(":")
        require(parts.size == 2) { "Invalid secure payload" }
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateSecretKey(),
            GCMParameterSpec(128, iv)
        )
        return String(cipher.doFinal(encrypted), StandardCharsets.UTF_8)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(SECURE_STORE_KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        val spec = KeyGenParameterSpec.Builder(
            SECURE_STORE_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }
}
