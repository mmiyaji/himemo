import Flutter
import QuickLook
import UIKit

private final class SyncV2PreviewItem: NSObject, QLPreviewItem {
  let previewItemURL: URL?
  let previewItemTitle: String?

  init(url: URL, title: String) {
    previewItemURL = url
    previewItemTitle = title
  }
}

/// Presents one in-memory decrypted attachment through Quick Look and keeps
/// its temporary plaintext file only for the lifetime of that presentation.
final class SyncV2AttachmentViewer: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  private static let channelName = "org.ruhenheim.himemo/sync_v2_attachment_viewer"
  private static let maximumBytes = 64 * 1024 * 1024
  private static let maximumCleanupEntries = 128
  private static let directoryName = "himemo-sync-v2-previews"

  private let fileQueue = DispatchQueue(label: "org.ruhenheim.himemo.sync-v2-preview-files")
  private var channel: FlutterMethodChannel?
  private var generation: UInt64 = 0
  private var isBusy = false
  private var openResult: FlutterResult?
  private var closeResults: [FlutterResult] = []
  private var previewController: QLPreviewController?
  private var previewItem: SyncV2PreviewItem?
  private var previewURL: URL?
  private var previewTitle = "Attachment"
  private var isClosing = false
  private var cleanupInFlight = false
  private var presentationInFlight = false
  private var terminalErrorCode: String?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "failed", message: nil, details: nil))
        return
      }
      switch call.method {
      case "open":
        self.open(call.arguments, result: result)
      case "close":
        self.close(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: UIApplication.willResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.closeForLifecycleChange() },
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.closeForLifecycleChange() },
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.purgePrivateDirectoryWhenActive() },
    ]
    fileQueue.async { [weak self] in
      guard let self else { return }
      try? self.preparePrivateDirectory()
    }
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
  }

  private func open(_ arguments: Any?, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(Self.error("unavailable")); return
    }
    guard let args = arguments as? [String: Any],
          let typedBytes = args["bytes"] as? FlutterStandardTypedData,
          let label = args["label"] as? String,
          !label.isEmpty,
          label.count <= 4096 else {
      result(Self.error("invalidInput")); return
    }
    let bytes = typedBytes.data
    guard !bytes.isEmpty else { result(Self.error("invalidInput")); return }
    guard bytes.count <= Self.maximumBytes else { result(Self.error("tooLarge")); return }
    guard !isBusy else { result(Self.error("busy")); return }

    isBusy = true
    isClosing = false
    terminalErrorCode = nil
    generation &+= 1
    let requestGeneration = generation
    openResult = result
    previewTitle = Self.displayTitle(label)
    let fileURL = Self.newPreviewURL(label: label)
    previewURL = fileURL

    fileQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.preparePrivateDirectory()
        try bytes.write(to: fileURL, options: [.completeFileProtection])
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.complete],
          ofItemAtPath: fileURL.path
        )
        var fileValues = URLResourceValues()
        fileValues.isExcludedFromBackup = true
        var mutableFileURL = fileURL
        try mutableFileURL.setResourceValues(fileValues)
        DispatchQueue.main.async {
          self.presentPreviewIfCurrent(fileURL, generation: requestGeneration)
        }
      } catch {
        DispatchQueue.main.async {
          self.failOpen(generation: requestGeneration, code: "failed")
        }
      }
    }
  }

  private func preparePrivateDirectory() throws {
    let directory = Self.previewDirectoryURL()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete]
    )
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: directory.path
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableDirectory = directory
    try mutableDirectory.setResourceValues(values)
    try purgeOldPreviews(in: directory)
  }

  private func purgeOldPreviews(in directory: URL) throws {
    let manager = FileManager.default
    let urls = try manager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: []
    )
    let generatedFiles = urls.filter { url in
      guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
            Self.isGeneratedFilenameOrAtomicTemporary(url.lastPathComponent),
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
        return false
      }
      return values.isRegularFile == true && values.isSymbolicLink != true
    }
    for url in generatedFiles.prefix(Self.maximumCleanupEntries) {
      try? manager.removeItem(at: url)
    }
  }

  private func presentPreviewIfCurrent(_ fileURL: URL, generation requestGeneration: UInt64) {
    guard generation == requestGeneration, isBusy, !isClosing else {
      enqueueDelete(fileURL)
      return
    }
    guard UIApplication.shared.applicationState == .active,
          let presenter = Self.topViewController(),
          !presenter.isBeingDismissed,
          !presenter.isBeingPresented,
          presenter.presentedViewController == nil else {
      finishOpen(generation: requestGeneration, errorCode: "unavailable")
      return
    }
    guard QLPreviewController.canPreview(fileURL as NSURL) else {
      finishOpen(generation: requestGeneration, errorCode: "unsupported")
      return
    }

    let controller = QLPreviewController()
    controller.dataSource = self
    controller.delegate = self
    controller.modalPresentationStyle = .formSheet
    if #available(iOS 13.0, *) {
      // Quick Look's Done action owns completion; prevent an adaptive sheet
      // dismissal from bypassing its delegate and leaving the request busy.
      controller.isModalInPresentation = true
    }
    controller.navigationItem.title = previewTitle
    previewController = controller
    presentationInFlight = true
    presenter.present(controller, animated: false) { [weak self, weak controller] in
      guard let self else { return }
      guard let controller, self.previewController === controller else { return }
      self.presentationInFlight = false
      guard self.generation == requestGeneration,
            !self.isClosing,
            UIApplication.shared.applicationState == .active else {
        self.isClosing = true
        self.terminalErrorCode = self.terminalErrorCode ?? "cancelled"
        let errorCode = self.terminalErrorCode
        if controller.presentingViewController != nil {
          controller.dismiss(animated: false) {
            self.finishSession(errorCode: errorCode, dismissedController: controller)
          }
        } else {
          self.finishSession(errorCode: errorCode, dismissedController: controller)
        }
        return
      }
    }
    if controller.presentingViewController == nil {
      presentationInFlight = false
      generation &+= 1
      finishOpen(generation: generation, errorCode: "unavailable")
    }
  }

  private func close(result: @escaping FlutterResult) {
    closeResults.append(result)
    beginClose(errorCode: "cancelled")
  }

  private func closeForLifecycleChange() {
    beginClose(errorCode: "cancelled")
  }

  private func purgePrivateDirectoryWhenActive() {
    guard UIApplication.shared.applicationState == .active,
          !isBusy,
          !cleanupInFlight,
          !isClosing else { return }
    fileQueue.async { [weak self] in
      guard let self else { return }
      try? self.preparePrivateDirectory()
    }
  }

  private func beginClose(errorCode: String) {
    if isClosing || cleanupInFlight { return }
    generation &+= 1
    guard isBusy || previewURL != nil else {
      completeCloseResults()
      return
    }
    isClosing = true
    terminalErrorCode = errorCode
    let controller = previewController
    if presentationInFlight { return }
    if let controller, controller.presentingViewController != nil {
      controller.dismiss(animated: false) { [weak self, weak controller] in
        guard let self else { return }
        self.finishSession(errorCode: errorCode, dismissedController: controller)
      }
    } else {
      finishSession(errorCode: errorCode, dismissedController: controller)
    }
  }

  private func finishOpen(generation requestGeneration: UInt64, errorCode: String) {
    guard generation == requestGeneration else { return }
    if isClosing || cleanupInFlight { return }
    isClosing = true
    terminalErrorCode = errorCode
    if let controller = previewController, controller.presentingViewController != nil {
      controller.dismiss(animated: false) { [weak self, weak controller] in
        self?.finishSession(errorCode: errorCode, dismissedController: controller)
      }
    } else {
      finishSession(errorCode: errorCode, dismissedController: previewController)
    }
  }

  private func finishSession(errorCode: String?, dismissedController: QLPreviewController?) {
    guard !cleanupInFlight else { return }
    guard isBusy || previewURL != nil else {
      completeCloseResults()
      return
    }
    cleanupInFlight = true
    isClosing = true
    let resolvedErrorCode = errorCode ?? terminalErrorCode
    if let dismissedController, previewController === dismissedController {
      previewController = nil
      previewItem = nil
    }
    let url = previewURL
    let openCompletion = openResult
    openResult = nil
    fileQueue.async { [weak self] in
      if let url { self?.deleteGeneratedPreview(url) }
      DispatchQueue.main.async {
        guard let self else { return }
        self.previewURL = nil
        self.previewController = nil
        self.previewItem = nil
        self.previewTitle = "Attachment"
        self.isBusy = false
        self.isClosing = false
        self.cleanupInFlight = false
        self.presentationInFlight = false
        self.terminalErrorCode = nil
        if let resolvedErrorCode {
          openCompletion?(Self.error(resolvedErrorCode))
        } else {
          openCompletion?(nil)
        }
        self.completeCloseResults()
      }
    }
  }

  private func failOpen(generation requestGeneration: UInt64, code: String) {
    guard generation == requestGeneration else { return }
    finishOpen(generation: requestGeneration, errorCode: code)
  }

  private func completeCloseResults() {
    let results = closeResults
    closeResults.removeAll()
    results.forEach { $0(nil) }
  }

  private func enqueueDelete(_ url: URL) {
    fileQueue.async { [weak self] in self?.deleteGeneratedPreview(url) }
  }

  private func deleteGeneratedPreview(_ url: URL) {
    let directory = Self.previewDirectoryURL().standardizedFileURL
    let candidate = url.standardizedFileURL
    guard candidate.deletingLastPathComponent() == directory,
          Self.isGeneratedFilename(candidate.lastPathComponent) else { return }
    try? FileManager.default.removeItem(at: candidate)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    guard previewURL != nil, !isClosing else { return 0 }
    return 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    guard index == 0, let previewURL else {
      return SyncV2PreviewItem(
        url: Self.previewDirectoryURL().appendingPathComponent("\(UUID().uuidString.lowercased()).bin"),
        title: "Attachment"
      )
    }
    let item = SyncV2PreviewItem(url: previewURL, title: previewTitle)
    previewItem = item
    return item
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    guard previewController === controller else { return }
    generation &+= 1
    finishSession(errorCode: terminalErrorCode, dismissedController: controller)
  }

  private static func previewDirectoryURL() -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(directoryName, isDirectory: true)
  }

  private static func newPreviewURL(label: String) -> URL {
    let pieces = label.split(separator: ".", omittingEmptySubsequences: false)
    let candidate = pieces.last.map(String.init) ?? ""
    let suffix = String(candidate.lowercased().filter { character in
      character.isASCII && (character.isLetter || character.isNumber)
    }.prefix(10))
    let fileExtension = suffix.isEmpty ? "bin" : suffix
    return previewDirectoryURL().appendingPathComponent("\(UUID().uuidString.lowercased()).\(fileExtension)")
  }

  private static func displayTitle(_ label: String) -> String {
    var safe = ""
    for scalar in label.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) {
      safe.unicodeScalars.append(scalar)
      if safe.unicodeScalars.count == 120 { break }
    }
    return safe.isEmpty ? "Attachment" : safe
  }

  private static func isGeneratedFilename(_ filename: String) -> Bool {
    let components = filename.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 2,
          UUID(uuidString: String(components[0])) != nil,
          !components[1].isEmpty,
          components[1].count <= 10 else { return false }
    return components[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
  }

  private static func isGeneratedFilenameOrAtomicTemporary(_ filename: String) -> Bool {
    if isGeneratedFilename(filename) { return true }
    return filename.split(separator: ".", omittingEmptySubsequences: true)
      .contains { UUID(uuidString: String($0)) != nil }
  }

  private static func topViewController() -> UIViewController? {
    let window: UIWindow?
    if #available(iOS 13.0, *) {
      window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)
    } else {
      window = UIApplication.shared.keyWindow
    }
    guard let root = window?.rootViewController else { return nil }
    return topViewController(from: root)
  }

  private static func topViewController(from controller: UIViewController) -> UIViewController {
    if let presented = controller.presentedViewController, !presented.isBeingDismissed {
      return topViewController(from: presented)
    }
    if let navigation = controller as? UINavigationController,
       let visible = navigation.visibleViewController {
      return topViewController(from: visible)
    }
    if let tabs = controller as? UITabBarController, let selected = tabs.selectedViewController {
      return topViewController(from: selected)
    }
    if let split = controller as? UISplitViewController, let last = split.viewControllers.last {
      return topViewController(from: last)
    }
    return controller
  }

  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }
}
