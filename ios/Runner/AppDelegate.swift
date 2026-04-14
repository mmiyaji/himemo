import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let widgetChannelName = "org.ruhenheim.himemo/widget"
  private let quickCaptureUrl = "himemo://widget-capture"
  private var widgetChannel: FlutterMethodChannel?
  private var pendingQuickCaptureRequest = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      widgetChannel = FlutterMethodChannel(
        name: widgetChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      widgetChannel?.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(false)
          return
        }
        if call.method == "consumePendingQuickCapture" {
          let pending = self.pendingQuickCaptureRequest
          self.pendingQuickCaptureRequest = false
          result(pending)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let url = launchOptions?[.url] as? URL {
      _ = handleQuickCaptureURL(url)
    }
    return result
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if handleQuickCaptureURL(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func handleQuickCaptureURL(_ url: URL) -> Bool {
    guard url.absoluteString == quickCaptureUrl else {
      return false
    }
    if widgetChannel != nil {
      widgetChannel?.invokeMethod("openQuickCapture", arguments: nil)
    } else {
      pendingQuickCaptureRequest = true
    }
    return true
  }
}
