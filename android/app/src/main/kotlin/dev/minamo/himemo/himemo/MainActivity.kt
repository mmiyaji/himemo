package dev.minamo.himemo.himemo

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val ACTION_QUICK_CAPTURE = "dev.minamo.himemo.himemo.action.QUICK_CAPTURE"
        private const val ACTION_SEND = Intent.ACTION_SEND
        private const val CHANNEL = "dev.minamo.himemo/widget"
    }

    private var widgetChannel: MethodChannel? = null

    override fun getInitialRoute(): String? {
        return if (shouldOpenQuickCapture(intent)) {
            "/widget-capture"
        } else {
            super.getInitialRoute()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (shouldOpenQuickCapture(intent)) {
            widgetChannel?.invokeMethod("openQuickCapture", buildQuickCapturePayload(intent))
        }
    }

    private fun shouldOpenQuickCapture(intent: Intent?): Boolean {
        return intent?.action == ACTION_QUICK_CAPTURE || isShareTextIntent(intent)
    }

    private fun isShareTextIntent(intent: Intent?): Boolean {
        return intent?.action == ACTION_SEND && intent.type == "text/plain"
    }

    private fun buildQuickCapturePayload(intent: Intent?): Map<String, String> {
        val isShare = isShareTextIntent(intent)
        val subject = intent?.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val combined = listOf(subject, body)
            .filter { it.isNotBlank() }
            .joinToString(separator = "\n\n")
            .trim()
        return mapOf(
            "source" to if (isShare) "share" else "widget",
            "text" to combined,
        )
    }
}
