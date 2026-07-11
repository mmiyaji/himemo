package org.ruhenheim.himemo

import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.util.Base64
import android.widget.FrameLayout
import android.widget.ImageView
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val ACTION_QUICK_CAPTURE = "org.ruhenheim.himemo.action.QUICK_CAPTURE"
        private const val ACTION_SEND = Intent.ACTION_SEND
        private const val ACTION_SEND_MULTIPLE = Intent.ACTION_SEND_MULTIPLE
        private const val MAX_IMAGE_BYTES = 25L * 1024L * 1024L
        private const val MAX_AUDIO_BYTES = 50L * 1024L * 1024L
        private const val MAX_VIDEO_BYTES = 200L * 1024L * 1024L
        private const val WIDGET_CHANNEL = "org.ruhenheim.himemo/widget"
        private const val INTEGRITY_CHANNEL = "org.ruhenheim.himemo/integrity"
        private const val PRIVACY_CHANNEL = "org.ruhenheim.himemo/privacy"
        private const val NETWORK_CHANNEL = "org.ruhenheim.himemo/network"
        private const val EXTRA_QUICK_CAPTURE_NONCE = "org.ruhenheim.himemo.extra.QUICK_CAPTURE_NONCE"
        private const val PRIVACY_OVERLAY_COLOR = 0xFFFDFCFF.toInt()
    }

    private var widgetChannel: MethodChannel? = null
    private var integrityChannel: MethodChannel? = null
    private var privacyChannel: MethodChannel? = null
    private var networkChannel: MethodChannel? = null
    private var privacyProtectionEnabled = false
    private var privacyOverlayView: FrameLayout? = null

    override fun getInitialRoute(): String? {
        return if (shouldOpenQuickCapture(intent)) {
            "/widget-capture"
        } else {
            super.getInitialRoute()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
        integrityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTEGRITY_CHANNEL)
        privacyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIVACY_CHANNEL)
        networkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL)
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingQuickCapture" -> {
                    val currentIntent = intent
                    if (shouldOpenQuickCapture(currentIntent)) {
                        val payload = buildQuickCapturePayload(currentIntent)
                        consumeQuickCaptureIntent(currentIntent)
                        result.success(payload)
                    } else {
                        result.success(null)
                    }
                }
                "deleteSharedImportFiles" -> {
                    val paths = call.argument<List<String>>("paths").orEmpty()
                    paths.forEach { path ->
                        runCatching {
                            val file = File(path)
                            if (isSharedImportFile(file) && file.exists()) {
                                file.delete()
                            }
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        integrityChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAvailability" -> result.success(buildIntegrityAvailability())
                "requestToken" -> {
                    val requestHash = call.argument<String>("requestHash")?.trim()
                    if (requestHash.isNullOrEmpty()) {
                        result.error("invalid-argument", "requestHash must not be empty.", null)
                        return@setMethodCallHandler
                    }
                    requestIntegrityToken(requestHash, result)
                }
                else -> result.notImplemented()
            }
        }
        privacyChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setProtected" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val showCover = call.argument<Boolean>("showCover") ?: false
                    setPrivacyProtected(enabled, showCover)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        networkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "currentConnectionKind" -> result.success(currentConnectionKind())
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (shouldOpenQuickCapture(intent)) {
            widgetChannel?.invokeMethod("openQuickCapture", buildQuickCapturePayload(intent))
            consumeQuickCaptureIntent(intent)
        }
    }

    override fun onPause() {
        if (privacyProtectionEnabled) {
            setPrivacyOverlayVisible(true)
        }
        super.onPause()
    }

    override fun onStop() {
        if (privacyProtectionEnabled) {
            setPrivacyOverlayVisible(true)
        }
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        setPrivacyOverlayVisible(false)
    }

    private fun shouldOpenQuickCapture(intent: Intent?): Boolean {
        return intent?.action == ACTION_QUICK_CAPTURE || isShareIntent(intent)
    }

    private fun isShareIntent(intent: Intent?): Boolean {
        return when (intent?.action) {
            ACTION_SEND, ACTION_SEND_MULTIPLE -> true
            else -> false
        }
    }

    private fun currentConnectionKind(): String {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return "unknown"
        val network = manager.activeNetwork ?: return "none"
        val capabilities = manager.getNetworkCapabilities(network) ?: return "unknown"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
    }

    private fun buildQuickCapturePayload(intent: Intent?): Map<String, Any> {
        val isShare = isShareIntent(intent)
        val subject = intent?.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val combined = listOf(subject, body)
            .filter { it.isNotBlank() }
            .joinToString(separator = "\n\n")
            .trim()
        val sharedFiles = sharedFilePayloadFromIntent(intent)
        return mapOf(
            "nonce" to quickCaptureNonce(intent),
            "source" to if (isShare) "share" else "widget",
            "text" to combined,
            "files" to sharedFiles.first,
            "rejectedFiles" to sharedFiles.second,
        )
    }

    private fun quickCaptureNonce(intent: Intent?): String {
        if (intent == null) {
            return UUID.randomUUID().toString()
        }
        val existing = intent.getStringExtra(EXTRA_QUICK_CAPTURE_NONCE)
        if (!existing.isNullOrBlank()) {
            return existing
        }
        val nonce = UUID.randomUUID().toString()
        intent.putExtra(EXTRA_QUICK_CAPTURE_NONCE, nonce)
        return nonce
    }

    private fun consumeQuickCaptureIntent(consumedIntent: Intent?) {
        if (consumedIntent == null || intent !== consumedIntent) {
            return
        }
        setIntent(
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER),
        )
    }

    private fun sharedFilePayloadFromIntent(
        intent: Intent?,
    ): Pair<List<Map<String, String>>, List<Map<String, String>>> {
        if (!isShareIntent(intent)) {
            return Pair(emptyList(), emptyList())
        }
        val uris = mutableListOf<Uri>()
        val stream = intent?.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (stream != null) {
            uris.add(stream)
        }
        val clipData = intent?.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                val uri = clipData.getItemAt(index).uri
                if (uri != null) {
                    uris.add(uri)
                }
            }
        }
        val files = mutableListOf<Map<String, String>>()
        val rejected = mutableListOf<Map<String, String>>()
        uris.distinct().forEach { uri ->
            val displayName = displayNameForUri(uri).ifBlank {
                uri.lastPathSegment.orEmpty().ifBlank { "shared-file" }
            }
            val mimeType = resolveSharedMimeType(
                contentResolver.getType(uri) ?: intent?.type.orEmpty(),
                displayName,
            )
            if (!isSupportedSharedMimeType(mimeType)) {
                rejected.add(
                    rejectedSharedFile(
                        displayName,
                        mimeType,
                        "unsupported_type",
                    ),
                )
                return@forEach
            }
            val copied = try {
                copySharedUri(uri, mimeType, displayName)
            } catch (_: SharedFileTooLargeException) {
                rejected.add(
                    rejectedSharedFile(
                        displayName,
                        mimeType,
                        "too_large",
                    ),
                )
                return@forEach
            }
            if (copied == null) {
                rejected.add(
                    rejectedSharedFile(
                        displayName,
                        mimeType,
                        "unreadable",
                    ),
                )
            } else {
                files.add(copied)
            }
        }
        return Pair(files, rejected)
    }

    private fun isSupportedSharedMimeType(mimeType: String): Boolean {
        val normalized = mimeType.lowercase()
        return normalized.startsWith("image/") ||
            normalized.startsWith("video/") ||
            normalized.startsWith("audio/")
    }

    private fun resolveSharedMimeType(mimeType: String, displayName: String): String {
        if (mimeType.isNotBlank() && mimeType != "*/*" && isSupportedSharedMimeType(mimeType)) {
            return mimeType
        }
        return when (displayName.substringAfterLast('.', "").lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            "mp4" -> "video/mp4"
            "mov" -> "video/quicktime"
            "m4v" -> "video/x-m4v"
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "wav" -> "audio/wav"
            "aac" -> "audio/aac"
            "caf" -> "audio/x-caf"
            "aif", "aiff" -> "audio/aiff"
            "flac" -> "audio/flac"
            "ogg" -> "audio/ogg"
            else -> mimeType
        }
    }

    private fun copySharedUri(
        uri: Uri,
        mimeType: String,
        displayName: String,
    ): Map<String, String>? {
        val maxBytes = maxBytesForMimeType(mimeType)
        val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val directory = File(cacheDir, "shared_imports")
        directory.mkdirs()
        val destination = File(directory, "${UUID.randomUUID()}-$safeName")
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var totalBytes = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) {
                            break
                        }
                        totalBytes += read
                        if (totalBytes > maxBytes) {
                            throw SharedFileTooLargeException()
                        }
                        output.write(buffer, 0, read)
                    }
                }
            } ?: return null
            mapOf(
                "path" to destination.absolutePath,
                "name" to displayName,
                "mimeType" to mimeType,
            )
        } catch (error: SharedFileTooLargeException) {
            runCatching { destination.delete() }
            throw error
        } catch (_: Throwable) {
            runCatching { destination.delete() }
            null
        }
    }

    private fun maxBytesForMimeType(mimeType: String): Long {
        val normalized = mimeType.lowercase()
        return when {
            normalized.startsWith("image/") -> MAX_IMAGE_BYTES
            normalized.startsWith("video/") -> MAX_VIDEO_BYTES
            normalized.startsWith("audio/") -> MAX_AUDIO_BYTES
            else -> 0L
        }
    }

    private fun rejectedSharedFile(
        name: String,
        mimeType: String,
        reason: String,
    ): Map<String, String> {
        return mapOf(
            "name" to name,
            "mimeType" to mimeType,
            "reason" to reason,
        )
    }

    private class SharedFileTooLargeException : Exception()

    private fun displayNameForUri(uri: Uri): String {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val nameIndex = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME) ?: -1
            if (cursor != null && nameIndex >= 0 && cursor.moveToFirst()) {
                cursor.getString(nameIndex).orEmpty()
            } else {
                uri.lastPathSegment.orEmpty()
            }
        } catch (_: Throwable) {
            uri.lastPathSegment.orEmpty()
        } finally {
            cursor?.close()
        }
    }

    private fun isSharedImportFile(file: File): Boolean {
        val directory = File(cacheDir, "shared_imports")
        return runCatching {
            file.canonicalPath.startsWith(directory.canonicalPath)
        }.getOrDefault(false)
    }

    private fun buildIntegrityAvailability(): Map<String, Any> {
        val installerPackage = try {
            packageManager.getInstallerPackageName(packageName).orEmpty()
        } catch (_: Throwable) {
            ""
        }
        val hasPlayStore = try {
            packageManager.getPackageInfo("com.android.vending", 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
        val available = hasPlayStore && BuildConfig.PLAY_INTEGRITY_PROJECT_NUMBER > 0L
        return mapOf(
            "available" to available,
            "installerPackage" to installerPackage,
            "projectNumber" to BuildConfig.PLAY_INTEGRITY_PROJECT_NUMBER.toString(),
            "message" to if (available) {
                "Play Integrity is ready for backend verification."
            } else {
                "Google Play Store or project configuration is unavailable."
            },
        )
    }

    private fun requestIntegrityToken(
        requestHash: String,
        result: MethodChannel.Result,
    ) {
        val integrityManager = IntegrityManagerFactory.create(applicationContext)
        val nonce = Base64.encodeToString(requestHash.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val request = IntegrityTokenRequest.builder()
            .setNonce(nonce)
            .setCloudProjectNumber(BuildConfig.PLAY_INTEGRITY_PROJECT_NUMBER)
            .build()
        integrityManager.requestIntegrityToken(request)
            .addOnSuccessListener { response ->
                result.success(response.token())
            }
            .addOnFailureListener { error ->
                result.error(
                    "play-integrity",
                    error.message ?: "Play Integrity token request failed.",
                    error.javaClass.simpleName,
                )
            }
    }

    private fun setPrivacyProtected(enabled: Boolean, showCover: Boolean) {
        runOnUiThread {
            privacyProtectionEnabled = enabled && showCover
            if (privacyProtectionEnabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            if (!privacyProtectionEnabled) {
                setPrivacyOverlayVisible(false)
            }
        }
    }

    private fun setPrivacyOverlayVisible(visible: Boolean) {
        runOnUiThread {
            val root = window.decorView as? ViewGroup ?: return@runOnUiThread
            if (visible) {
                val overlay = privacyOverlayView ?: buildPrivacyOverlay().also {
                    privacyOverlayView = it
                }
                if (overlay.parent == null) {
                    root.addView(
                        overlay,
                        ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT,
                        ),
                    )
                }
                overlay.bringToFront()
            } else {
                privacyOverlayView?.let { overlay ->
                    (overlay.parent as? ViewGroup)?.removeView(overlay)
                }
            }
        }
    }

    private fun buildPrivacyOverlay(): FrameLayout {
        val iconSize = (128 * resources.displayMetrics.density).toInt()
        return FrameLayout(this).apply {
            setBackgroundColor(PRIVACY_OVERLAY_COLOR)
            isClickable = false
            isFocusable = false
            addView(
                ImageView(context).apply {
                    setImageResource(R.mipmap.ic_launcher)
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    alpha = 0.96f
                },
                FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER),
            )
        }
    }
}
