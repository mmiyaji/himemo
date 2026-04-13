package dev.minamo.himemo.himemo

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val ACTION_QUICK_CAPTURE = "dev.minamo.himemo.himemo.action.QUICK_CAPTURE"
        private const val CHANNEL = "dev.minamo.himemo/widget"
    }

    private var widgetChannel: MethodChannel? = null

    override fun getInitialRoute(): String? {
        return if (intent?.action == ACTION_QUICK_CAPTURE) {
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
        if (intent.action == ACTION_QUICK_CAPTURE) {
            widgetChannel?.invokeMethod("openQuickCapture", null)
        }
    }
}
