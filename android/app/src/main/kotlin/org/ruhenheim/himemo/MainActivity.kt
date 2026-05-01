package org.ruhenheim.himemo

import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.view.WindowManager
import android.util.Base64
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
        private const val WIDGET_CHANNEL = "org.ruhenheim.himemo/widget"
        private const val INTEGRITY_CHANNEL = "org.ruhenheim.himemo/integrity"
        private const val PRIVACY_CHANNEL = "org.ruhenheim.himemo/privacy"
    }

    private var widgetChannel: MethodChannel? = null
    private var integrityChannel: MethodChannel? = null
    private var privacyChannel: MethodChannel? = null

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
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingQuickCapture" -> result.success(buildQuickCapturePayload(intent))
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
                    setPrivacyProtected(enabled)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (shouldOpenQuickCapture(intent)) {
            widgetChannel?.invokeMethod("openQuickCapture", buildQuickCapturePayload(intent))
        }
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

    private fun buildQuickCapturePayload(intent: Intent?): Map<String, Any> {
        val isShare = isShareIntent(intent)
        val subject = intent?.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val combined = listOf(subject, body)
            .filter { it.isNotBlank() }
            .joinToString(separator = "\n\n")
            .trim()
        return mapOf(
            "source" to if (isShare) "share" else "widget",
            "text" to combined,
            "files" to sharedFilesFromIntent(intent),
        )
    }

    private fun sharedFilesFromIntent(intent: Intent?): List<Map<String, String>> {
        if (!isShareIntent(intent)) {
            return emptyList()
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
        return uris.distinct().mapNotNull { uri ->
            val mimeType = contentResolver.getType(uri) ?: intent?.type.orEmpty()
            if (!isSupportedSharedMimeType(mimeType)) {
                return@mapNotNull null
            }
            copySharedUri(uri, mimeType)
        }
    }

    private fun isSupportedSharedMimeType(mimeType: String): Boolean {
        val normalized = mimeType.lowercase()
        return normalized.startsWith("image/") ||
            normalized.startsWith("video/") ||
            normalized.startsWith("audio/")
    }

    private fun copySharedUri(uri: Uri, mimeType: String): Map<String, String>? {
        val displayName = displayNameForUri(uri).ifBlank {
            "shared-${UUID.randomUUID()}"
        }
        val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val directory = File(cacheDir, "shared_imports")
        directory.mkdirs()
        val destination = File(directory, "${UUID.randomUUID()}-$safeName")
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            mapOf(
                "path" to destination.absolutePath,
                "name" to displayName,
                "mimeType" to mimeType,
            )
        } catch (_: Throwable) {
            runCatching { destination.delete() }
            null
        }
    }

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

    private fun setPrivacyProtected(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }
}
