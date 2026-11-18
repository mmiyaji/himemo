import UIKit
import Flutter
import CloudKit
import Network
import CoreSpotlight
import MobileCoreServices
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let widgetChannelName = "org.ruhenheim.himemo/widget"
  private let cloudKitChannelName = "org.ruhenheim.himemo/cloudkit"
  private let privacyChannelName = "org.ruhenheim.himemo/privacy"
  private let networkChannelName = "org.ruhenheim.himemo/network"
  private let spotlightChannelName = "org.ruhenheim.himemo/spotlight"
  private let intelligenceChannelName = "org.ruhenheim.himemo/intelligence"
  private let spotlightDomainIdentifier = "org.ruhenheim.himemo.notes.standard"
  private let quickCaptureUrl = "himemo://widget-capture"
  private let appGroupIdentifier = "group.org.ruhenheim.himemo"
  private let pendingQuickCaptureFileName = "pending_quick_capture.json"
  private let cloudKitContainerIdentifier = "iCloud.org.ruhenheim.himemo"

  private var widgetChannel: FlutterMethodChannel?
  private var cloudKitChannel: FlutterMethodChannel?
  private var privacyChannel: FlutterMethodChannel?
  private var networkChannel: FlutterMethodChannel?
  private var spotlightChannel: FlutterMethodChannel?
  private var intelligenceChannel: FlutterMethodChannel?
  private var syncV2AttachmentViewer: SyncV2AttachmentViewer?
  private var pendingQuickCapturePayload: [String: Any]?
  private var pendingSpotlightNoteId: String?
  private var privacyProtectionEnabled = false
  private var privacyOverlayView: UIView?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    SyncV2BiometricKeyStore.register(with: messenger)
    syncV2AttachmentViewer = SyncV2AttachmentViewer(messenger: messenger)
    widgetChannel = FlutterMethodChannel(
      name: widgetChannelName,
      binaryMessenger: messenger
    )
    cloudKitChannel = FlutterMethodChannel(
      name: cloudKitChannelName,
      binaryMessenger: messenger
    )
    privacyChannel = FlutterMethodChannel(
      name: privacyChannelName,
      binaryMessenger: messenger
    )
    networkChannel = FlutterMethodChannel(
      name: networkChannelName,
      binaryMessenger: messenger
    )
    spotlightChannel = FlutterMethodChannel(
      name: spotlightChannelName,
      binaryMessenger: messenger
    )
    intelligenceChannel = FlutterMethodChannel(
      name: intelligenceChannelName,
      binaryMessenger: messenger
    )

    widgetChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "consumePendingQuickCapture":
        let pending = self.pendingQuickCapturePayload ?? self.readPendingQuickCapturePayload()
        self.pendingQuickCapturePayload = nil
        result(pending ?? false)
      case "acknowledgeSharedCapture":
        guard let id = call.arguments as? String, UUID(uuidString: id) != nil else {
          result(FlutterError(code: "invalid_share_id", message: nil, details: nil))
          return
        }
        do {
          try self.acknowledgeSharedCapture(id)
          result(nil)
        } catch {
          result(FlutterError(code: "share_ack_failed", message: nil, details: nil))
        }
      case "deleteSharedImportFiles":
        let args = call.arguments as? [String: Any]
        let paths = args?["paths"] as? [String] ?? []
        for path in paths {
          let url = URL(fileURLWithPath: path)
          if self.isSharedImportFile(url) {
            try? FileManager.default.removeItem(at: url)
          }
        }
        result(nil)
      case "appGroupStorageDiagnostics":
        result(self.appGroupStorageDiagnostics())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    cloudKitChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleCloudKitMethod(call: call, result: result)
    }

    privacyChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handlePrivacyMethod(call: call, result: result)
    }

    networkChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result("unknown")
        return
      }
      self.handleNetworkMethod(call: call, result: result)
    }

    spotlightChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleSpotlightMethod(call: call, result: result)
    }

    intelligenceChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleIntelligenceMethod(call: call, result: result)
    }
  }

  // UI state and launch events belong to the scene on iOS 27.
  fileprivate weak var sceneWindow: UIWindow?

  fileprivate func handleSceneURL(_ url: URL) -> Bool {
    handleQuickCaptureURL(url) || handleSpotlightURL(url)
  }

  fileprivate func handleSceneActivity(_ activity: NSUserActivity) -> Bool {
    handleSpotlightUserActivity(activity)
  }

  fileprivate func sceneActiveChanged(_ active: Bool) {
    setPrivacyOverlayVisible(!active && privacyProtectionEnabled)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if handleQuickCaptureURL(url) {
      return true
    }
    if handleSpotlightURL(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if handleSpotlightUserActivity(userActivity) {
      return true
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  private func handlePrivacyMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setProtected":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      DispatchQueue.main.async {
        self.setPrivacyProtectionEnabled(enabled)
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleNetworkMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "currentConnectionKind":
      currentConnectionKind(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleIntelligenceMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "suggestTags":
      let args = call.arguments as? [String: Any] ?? [:]
#if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        suggestTagsWithFoundationModels(arguments: args, result: result)
      } else {
        result(appleIntelligenceUnavailable("Foundation Models requires iOS 26 or later."))
      }
#else
      result(appleIntelligenceUnavailable("Foundation Models is not available in this build."))
#endif
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func appleIntelligenceUnavailable(_ message: String) -> FlutterError {
    FlutterError(
      code: "apple_intelligence_unavailable",
      message: message,
      details: nil
    )
  }

#if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private func suggestTagsWithFoundationModels(
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    Task {
      do {
        let tags = try await generateFoundationModelTags(arguments: arguments)
        DispatchQueue.main.async {
          result([
            "tags": tags,
            "source": "apple_intelligence",
            "usedAppleIntelligence": true
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "apple_intelligence_unavailable",
            message: "\(error)",
            details: nil
          ))
        }
      }
    }
  }

  @available(iOS 26.0, *)
  private func generateFoundationModelTags(arguments: [String: Any]) async throws -> [String] {
    let title = arguments["title"] as? String ?? ""
    let body = arguments["body"] as? String ?? ""
    let existingTags = arguments["existingTags"] as? [String] ?? []
    let knownTags = arguments["knownTags"] as? [String] ?? []
    let attachmentLabels = arguments["attachmentLabels"] as? [String] ?? []
    let preferredLanguageCode = arguments["preferredLanguageCode"] as? String ?? ""
    let preferredLanguage = preferredTagLanguage(
      code: preferredLanguageCode,
      title: title,
      body: body
    )

    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
      throw NSError(
        domain: "HiMemoAppleIntelligence",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence is not available: \(model.availability)"]
      )
    }

    let instructions = """
    You suggest concise memo tags. Infer topics from context instead of copying arbitrary words.
    Return tags in \(preferredLanguage). Do not translate them to English unless the memo itself mainly uses English.
    Prefer existing or known tags when they fit the context. Return only tags that are useful for future filtering.
    Do not include tags already present in the memo.
    Return plain JSON only. Do not wrap the response in markdown fences.
    """
    let session = LanguageModelSession(model: model, instructions: instructions)
    let prompt = """
    Suggest up to 5 short tags for this memo.
    Return a JSON array of strings only, with no markdown and no explanation.
    Output language:
    \(preferredLanguage)

    Existing tags:
    \(existingTags.joined(separator: ", "))

    Known tags that may be reused when relevant:
    \(knownTags.prefix(80).joined(separator: ", "))

    Attachment labels:
    \(attachmentLabels.prefix(20).joined(separator: ", "))

    Title:
    \(title)

    Body:
    \(body.prefix(4000))
    """
    let response = try await session.respond(to: prompt)
    return sanitizeFoundationModelTags(
      rawText: response.content,
      existingTags: existingTags
    )
  }

  private func sanitizeFoundationModelTags(rawText: String, existingTags: [String]) -> [String] {
    let existing = Set(existingTags.map { canonicalTag($0) }.filter { !$0.isEmpty })
    var rawTags: [String] = []
    let jsonText = extractJsonArrayText(from: rawText) ?? rawText
    if let data = jsonText.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] {
      rawTags = decoded.compactMap { $0 as? String }
    } else {
      rawTags = rawText
        .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "```", with: "")
        .replacingOccurrences(of: "[", with: "")
        .replacingOccurrences(of: "]", with: "")
        .replacingOccurrences(of: "\"", with: "")
        .components(separatedBy: CharacterSet(charactersIn: ",\n"))
    }

    var seen = Set<String>()
    var tags: [String] = []
    for raw in rawTags {
      let tag = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-*0123456789.) "))
      let canonical = canonicalTag(tag)
      if tag.isEmpty ||
          canonical.isEmpty ||
          existing.contains(canonical) ||
          isInvalidModelTag(tag, canonical: canonical) ||
          !seen.insert(canonical).inserted {
        continue
      }
      tags.append(String(tag.prefix(24)))
      if tags.count >= 5 {
        break
      }
    }
    return tags
  }

  private func extractJsonArrayText(from rawText: String) -> String? {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
      return trimmed
    }
    guard let start = trimmed.firstIndex(of: "["),
          let end = trimmed.lastIndex(of: "]"),
          start < end else {
      return nil
    }
    return String(trimmed[start...end])
  }

  private func isInvalidModelTag(_ tag: String, canonical: String) -> Bool {
    let rejected: Set<String> = ["json", "```", "```json", "tags", "tag", "null", "none"]
    if rejected.contains(canonical) {
      return true
    }
    if tag.hasPrefix("{") || tag.hasSuffix("}") || tag.contains("```") {
      return true
    }
    return false
  }

  private func preferredTagLanguage(code: String, title: String, body: String) -> String {
    if code == "ja" || containsJapaneseKana(title) || containsJapaneseKana(body) {
      return "Japanese"
    }
    switch code {
    case "zh":
      return "Chinese"
    case "ko":
      return "Korean"
    case "es":
      return "Spanish"
    case "de":
      return "German"
    default:
      return "the primary language of the memo"
    }
  }

  private func containsJapaneseKana(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
      if (0x3040...0x30ff).contains(Int(scalar.value)) {
        return true
      }
    }
    return false
  }

  private func canonicalTag(_ tag: String) -> String {
    tag
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "#", with: "")
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
  }
#endif

  private func handleSpotlightMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "replaceAllNotes":
      let args = call.arguments as? [String: Any]
      let items = args?["items"] as? [[String: Any]] ?? []
      replaceSpotlightNotes(items: items, result: result)
    case "indexNotes":
      let args = call.arguments as? [String: Any]
      let items = args?["items"] as? [[String: Any]] ?? []
      indexSpotlightNotes(items: items, result: result)
    case "deleteNotes":
      let args = call.arguments as? [String: Any]
      let ids = args?["ids"] as? [String] ?? []
      deleteSpotlightNotes(ids: ids, result: result)
    case "clearNotes":
      clearSpotlightNotes(result: result)
    case "consumePendingSpotlightNote":
      let noteId = pendingSpotlightNoteId
      pendingSpotlightNoteId = nil
      result(noteId ?? false)
    case "clearPendingSpotlightNote":
      pendingSpotlightNoteId = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func replaceSpotlightNotes(items: [[String: Any]], result: @escaping FlutterResult) {
    CSSearchableIndex.default().deleteSearchableItems(
      withDomainIdentifiers: [spotlightDomainIdentifier]
    ) { [weak self] error in
      guard let self else {
        result(nil)
        return
      }
      if let error {
        result(FlutterError(
          code: "spotlight_clear_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      self.indexSpotlightNotes(items: items, result: result)
    }
  }

  private func indexSpotlightNotes(items: [[String: Any]], result: @escaping FlutterResult) {
    guard CSSearchableIndex.isIndexingAvailable() else {
      result([
        "indexedCount": 0,
        "indexingAvailable": false
      ])
      return
    }
    let searchableItems = items.compactMap { spotlightSearchableItem(from: $0) }
    if searchableItems.isEmpty {
      result([
        "indexedCount": 0,
        "indexingAvailable": true
      ])
      return
    }
    CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
      if let error {
        result(FlutterError(
          code: "spotlight_index_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      result([
        "indexedCount": searchableItems.count,
        "indexingAvailable": true
      ])
    }
  }

  private func deleteSpotlightNotes(ids: [String], result: @escaping FlutterResult) {
    let identifiers = ids
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if identifiers.isEmpty {
      result(nil)
      return
    }
    CSSearchableIndex.default().deleteSearchableItems(
      withIdentifiers: identifiers
    ) { error in
      if let error {
        result(FlutterError(
          code: "spotlight_delete_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      result([
        "deletedCount": identifiers.count
      ])
    }
  }

  private func clearSpotlightNotes(result: @escaping FlutterResult) {
    CSSearchableIndex.default().deleteSearchableItems(
      withDomainIdentifiers: [spotlightDomainIdentifier]
    ) { error in
      if let error {
        result(FlutterError(
          code: "spotlight_clear_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      result([
        "clearedDomain": self.spotlightDomainIdentifier
      ])
    }
  }

  private func spotlightSearchableItem(from payload: [String: Any]) -> CSSearchableItem? {
    guard let id = payload["id"] as? String, !id.isEmpty else {
      return nil
    }
    let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = (payload["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let tags = payload["tags"] as? [String] ?? []
    let searchTerms = payload["searchTerms"] as? [String] ?? []
    let resolvedTitle = title?.isEmpty == false ? title! : "HiMemo"
    let searchableText = [
      resolvedTitle,
      body ?? "",
      tags.joined(separator: " "),
      searchTerms.joined(separator: " "),
      "HiMemo"
    ]
      .compactMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
      .joined(separator: "\n\n")
    let attributeSet = CSSearchableItemAttributeSet(itemContentType: kUTTypeText as String)
    attributeSet.title = resolvedTitle
    attributeSet.displayName = resolvedTitle
    attributeSet.textContent = searchableText
    attributeSet.contentDescription = [body, tags.joined(separator: " ")]
      .compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
      }
      .joined(separator: "\n\n")
    var seenKeywords = Set<String>()
    attributeSet.keywords = (["HiMemo"] + tags + searchTerms).compactMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return nil
      }
      let normalized = trimmed.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
      )
      guard seenKeywords.insert(normalized).inserted else {
        return nil
      }
      return trimmed
    }
    attributeSet.kind = "HiMemo Note"
    attributeSet.contentCreationDate = dateFromIsoString(payload["createdAt"] as? String)
    attributeSet.contentModificationDate = dateFromIsoString(payload["updatedAt"] as? String)
    if let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let url = URL(string: "himemo://note?id=\(encodedId)") {
      attributeSet.contentURL = url
    }

    let item = CSSearchableItem(
      uniqueIdentifier: id,
      domainIdentifier: spotlightDomainIdentifier,
      attributeSet: attributeSet
    )
    item.expirationDate = Date.distantFuture
    return item
  }

  private func dateFromIsoString(_ value: String?) -> Date? {
    guard let value else {
      return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
      return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private func currentConnectionKind(result: @escaping FlutterResult) {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "org.ruhenheim.himemo.network-kind")
    let completionQueue = DispatchQueue(label: "org.ruhenheim.himemo.network-kind-completion")
    var completed = false

    func complete(_ kind: String) {
      completionQueue.async {
        if completed {
          return
        }
        completed = true
        monitor.cancel()
        DispatchQueue.main.async {
          result(kind)
        }
      }
    }

    monitor.pathUpdateHandler = { path in
      let kind: String
      if path.status != .satisfied {
        kind = "none"
      } else if path.usesInterfaceType(.cellular) || path.isExpensive {
        kind = "mobile"
      } else if path.usesInterfaceType(.wifi) {
        kind = "wifi"
      } else if path.usesInterfaceType(.wiredEthernet) {
        kind = "ethernet"
      } else {
        kind = "other"
      }
      complete(kind)
    }
    monitor.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 0.8) {
      complete("unknown")
    }
  }

  private func setPrivacyProtectionEnabled(_ enabled: Bool) {
    privacyProtectionEnabled = enabled
    if !enabled {
      setPrivacyOverlayVisible(false)
    }
  }

  private func setPrivacyOverlayVisible(_ visible: Bool) {
    guard let window = sceneWindow else {
      return
    }
    if visible {
      if privacyOverlayView == nil {
        let overlay = UIView(frame: window.bounds)
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = UIColor(
          red: 0.992,
          green: 0.988,
          blue: 1.0,
          alpha: 1.0
        )

        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.image = UIImage(
          named: FlutterDartProject.lookupKey(forAsset: "assets/app-icon.png")
        )
        overlay.addSubview(icon)
        NSLayoutConstraint.activate([
          icon.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
          icon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
          icon.widthAnchor.constraint(equalToConstant: 152),
          icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
        ])

        privacyOverlayView = overlay
      }
      guard let privacyOverlayView else {
        return
      }
      if privacyOverlayView.superview == nil {
        window.addSubview(privacyOverlayView)
      }
      window.bringSubviewToFront(privacyOverlayView)
    } else {
      privacyOverlayView?.removeFromSuperview()
    }
  }

  private func handleQuickCaptureURL(_ url: URL) -> Bool {
    if url.isFileURL {
      guard let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      ) else {
        return false
      }
      let entry = container.appendingPathComponent("pending_shares", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      guard let file = copySharedFile(url, into: entry) else { return false }
      do {
        let data = try JSONSerialization.data(withJSONObject: ["text": "", "files": [file]])
        try data.write(
          to: entry.appendingPathComponent("manifest.json"),
          options: [.atomic, .completeFileProtection]
        )
      } catch {
        try? FileManager.default.removeItem(at: entry)
        return false
      }
      if let payload = readPendingQuickCapturePayload() { openQuickCapture(payload: payload) }
      return true
    }

    guard url.absoluteString == quickCaptureUrl else {
      return false
    }
    openQuickCapture(payload: readPendingQuickCapturePayload() ?? [
      "source": "widget",
      "text": "",
      "files": []
    ])
    return true
  }

  private func handleSpotlightUserActivity(_ userActivity: NSUserActivity) -> Bool {
    guard userActivity.activityType == CSSearchableItemActionType else {
      return false
    }
    if let noteId = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
       !noteId.isEmpty {
      openSpotlightNote(noteId: noteId)
      return true
    }
    if let url = userActivity.webpageURL ?? userActivity.referrerURL,
       handleSpotlightURL(url) {
      return true
    }
    return false
  }

  private func handleSpotlightURL(_ url: URL) -> Bool {
    guard url.scheme == "himemo", url.host == "note" else {
      return false
    }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryNoteId = components?.queryItems?.first(where: { $0.name == "id" })?.value
    let pathNoteId = url.pathComponents.dropFirst().first
    let noteId = (queryNoteId ?? pathNoteId ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !noteId.isEmpty else {
      return false
    }
    openSpotlightNote(noteId: noteId)
    return true
  }

  private func openSpotlightNote(noteId: String) {
    pendingSpotlightNoteId = noteId
    if spotlightChannel != nil {
      spotlightChannel?.invokeMethod("openSpotlightNote", arguments: [
        "noteId": noteId
      ])
    }
  }

  private func openQuickCapture(payload: [String: Any]) {
    if widgetChannel != nil {
      widgetChannel?.invokeMethod("openQuickCapture", arguments: payload)
    } else {
      pendingQuickCapturePayload = payload
    }
  }

  private func copySharedFile(_ sourceURL: URL, into directory: URL) -> [String: String]? {
    let startedAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if startedAccess {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let mimeType = mimeTypeForSharedFile(sourceURL)
    guard isSupportedSharedMimeType(mimeType) else {
      return nil
    }

    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let destination = directory.appendingPathComponent(
        "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
      )
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: sourceURL, to: destination)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path
      )
      return [
        "relativePath": destination.lastPathComponent,
        "name": sourceURL.lastPathComponent,
        "mimeType": mimeType
      ]
    } catch {
      try? FileManager.default.removeItem(at: directory)
      return nil
    }
  }

  private func mimeTypeForSharedFile(_ url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "gif":
      return "image/gif"
    case "heic":
      return "image/heic"
    case "heif":
      return "image/heif"
    case "mp4":
      return "video/mp4"
    case "mov":
      return "video/quicktime"
    case "m4v":
      return "video/x-m4v"
    case "mp3":
      return "audio/mpeg"
    case "m4a":
      return "audio/mp4"
    case "wav":
      return "audio/wav"
    case "aac":
      return "audio/aac"
    case "caf":
      return "audio/x-caf"
    case "aif", "aiff":
      return "audio/aiff"
    case "flac":
      return "audio/flac"
    case "ogg":
      return "audio/ogg"
    default:
      return "application/octet-stream"
    }
  }

  private func isSupportedSharedMimeType(_ mimeType: String) -> Bool {
    let normalized = mimeType.lowercased()
    return normalized.hasPrefix("image/") ||
      normalized.hasPrefix("video/") ||
      normalized.hasPrefix("audio/")
  }

  private func isSharedImportFile(_ url: URL) -> Bool {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("shared_imports", isDirectory: true)
    if url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path) {
      return true
    }
    guard let appGroupDirectory = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )?.appendingPathComponent("shared_imports", isDirectory: true) else {
      return false
    }
    return url.resolvingSymlinksInPath().standardizedFileURL.path
      .hasPrefix(appGroupDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/")
  }

  private func readPendingQuickCapturePayload() -> [String: Any]? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    let manager = FileManager.default
    let queue = container.appendingPathComponent("pending_shares", isDirectory: true)
    let legacy = container.appendingPathComponent(pendingQuickCaptureFileName)
    if manager.fileExists(atPath: legacy.path) {
      let entry = queue.appendingPathComponent(UUID().uuidString, isDirectory: true)
      do {
        try manager.createDirectory(at: entry, withIntermediateDirectories: true)
        try manager.moveItem(at: legacy, to: entry.appendingPathComponent("manifest.json"))
      } catch {
        // Leave the legacy manifest in place if migration could not finish.
      }
    }
    let entries = (try? manager.contentsOfDirectory(
      at: queue, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )) ?? []
    let manifests = entries.compactMap { entry -> (String, URL, Date)? in
      let id = entry.lastPathComponent
      guard UUID(uuidString: id) != nil else { return nil }
      let url = entry.appendingPathComponent("manifest.json")
      guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate else { return nil }
      return (id, url, date)
    }.sorted { left, right in
      left.2 == right.2 ? left.0 < right.0 : left.2 < right.2
    }
    for (id, url, _) in manifests {
      guard let data = try? Data(contentsOf: url),
            var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      payload["source"] = "share"
      payload["nonce"] = id
      payload["shareId"] = id
      if let files = payload["files"] as? [[String: Any]] {
        payload["files"] = files.map { file in
          var resolved = file
          if let path = file["path"] as? String {
            resolved["path"] = legacySharedImportURL(path, in: container).path
          }
          guard let name = file["relativePath"] as? String,
                !name.isEmpty, name != ".", name != "..", !name.contains("/")
          else { return resolved }
          resolved["path"] = url.deletingLastPathComponent().appendingPathComponent(name).path
          return resolved
        }
      }
      return payload
    }
    return nil
  }

  private func acknowledgeSharedCapture(_ id: String) throws {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else { throw CocoaError(.fileNoSuchFile) }
    let entry = container.appendingPathComponent("pending_shares", isDirectory: true)
      .appendingPathComponent(id, isDirectory: true)
    let manifest = entry.appendingPathComponent("manifest.json")
    let manager = FileManager.default
    guard manager.fileExists(atPath: manifest.path) else { return }
    // Migrated manifests can still reference the old shared_imports directory.
    if let data = try? Data(contentsOf: manifest),
       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let files = payload["files"] as? [[String: Any]] {
      for file in files {
        guard let path = file["path"] as? String else { continue }
        let url = legacySharedImportURL(path, in: container)
        if isSharedImportFile(url) { try? manager.removeItem(at: url) }
      }
    }
    try manager.removeItem(at: entry)
  }

  private func legacySharedImportURL(_ path: String, in container: URL) -> URL {
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) ||
       url.deletingLastPathComponent().lastPathComponent != "shared_imports" {
      return url
    }
    return container.appendingPathComponent("shared_imports", isDirectory: true)
      .appendingPathComponent(url.lastPathComponent)
  }

  private func appGroupStorageDiagnostics() -> [String: Any] {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return [
        "appGroupBytes": 0,
        "appGroupSharedImportsBytes": 0,
        "appGroupPendingQuickCaptureBytes": 0,
      ]
    }
    let sharedImports = container.appendingPathComponent(
      "shared_imports",
      isDirectory: true
    )
    let pendingQuickCapture = container.appendingPathComponent(
      pendingQuickCaptureFileName,
      isDirectory: false
    )
    return [
      "appGroupBytes": Int(directorySizeBytes(container)),
      "appGroupSharedImportsBytes": Int(directorySizeBytes(sharedImports)),
      "appGroupPendingQuickCaptureBytes": Int(fileSizeBytes(pendingQuickCapture)
        + directorySizeBytes(container.appendingPathComponent("pending_shares", isDirectory: true))),
    ]
  }

  private func directorySizeBytes(_ url: URL) -> Int64 {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      return fileSizeBytes(url)
    }
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles],
      errorHandler: { _, _ in true }
    ) else {
      return 0
    }
    var total: Int64 = 0
    for case let fileUrl as URL in enumerator {
      guard
        let values = try? fileUrl.resourceValues(
          forKeys: [.isRegularFileKey, .fileSizeKey]
        ),
        values.isRegularFile == true
      else {
        continue
      }
      total += Int64(values.fileSize ?? 0)
    }
    return total
  }

  private func fileSizeBytes(_ url: URL) -> Int64 {
    guard
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
      values.isRegularFile == true
    else {
      return 0
    }
    return Int64(values.fileSize ?? 0)
  }

  private func handleCloudKitMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "cloudKitV2AccountId", "cloudKitV2Prepare", "cloudKitV2FetchHeaders", "cloudKitV2FetchHeader",
         "cloudKitV2FetchPayload", "cloudKitV2Publish":
      guard #available(iOS 15.0, *) else {
        result(FlutterError(code: "cloudkit_v2_unsupported", message: "Sync v2 requires iOS 15.", details: nil))
        return
      }
      handleCloudKitV2Method(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 15.0, *)
  private func handleCloudKitV2Method(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let container = makeCloudKitContainer() else {
      result(cloudKitConfigurationError())
      return
    }
    Task { @MainActor in
      do {
        let account = try await container.userRecordID().recordName
        if call.method == "cloudKitV2AccountId" {
          result(account)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let enrolled = args["accountId"] as? String,
              let generation = args["generationId"] as? String,
              self.isCloudKitV2Identifier(generation) else {
          throw CloudKitV2Error.invalidRequest
        }
        guard enrolled == account else { throw CloudKitV2Error.accountChanged }
        let database = container.privateCloudDatabase
        let zone = CKRecordZone.ID(
          zoneName: "HiMemoSyncV2-\(generation)",
          ownerName: CKCurrentUserDefaultName
        )
        let response: Any?
        switch call.method {
        case "cloudKitV2Prepare":
          _ = try await database.save(CKRecordZone(zoneID: zone))
          response = nil
        case "cloudKitV2FetchHeaders":
          response = try await self.fetchCloudKitV2Headers(database, zone: zone, args: args)
        case "cloudKitV2FetchHeader", "cloudKitV2FetchPayload", "cloudKitV2Publish":
          guard let name = args["id"] as? String, self.isCloudKitV2Identifier(name) else {
            throw CloudKitV2Error.invalidRequest
          }
          let id = CKRecord.ID(recordName: name, zoneID: zone)
          if call.method == "cloudKitV2FetchHeader" {
            let records = try await database.records(
              for: [id], desiredKeys: [Self.syncV2HeaderField]
            )
            guard let fetched = records[id] else { throw CloudKitV2Error.invalidRecord }
            let record = try fetched.get()
            guard record.recordType == Self.syncV2RecordType,
                  let header = record[Self.syncV2HeaderField] as? String,
                  !header.isEmpty else { throw CloudKitV2Error.invalidRecord }
            response = header
          } else if call.method == "cloudKitV2FetchPayload" {
            let record = try await database.record(for: id)
            guard let payload = try self.cloudKitV2Payload(record) else {
              throw CloudKitV2Error.invalidRecord
            }
            response = FlutterStandardTypedData(bytes: payload)
          } else {
            try await self.publishCloudKitV2(database, id: id, args: args)
            response = nil
          }
        default:
          result(FlutterMethodNotImplemented)
          return
        }
        guard try await container.userRecordID().recordName == enrolled else {
          throw CloudKitV2Error.accountChanged
        }
        result(response)
      } catch let error as CloudKitV2Error {
        result(FlutterError(code: "cloudkit_v2_\(error.rawValue)", message: nil, details: nil))
      } catch let error as CKError where error.code == .partialFailure {
        if let partialErrors = error.partialErrorsByItemID,
           partialErrors.count == 1,
           let itemError = partialErrors.values.first as? CKError {
          if itemError.code == .changeTokenExpired {
            result(FlutterError(code: "cloudkit_v2_cursor_expired", message: nil, details: nil))
          } else {
            result(self.flutterError(from: itemError))
          }
        } else {
          result(self.flutterError(from: error))
        }
      } catch let error as CKError where error.code == .changeTokenExpired {
        result(FlutterError(code: "cloudkit_v2_cursor_expired", message: nil, details: nil))
      } catch {
        result(self.flutterError(from: error))
      }
    }
  }

  private enum CloudKitV2Error: String, Error {
    case invalidRequest, invalidRecord, accountChanged, recordCollision
  }

  private static let syncV2RecordType = "HiMemoSyncV2Change"
  private static let syncV2HeaderField = "encryptedHeader"
  private static let syncV2PayloadField = "encryptedPayload"
  private static let syncV2PayloadLimit = 16 * 1024 * 1024

  private func isCloudKitV2Identifier(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 80 &&
      value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) ||
        (97...122).contains($0) || $0 == 45 || $0 == 95 }
  }

  @available(iOS 15.0, *)
  private func fetchCloudKitV2Headers(
    _ database: CKDatabase, zone: CKRecordZone.ID, args: [String: Any]
  ) async throws -> [String: Any] {
    guard let limit = args["limit"] as? Int, (1...200).contains(limit) else {
      throw CloudKitV2Error.invalidRequest
    }
    var token: CKServerChangeToken?
    if let cursor = args["cursor"] {
      guard let encoded = cursor as? String, let data = Data(base64Encoded: encoded),
            let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) else {
        throw CloudKitV2Error.invalidRequest
      }
      token = decoded
    }
    let page = try await database.recordZoneChanges(
      inZoneWith: zone,
      since: token,
      desiredKeys: [Self.syncV2HeaderField],
      resultsLimit: limit
    )
    var headers: [[String: String]] = []
    var issues = page.deletions.map { deletion in
      ["id": deletion.recordID.recordName, "reason": "remote_deleted"]
    }
    for (id, modification) in page.modificationResultsByID {
      let record: CKRecord
      do {
        record = try modification.get().record
      } catch {
        issues.append(["id": id.recordName, "reason": "record_unavailable"])
        continue
      }
      guard record.recordType == Self.syncV2RecordType,
            let header = record[Self.syncV2HeaderField] as? String,
            !header.isEmpty else {
        issues.append(["id": id.recordName, "reason": "invalid_record"])
        continue
      }
      headers.append(["id": id.recordName, "header": header])
    }
    let cursor = try NSKeyedArchiver.archivedData(
      withRootObject: page.changeToken, requiringSecureCoding: true
    ).base64EncodedString()
    return ["cursor": cursor, "hasMore": page.moreComing, "headers": headers, "issues": issues]
  }

  private func cloudKitV2Payload(_ record: CKRecord) throws -> Data? {
    guard record.recordType == Self.syncV2RecordType else { throw CloudKitV2Error.invalidRecord }
    guard let field = record[Self.syncV2PayloadField] else { return nil }
    guard let asset = field as? CKAsset, let url = asset.fileURL,
          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          (1...Self.syncV2PayloadLimit).contains(size) else {
      throw CloudKitV2Error.invalidRecord
    }
    return try Data(contentsOf: url)
  }

  @available(iOS 15.0, *)
  private func publishCloudKitV2(
    _ database: CKDatabase, id: CKRecord.ID, args: [String: Any]
  ) async throws {
    guard let header = args["header"] as? String, (1...65536).contains(header.utf8.count) else {
      throw CloudKitV2Error.invalidRequest
    }
    let payload = (args["payload"] as? FlutterStandardTypedData)?.data
    if args["payload"] != nil &&
        (payload.map { (1...Self.syncV2PayloadLimit).contains($0.count) } != true) {
      throw CloudKitV2Error.invalidRequest
    }
    let record = CKRecord(recordType: Self.syncV2RecordType, recordID: id)
    record[Self.syncV2HeaderField] = header as CKRecordValue
    var temporaryURL: URL?
    defer {
      if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
    }
    if let payload {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      temporaryURL = url
      try payload.write(to: url, options: [.atomic])
      record[Self.syncV2PayloadField] = CKAsset(fileURL: url)
    }
    do {
      let outcome = try await database.modifyRecords(saving: [record], deleting: [])
      guard let saved = outcome.saveResults[id] else { throw CloudKitV2Error.invalidRecord }
      _ = try saved.get()
    } catch {
      guard let existing = try? await database.record(for: id) else { throw error }
      let storedPayload = try cloudKitV2Payload(existing)
      guard existing[Self.syncV2HeaderField] as? String == header,
            storedPayload == payload else { throw CloudKitV2Error.recordCollision }
    }
  }

  private func makeCloudKitContainer() -> CKContainer? {
    if appHasCloudKitConfiguration() == false {
      return nil
    }
    return CKContainer(identifier: cloudKitContainerIdentifier)
  }

  private func appHasCloudKitConfiguration() -> Bool {
    if let profileStatus = embeddedProvisioningProfileRequiresCloudKitConfiguration() {
      return profileStatus
    }
    return true
  }

  private func embeddedProvisioningProfileRequiresCloudKitConfiguration() -> Bool? {
    guard
      let profileURL = Bundle.main.url(
        forResource: "embedded",
        withExtension: "mobileprovision"
      ),
      let profileData = try? Data(contentsOf: profileURL),
      let profileText = String(data: profileData, encoding: .isoLatin1),
      let plistStart = profileText.range(of: "<?xml"),
      let plistEnd = profileText.range(of: "</plist>")
    else {
      return nil
    }
    let plistRange = plistStart.lowerBound..<plistEnd.upperBound
    let plistString = String(profileText[plistRange])
    guard
      let plistData = plistString.data(using: .utf8),
      let plist = try? PropertyListSerialization.propertyList(
        from: plistData,
        options: [],
        format: nil
      ) as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any],
      let services = entitlements["com.apple.developer.icloud-services"] as? [String],
      let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String]
    else {
      return false
    }
    return services.contains("CloudKit") &&
      containers.contains(cloudKitContainerIdentifier)
  }

  private func cloudKitConfigurationError() -> FlutterError {
    FlutterError(
      code: "missingEntitlement",
      message: "This build is missing the CloudKit entitlement or container configuration.",
      details: ["message": "This build is missing the CloudKit entitlement or container configuration."]
    )
  }

  private func flutterError(from error: Error) -> FlutterError {
    guard let cloudError = error as? CKError else {
      return FlutterError(
        code: "unknown",
        message: error.localizedDescription,
        details: ["message": error.localizedDescription]
      )
    }

    let message: String
    switch cloudError.code {
    case .quotaExceeded:
      message = "The user's iCloud storage is full. Ask them to manage iCloud storage in Settings."
    case .networkUnavailable:
      message = "The network is unavailable. Connect to the internet and try iCloud sync again."
    case .networkFailure, .serviceUnavailable, .zoneBusy, .requestRateLimited, .serverResponseLost:
      message = "CloudKit is temporarily unavailable. Retry iCloud sync in a moment."
    case .notAuthenticated:
      message = "This device is not authenticated for iCloud. Sign in to iCloud in Settings."
    case .permissionFailure, .managedAccountRestricted:
      message = "This device is not allowed to access the iCloud container."
    case .missingEntitlement, .badContainer:
      message = "This build is missing the CloudKit entitlement or container configuration."
    case .unknownItem:
      message = "The requested iCloud bundle could not be found."
    case .limitExceeded:
      message = "The encrypted bundle is too large for a single CloudKit save. Reduce attachment size and try again."
    case .accountTemporarilyUnavailable:
      message = "The user's iCloud account is temporarily unavailable. Try again later."
    default:
      message = cloudError.localizedDescription
    }

    var details: [String: Any] = ["message": message]
    if let retryAfter = cloudError.retryAfterSeconds {
      details["retryAfterSeconds"] = retryAfter
    }
    details["code"] = cloudError.code.rawValue

    return FlutterError(
      code: "\(cloudError.code.rawValue)",
      message: message,
      details: details
    )
  }
}

// Included by the existing Runner Sources build phase with AppDelegate.swift.
@objc class SceneDelegate: FlutterSceneDelegate {
  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    appDelegate?.sceneWindow = window
    for context in connectionOptions.urlContexts {
      _ = appDelegate?.handleSceneURL(context.url)
    }
    for activity in connectionOptions.userActivities {
      _ = appDelegate?.handleSceneActivity(activity)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let remaining = URLContexts.filter { appDelegate?.handleSceneURL($0.url) != true }
    if !remaining.isEmpty {
      super.scene(scene, openURLContexts: Set(remaining))
    }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if appDelegate?.handleSceneActivity(userActivity) != true {
      super.scene(scene, continue: userActivity)
    }
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    appDelegate?.sceneActiveChanged(false)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    appDelegate?.sceneActiveChanged(false)
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    appDelegate?.sceneWindow = window
    appDelegate?.sceneActiveChanged(true)
  }
}
