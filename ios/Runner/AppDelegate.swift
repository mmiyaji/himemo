import UIKit
import Flutter
import CloudKit
import Network
import CoreSpotlight
import MobileCoreServices
#if canImport(FoundationModels)
import FoundationModels
#endif

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
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
  private let cloudKitZoneName = "HiMemoSyncZone"
  private let cloudKitRecordType = "HiMemoSyncBundle"
  private let cloudKitAttachmentRecordType = "HiMemoSyncAttachment"
  private let cloudKitAssetField = "bundleAsset"
  private let cloudKitAttachmentAssetField = "attachmentAsset"
  private let cloudKitContentHashField = "contentHash"
  private let cloudKitAttachmentTypeField = "attachmentType"
  private let cloudKitAttachmentLabelField = "attachmentLabel"
  private let cloudKitAttachmentSizeField = "attachmentSize"
  // CloudKit production schema type: Int(64). This is metadata, not a Bytes field.
  private let cloudKitBundleSizeField = "bundleSize"
  private let cloudKitDeviceIdField = "deviceId"
  private let cloudKitNoteCountField = "noteCount"
  private let cloudKitAttachmentCountField = "attachmentCount"
  private let cloudKitExportedAtField = "exportedAt"
  private let cloudKitBundleKindField = "bundleKind"
  private let cloudKitAccountStatusCacheDuration: TimeInterval = 60

  private var widgetChannel: FlutterMethodChannel?
  private var cloudKitChannel: FlutterMethodChannel?
  private var privacyChannel: FlutterMethodChannel?
  private var networkChannel: FlutterMethodChannel?
  private var spotlightChannel: FlutterMethodChannel?
  private var intelligenceChannel: FlutterMethodChannel?
  private var pendingQuickCapturePayload: [String: Any]?
  private var pendingSpotlightNoteId: String?
  private var privacyProtectionEnabled = false
  private var privacyOverlayView: UIView?
  private var cloudKitAccountAvailableUntil: Date?
  private var cloudKitSyncZoneReady = false

  private var cloudKitSyncZoneID: CKRecordZone.ID {
    CKRecordZone.ID(zoneName: cloudKitZoneName, ownerName: CKCurrentUserDefaultName)
  }

  private var cloudKitBundleMetadataFields: [String] {
    [
      cloudKitDeviceIdField,
      cloudKitNoteCountField,
      cloudKitAttachmentCountField,
      cloudKitExportedAtField,
      cloudKitBundleKindField,
      cloudKitBundleSizeField,
    ]
  }

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
      cloudKitChannel = FlutterMethodChannel(
        name: cloudKitChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      privacyChannel = FlutterMethodChannel(
        name: privacyChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      networkChannel = FlutterMethodChannel(
        name: networkChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      spotlightChannel = FlutterMethodChannel(
        name: spotlightChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      intelligenceChannel = FlutterMethodChannel(
        name: intelligenceChannelName,
        binaryMessenger: controller.binaryMessenger
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

    if let url = launchOptions?[.url] as? URL {
      if !handleQuickCaptureURL(url) {
        _ = handleSpotlightURL(url)
      }
    }
    if let activities = launchOptions?[.userActivityDictionary] as? [AnyHashable: Any] {
      for value in activities.values {
        if let activity = value as? NSUserActivity,
           handleSpotlightUserActivity(activity) {
          break
        }
      }
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

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    if privacyProtectionEnabled {
      setPrivacyOverlayVisible(true)
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    if privacyProtectionEnabled {
      setPrivacyOverlayVisible(true)
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    setPrivacyOverlayVisible(false)
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
    attributeSet.keywords = ([resolvedTitle, body ?? "", "HiMemo"] + tags + searchTerms)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    attributeSet.alternateNames = attributeSet.keywords
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
    guard let window else {
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
      guard let file = copySharedFile(url) else {
        return false
      }
      openQuickCapture(payload: [
        "source": "share",
        "text": "",
        "files": [file]
      ])
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

  private func copySharedFile(_ sourceURL: URL) -> [String: String]? {
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

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("shared_imports", isDirectory: true)
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
      return [
        "path": destination.path,
        "name": sourceURL.lastPathComponent,
        "mimeType": mimeType
      ]
    } catch {
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
    return url.standardizedFileURL.path.hasPrefix(appGroupDirectory.standardizedFileURL.path)
  }

  private func readPendingQuickCapturePayload() -> [String: Any]? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    let url = container.appendingPathComponent(pendingQuickCaptureFileName)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    defer {
      try? FileManager.default.removeItem(at: url)
    }
    guard
      let data = try? Data(contentsOf: url),
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return payload
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
      "appGroupPendingQuickCaptureBytes": Int(fileSizeBytes(pendingQuickCapture)),
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
    case "cloudKitAccountStatus":
      checkCloudKitAccountStatus(result: result)
    case "cloudKitFetchLatestBundleStatus":
      fetchLatestCloudKitBundleStatus(result: result)
    case "cloudKitListBundleHistory":
      let args = call.arguments as? [String: Any]
      let limit = args?["limit"] as? Int ?? 10
      listCloudKitBundleHistory(limit: limit, result: result)
    case "cloudKitUploadBundle":
      guard
        let args = call.arguments as? [String: Any],
        let encodedPayload = args["encodedPayload"] as? String,
        let deviceId = args["deviceId"] as? String,
        let noteCount = args["noteCount"] as? Int,
        let attachmentCount = args["attachmentCount"] as? Int
      else {
        result(
          FlutterError(
            code: "invalidArguments",
            message: "CloudKit upload arguments are invalid.",
            details: nil
          )
        )
        return
      }
      uploadCloudKitBundle(
        encodedPayload: encodedPayload,
        deviceId: deviceId,
        noteCount: noteCount,
        attachmentCount: attachmentCount,
        bundleKind: args["bundleKind"] as? String ?? "full",
        result: result
      )
    case "cloudKitDownloadLatestBundle":
      downloadLatestCloudKitBundle(result: result)
    case "cloudKitUploadAttachmentObject":
      guard
        let args = call.arguments as? [String: Any],
        let contentHash = args["contentHash"] as? String,
        let encodedPayload = args["encodedPayload"] as? String,
        let type = args["type"] as? String,
        let label = args["label"] as? String,
        let sizeBytes = args["sizeBytes"] as? Int,
        !contentHash.isEmpty
      else {
        result(
          FlutterError(
            code: "invalidArguments",
            message: "CloudKit attachment upload arguments are invalid.",
            details: nil
          )
        )
        return
      }
      uploadCloudKitAttachmentObject(
        contentHash: contentHash,
        encodedPayload: encodedPayload,
        type: type,
        label: label,
        sizeBytes: sizeBytes,
        skipExistingCheck: args["skipExistingCheck"] as? Bool ?? false,
        result: result
      )
    case "cloudKitListAttachmentHashes":
      listCloudKitAttachmentHashes(result: result)
    case "cloudKitDownloadAttachmentObject":
      guard
        let args = call.arguments as? [String: Any],
        let contentHash = args["contentHash"] as? String,
        !contentHash.isEmpty
      else {
        result(
          FlutterError(
            code: "invalidArguments",
            message: "contentHash is required.",
            details: nil
          )
        )
        return
      }
      downloadCloudKitAttachmentObject(contentHash: contentHash, result: result)
    case "cloudKitDownloadBundle":
      guard
        let args = call.arguments as? [String: Any],
        let recordName = args["recordName"] as? String,
        !recordName.isEmpty
      else {
        result(
          FlutterError(
            code: "invalidArguments",
            message: "recordName is required.",
            details: nil
          )
        )
        return
      }
      downloadCloudKitBundle(recordName: recordName, result: result)
    case "cloudKitStorageBreakdown":
      cloudKitStorageBreakdown(result: result)
    case "cloudKitPruneObsoleteData":
      let args = call.arguments as? [String: Any]
      let keepLatest = args?["keepLatest"] as? Int ?? 1
      let referencedAttachmentHashes =
        Set(args?["referencedAttachmentHashes"] as? [String] ?? [])
      pruneObsoleteCloudKitData(
        keepLatest: max(keepLatest, 1),
        referencedAttachmentHashes: referencedAttachmentHashes,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func checkCloudKitAccountStatus(result: @escaping FlutterResult) {
    guard let container = makeCloudKitContainer() else {
      result(cloudKitConfigurationError())
      return
    }
    container.accountStatus { status, error in
      DispatchQueue.main.async {
        if let error {
          result(self.flutterError(from: error))
          return
        }

        let payload: [String: Any]
        switch status {
        case .available:
          self.cloudKitAccountAvailableUntil = Date().addingTimeInterval(
            self.cloudKitAccountStatusCacheDuration
          )
          payload = [
            "status": "available",
            "message": "iCloud is available on this device."
          ]
        case .noAccount:
          self.cloudKitAccountAvailableUntil = nil
          self.cloudKitSyncZoneReady = false
          payload = [
            "status": "noAccount",
            "message": "Sign in to iCloud in the Settings app before enabling iCloud sync on this device."
          ]
        case .restricted:
          self.cloudKitAccountAvailableUntil = nil
          self.cloudKitSyncZoneReady = false
          payload = [
            "status": "restricted",
            "message": "This device restricts iCloud access. Check Screen Time, parental controls, or device management restrictions."
          ]
        case .temporarilyUnavailable:
          self.cloudKitAccountAvailableUntil = nil
          payload = [
            "status": "temporarilyUnavailable",
            "message": "The user's iCloud account is temporarily unavailable. Try again later."
          ]
        case .couldNotDetermine:
          self.cloudKitAccountAvailableUntil = nil
          payload = [
            "status": "couldNotDetermine",
            "message": "Unable to determine the user's iCloud status right now."
          ]
        @unknown default:
          self.cloudKitAccountAvailableUntil = nil
          payload = [
            "status": "unknown",
            "message": "Unable to determine the user's iCloud status right now."
          ]
        }
        result(payload)
      }
    }
  }

  private func fetchLatestCloudKitBundleStatus(result: @escaping FlutterResult) {
    withAvailableCloudKit(result: result) { database in
      self.fetchCloudKitRecords(
        database: database,
        limit: 1,
        desiredKeys: self.cloudKitBundleMetadataFields
      ) { records, error in
        DispatchQueue.main.async {
          if let error {
            result(self.flutterError(from: error))
            return
          }
          result(records.first.map(self.serializeRecord))
        }
      }
    }
  }

  private func listCloudKitBundleHistory(limit: Int, result: @escaping FlutterResult) {
    withAvailableCloudKit(result: result) { database in
      self.fetchCloudKitRecords(
        database: database,
        limit: max(limit, 1),
        desiredKeys: self.cloudKitBundleMetadataFields
      ) { records, error in
        DispatchQueue.main.async {
          if let error {
            result(self.flutterError(from: error))
            return
          }
          result(records.map(self.serializeRecord))
        }
      }
    }
  }

  private func uploadCloudKitBundle(
    encodedPayload: String,
    deviceId: String,
    noteCount: Int,
    attachmentCount: Int,
    bundleKind: String,
    result: @escaping FlutterResult
  ) {
    withAvailableCloudKit(result: result) { database in
      let recordID = CKRecord.ID(
        recordName: "sync-\(UUID().uuidString)",
        zoneID: self.cloudKitSyncZoneID
      )
      let record = CKRecord(recordType: self.cloudKitRecordType, recordID: recordID)
      let temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(recordID.recordName).enc")

      do {
        try encodedPayload.write(to: temporaryURL, atomically: true, encoding: .utf8)
      } catch {
        result(
          FlutterError(
            code: "writeFailed",
            message: "Failed to prepare the encrypted bundle for iCloud upload.",
            details: nil
          )
        )
        return
      }

      record[self.cloudKitDeviceIdField] = deviceId as CKRecordValue
      record[self.cloudKitNoteCountField] = NSNumber(value: noteCount)
      record[self.cloudKitAttachmentCountField] = NSNumber(value: attachmentCount)
      record[self.cloudKitExportedAtField] = Date() as CKRecordValue
      record[self.cloudKitBundleKindField] = bundleKind as CKRecordValue
      record[self.cloudKitBundleSizeField] = NSNumber(value: encodedPayload.utf8.count)
      record[self.cloudKitAssetField] = CKAsset(fileURL: temporaryURL)

      database.save(record) { savedRecord, error in
        try? FileManager.default.removeItem(at: temporaryURL)
        DispatchQueue.main.async {
          if let error {
            result(self.flutterError(from: error))
            return
          }
          guard let savedRecord else {
            result(
              FlutterError(
                code: "saveFailed",
                message: "CloudKit didn't return saved metadata.",
                details: nil
              )
            )
            return
          }
          result(self.serializeRecord(savedRecord))
        }
      }
    }
  }

  private func downloadLatestCloudKitBundle(result: @escaping FlutterResult) {
    withAvailableCloudKit(result: result) { database in
      self.fetchCloudKitRecords(database: database, limit: 1) { records, error in
        if let error {
          DispatchQueue.main.async {
            result(self.flutterError(from: error))
          }
          return
        }
        guard let record = records.first else {
          DispatchQueue.main.async {
            result(nil)
          }
          return
        }
        self.readBundlePayload(from: record, result: result)
      }
    }
  }

  private func downloadCloudKitBundle(recordName: String, result: @escaping FlutterResult) {
    withAvailableCloudKit(result: result) { database in
      database.fetch(
        withRecordID: CKRecord.ID(
          recordName: recordName,
          zoneID: self.cloudKitSyncZoneID
        )
      ) { record, error in
        if let error {
          DispatchQueue.main.async {
            result(self.flutterError(from: error))
          }
          return
        }
        guard let record else {
          DispatchQueue.main.async {
            result(nil)
          }
          return
        }
        self.readBundlePayload(from: record, result: result)
      }
    }
  }

  private func uploadCloudKitAttachmentObject(
    contentHash: String,
    encodedPayload: String,
    type: String,
    label: String,
    sizeBytes: Int,
    skipExistingCheck: Bool,
    result: @escaping FlutterResult
  ) {
    withAvailableCloudKit(result: result) { database in
      let recordID = CKRecord.ID(
        recordName: "attachment-\(contentHash)",
        zoneID: self.cloudKitSyncZoneID
      )

      func saveNewRecord() {
        let record = CKRecord(recordType: self.cloudKitAttachmentRecordType, recordID: recordID)
        let temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("\(recordID.recordName).encjson")

        do {
          try encodedPayload.write(to: temporaryURL, atomically: true, encoding: .utf8)
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "writeFailed",
                message: "Failed to prepare the encrypted attachment for iCloud upload.",
                details: nil
              )
            )
          }
          return
        }

        record[self.cloudKitContentHashField] = contentHash as CKRecordValue
        record[self.cloudKitAttachmentTypeField] = type as CKRecordValue
        record[self.cloudKitAttachmentLabelField] = label as CKRecordValue
        record[self.cloudKitAttachmentSizeField] = NSNumber(value: sizeBytes)
        record[self.cloudKitExportedAtField] = Date() as CKRecordValue
        record[self.cloudKitAttachmentAssetField] = CKAsset(fileURL: temporaryURL)

        database.save(record) { savedRecord, error in
          try? FileManager.default.removeItem(at: temporaryURL)
          DispatchQueue.main.async {
            // Attachment records are content-addressed, so a record that
            // already exists holds identical content — treat it as success.
            if let ckError = error as? CKError,
               ckError.code == .serverRecordChanged {
              result(["recordName": recordID.recordName])
              return
            }
            if let error {
              result(self.flutterError(from: error))
              return
            }
            guard let savedRecord else {
              result(
                FlutterError(
                  code: "saveFailed",
                  message: "CloudKit didn't return saved attachment metadata.",
                  details: nil
                )
              )
              return
            }
            result(["recordName": savedRecord.recordID.recordName])
          }
        }
      }

      if skipExistingCheck {
        saveNewRecord()
        return
      }

      database.fetch(withRecordID: recordID) { existingRecord, fetchError in
        if existingRecord != nil {
          DispatchQueue.main.async {
            result(["recordName": recordID.recordName])
          }
          return
        }
        if let fetchError = fetchError as? CKError, fetchError.code != .unknownItem {
          DispatchQueue.main.async {
            result(self.flutterError(from: fetchError))
          }
          return
        }
        saveNewRecord()
      }
    }
  }

  private func listCloudKitAttachmentHashes(result: @escaping FlutterResult) {
    withAvailableCloudKit(result: result) { database in
      self.fetchAllCloudKitRecords(
        database: database,
        recordType: self.cloudKitAttachmentRecordType,
        sortedByModificationDate: false,
        desiredKeys: [self.cloudKitContentHashField]
      ) { records, error in
        DispatchQueue.main.async {
          if let error {
            result(self.flutterError(from: error))
            return
          }
          let hashes = records.compactMap { record -> String? in
            if let contentHash = record[self.cloudKitContentHashField] as? String,
               !contentHash.isEmpty {
              return contentHash
            }
            let recordName = record.recordID.recordName
            guard recordName.hasPrefix("attachment-") else {
              return nil
            }
            return String(recordName.dropFirst("attachment-".count))
          }
          result(hashes)
        }
      }
    }
  }

  private func downloadCloudKitAttachmentObject(
    contentHash: String,
    result: @escaping FlutterResult
  ) {
    withAvailableCloudKit(result: result) { database in
      let recordID = CKRecord.ID(
        recordName: "attachment-\(contentHash)",
        zoneID: self.cloudKitSyncZoneID
      )
      database.fetch(withRecordID: recordID) { record, error in
        if let error = error as? CKError, error.code == .unknownItem {
          DispatchQueue.main.async {
            result(nil)
          }
          return
        }
        if let error {
          DispatchQueue.main.async {
            result(self.flutterError(from: error))
          }
          return
        }
        guard let record else {
          DispatchQueue.main.async {
            result(nil)
          }
          return
        }
        self.readAttachmentObjectPayload(from: record, result: result)
      }
    }
  }

  private func cloudKitStorageBreakdown(result: @escaping FlutterResult) {
    withAvailableCloudKit(result: result) { database in
      let group = DispatchGroup()
      var bundleRecords: [CKRecord] = []
      var attachmentRecords: [CKRecord] = []
      var firstError: Error?

      group.enter()
      self.fetchAllCloudKitRecords(
        database: database,
        recordType: self.cloudKitRecordType,
        sortedByModificationDate: false
      ) { records, error in
        if let error, firstError == nil {
          firstError = error
        }
        bundleRecords = records
        group.leave()
      }

      group.enter()
      self.fetchAllCloudKitRecords(
        database: database,
        recordType: self.cloudKitAttachmentRecordType,
        sortedByModificationDate: false
      ) { records, error in
        if let error, firstError == nil {
          firstError = error
        }
        attachmentRecords = records
        group.leave()
      }

      group.notify(queue: .main) {
        if let firstError {
          result(self.flutterError(from: firstError))
          return
        }
        let bundleBytes = bundleRecords.reduce(0) { total, record in
          total + (self.assetFileSize(for: record, field: self.cloudKitAssetField) ?? 0)
        }
        let attachmentBytes = attachmentRecords.reduce(0) { total, record in
          total + (self.assetFileSize(for: record, field: self.cloudKitAttachmentAssetField) ?? 0)
        }
        result([
          "bundleCount": bundleRecords.count,
          "bundleBytes": bundleBytes,
          "attachmentCount": attachmentRecords.count,
          "attachmentBytes": attachmentBytes,
        ])
      }
    }
  }

  private func pruneObsoleteCloudKitData(
    keepLatest: Int,
    referencedAttachmentHashes: Set<String>,
    result: @escaping FlutterResult
  ) {
    withAvailableCloudKit(result: result) { database in
      let group = DispatchGroup()
      var bundleRecords: [CKRecord] = []
      var attachmentRecords: [CKRecord] = []
      var firstError: Error?

      group.enter()
      self.fetchAllCloudKitRecords(
        database: database,
        recordType: self.cloudKitRecordType,
        sortedByModificationDate: true
      ) { records, error in
        if let error, firstError == nil {
          firstError = error
        }
        bundleRecords = records
        group.leave()
      }

      group.enter()
      self.fetchAllCloudKitRecords(
        database: database,
        recordType: self.cloudKitAttachmentRecordType,
        sortedByModificationDate: false
      ) { records, error in
        if let error, firstError == nil {
          firstError = error
        }
        attachmentRecords = records
        group.leave()
      }

      group.notify(queue: .global(qos: .utility)) {
        if let firstError {
          DispatchQueue.main.async {
            result(self.flutterError(from: firstError))
          }
          return
        }

        let bundleRecordsToDelete = Array(bundleRecords.dropFirst(keepLatest))
        let attachmentRecordsToDelete = attachmentRecords.filter { record in
          guard let contentHash = record[self.cloudKitContentHashField] as? String else {
            return true
          }
          return !referencedAttachmentHashes.contains(contentHash)
        }
        let deletedBundleBytes = bundleRecordsToDelete.reduce(0) { total, record in
          total + (self.assetFileSize(for: record, field: self.cloudKitAssetField) ?? 0)
        }
        let deletedAttachmentBytes = attachmentRecordsToDelete.reduce(0) { total, record in
          total + (self.assetFileSize(for: record, field: self.cloudKitAttachmentAssetField) ?? 0)
        }
        let recordIDsToDelete =
          bundleRecordsToDelete.map { $0.recordID } +
          attachmentRecordsToDelete.map { $0.recordID }
        if recordIDsToDelete.isEmpty {
          DispatchQueue.main.async {
            result([
              "deletedBundleCount": 0,
              "deletedBundleBytes": 0,
              "deletedAttachmentCount": 0,
              "deletedAttachmentBytes": 0,
            ])
          }
          return
        }

        self.deleteCloudKitRecords(
          database: database,
          recordIDs: recordIDsToDelete
        ) { error in
          DispatchQueue.main.async {
            if let error {
              result(self.flutterError(from: error))
              return
            }
            result([
              "deletedBundleCount": bundleRecordsToDelete.count,
              "deletedBundleBytes": deletedBundleBytes,
              "deletedAttachmentCount": attachmentRecordsToDelete.count,
              "deletedAttachmentBytes": deletedAttachmentBytes,
            ])
          }
        }
      }
    }
  }

  private func withAvailableCloudKit(
    result: @escaping FlutterResult,
    action: @escaping (CKDatabase) -> Void
  ) {
    guard let container = makeCloudKitContainer() else {
      result(cloudKitConfigurationError())
      return
    }

    func continueWithDatabase() {
      let database = container.privateCloudDatabase
      self.ensureCloudKitSyncZone(database: database) { error in
        if let error {
          DispatchQueue.main.async {
            result(self.flutterError(from: error))
          }
          return
        }
        action(database)
      }
    }

    if let availableUntil = cloudKitAccountAvailableUntil,
       Date() < availableUntil {
      continueWithDatabase()
      return
    }

    container.accountStatus { status, error in
      if let error {
        self.cloudKitAccountAvailableUntil = nil
        DispatchQueue.main.async {
          result(self.flutterError(from: error))
        }
        return
      }
      guard status == .available else {
        self.cloudKitAccountAvailableUntil = nil
        self.cloudKitSyncZoneReady = false
        DispatchQueue.main.async {
          result(self.flutterErrorForAccountStatus(status))
        }
        return
      }
      self.cloudKitAccountAvailableUntil = Date().addingTimeInterval(
        self.cloudKitAccountStatusCacheDuration
      )
      continueWithDatabase()
    }
  }

  private func ensureCloudKitSyncZone(
    database: CKDatabase,
    completion: @escaping (Error?) -> Void
  ) {
    if cloudKitSyncZoneReady {
      completion(nil)
      return
    }
    let zoneID = cloudKitSyncZoneID
    database.fetch(withRecordZoneID: zoneID) { zone, error in
      if zone != nil {
        self.cloudKitSyncZoneReady = true
        completion(nil)
        return
      }
      if let cloudError = error as? CKError, cloudError.code != .zoneNotFound {
        completion(cloudError)
        return
      }
      let zone = CKRecordZone(zoneID: zoneID)
      database.save(zone) { _, saveError in
        if saveError == nil {
          self.cloudKitSyncZoneReady = true
        }
        completion(saveError)
      }
    }
  }

  private func fetchCloudKitRecords(
    database: CKDatabase,
    limit: Int,
    desiredKeys: [String]? = nil,
    completion: @escaping ([CKRecord], Error?) -> Void
  ) {
    var records: [CKRecord] = []
    let query = CKQuery(
      recordType: cloudKitRecordType,
      predicate: NSPredicate(value: true)
    )
    query.sortDescriptors = [
      NSSortDescriptor(key: "modificationDate", ascending: false)
    ]

    func finish(_ error: Error?) {
      if let error {
        completion(records, error)
        return
      }
      completion(Array(records.prefix(limit)), nil)
    }

    func fetch(cursor: CKQueryOperation.Cursor?) {
      let operation: CKQueryOperation
      if let cursor {
        operation = CKQueryOperation(cursor: cursor)
      } else {
        operation = CKQueryOperation(query: query)
        operation.zoneID = cloudKitSyncZoneID
      }
      operation.resultsLimit = max(limit - records.count, 1)
      operation.desiredKeys = desiredKeys
      operation.recordFetchedBlock = { record in
        if records.count < limit {
          records.append(record)
        }
      }
      operation.queryCompletionBlock = { nextCursor, error in
        if let error {
          finish(error)
          return
        }
        if let nextCursor, records.count < limit {
          fetch(cursor: nextCursor)
          return
        }
        finish(nil)
      }
      database.add(operation)
    }

    fetch(cursor: nil)
  }

  private func fetchAllCloudKitRecords(
    database: CKDatabase,
    recordType: String,
    sortedByModificationDate: Bool,
    desiredKeys: [String]? = nil,
    completion: @escaping ([CKRecord], Error?) -> Void
  ) {
    var records: [CKRecord] = []

    func finish(_ error: Error?) {
      if let error {
        completion(records, error)
        return
      }
      if sortedByModificationDate {
        records.sort {
          ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
        }
      }
      completion(records, nil)
    }

    func fetchChanges(after token: CKServerChangeToken?) {
      let zoneID = cloudKitSyncZoneID
      let options = CKFetchRecordZoneChangesOperation.ZoneOptions()
      options.previousServerChangeToken = token
      options.desiredKeys = desiredKeys
      let operation = CKFetchRecordZoneChangesOperation(
        recordZoneIDs: [zoneID],
        optionsByRecordZoneID: [zoneID: options]
      )
      var requestedMore = false
      operation.recordChangedBlock = { (record: CKRecord) in
        if record.recordType == recordType {
          records.append(record)
        }
      }
      operation.recordZoneFetchCompletionBlock = {
        (_: CKRecordZone.ID, serverChangeToken: CKServerChangeToken?, _: Data?, moreComing: Bool, error: Error?) in
        if let error {
          finish(error)
          return
        }
        if moreComing {
          requestedMore = true
          fetchChanges(after: serverChangeToken)
        }
      }
      operation.fetchRecordZoneChangesCompletionBlock = { (error: Error?) in
        if requestedMore {
          return
        }
        if let error {
          finish(error)
          return
        }
        finish(nil)
      }
      database.add(operation)
    }

    fetchChanges(after: nil)
  }

  private func deleteCloudKitRecords(
    database: CKDatabase,
    recordIDs: [CKRecord.ID],
    completion: @escaping (Error?) -> Void
  ) {
    if recordIDs.isEmpty {
      completion(nil)
      return
    }

    var index = 0
    func deleteNextBatch() {
      if index >= recordIDs.count {
        completion(nil)
        return
      }
      let end = min(index + 200, recordIDs.count)
      let batch = Array(recordIDs[index..<end])
      index = end
      let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
      operation.modifyRecordsCompletionBlock = { _, _, error in
        if let error {
          completion(error)
          return
        }
        deleteNextBatch()
      }
      database.add(operation)
    }

    deleteNextBatch()
  }

  private func readBundlePayload(from record: CKRecord, result: @escaping FlutterResult) {
    guard
      let asset = record[cloudKitAssetField] as? CKAsset,
      let fileURL = asset.fileURL
    else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "missingAsset",
            message: "CloudKit record does not contain an encrypted bundle asset.",
            details: nil
          )
        )
      }
      return
    }

    do {
      let payload = try String(contentsOf: fileURL, encoding: .utf8)
      DispatchQueue.main.async {
        result([
          "status": self.serializeRecord(record),
          "encodedPayload": payload,
        ])
      }
    } catch {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "readFailed",
            message: "The downloaded iCloud bundle couldn't be read.",
            details: nil
          )
        )
      }
    }
  }

  private func readAttachmentObjectPayload(from record: CKRecord, result: @escaping FlutterResult) {
    guard
      let asset = record[cloudKitAttachmentAssetField] as? CKAsset,
      let fileURL = asset.fileURL
    else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "missingAsset",
            message: "CloudKit record does not contain an encrypted attachment asset.",
            details: nil
          )
        )
      }
      return
    }

    do {
      let payload = try String(contentsOf: fileURL, encoding: .utf8)
      DispatchQueue.main.async {
        result(["encodedPayload": payload])
      }
    } catch {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "readFailed",
            message: "The downloaded iCloud attachment couldn't be read.",
            details: nil
          )
        )
      }
    }
  }

  private func serializeRecord(_ record: CKRecord) -> [String: Any] {
    let noteCount = (record[cloudKitNoteCountField] as? NSNumber)?.intValue
    let attachmentCount = (record[cloudKitAttachmentCountField] as? NSNumber)?.intValue
    let bundleSize = (record[cloudKitBundleSizeField] as? NSNumber)?.intValue
    let assetFileName =
      ((record[cloudKitAssetField] as? CKAsset)?.fileURL?.lastPathComponent) ??
      record.recordID.recordName

    var payload: [String: Any] = [
      "recordName": record.recordID.recordName,
      "fileName": assetFileName,
    ]
    if let modifiedAt = record.modificationDate?.iso8601String {
      payload["modifiedAt"] = modifiedAt
    }
    if let sizeBytes = bundleSize ?? bundleFileSize(for: record) {
      payload["sizeBytes"] = sizeBytes
    }
    if let noteCount = noteCount {
      payload["noteCount"] = noteCount
    }
    if let attachmentCount = attachmentCount {
      payload["attachmentCount"] = attachmentCount
    }
    if let deviceId = record[cloudKitDeviceIdField] as? String {
      payload["deviceId"] = deviceId
    }
    if let bundleKind = record[cloudKitBundleKindField] as? String {
      payload["bundleKind"] = bundleKind
    }
    return payload
  }

  private func bundleFileSize(for record: CKRecord) -> Int? {
    return assetFileSize(for: record, field: cloudKitAssetField)
  }

  private func assetFileSize(for record: CKRecord, field: String) -> Int? {
    guard
      let asset = record[field] as? CKAsset,
      let fileURL = asset.fileURL,
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
    else {
      return nil
    }
    return values.fileSize
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

  private func flutterErrorForAccountStatus(_ status: CKAccountStatus) -> FlutterError {
    switch status {
    case .noAccount:
      return FlutterError(
        code: "noAccount",
        message: "Sign in to iCloud in Settings before using iCloud sync on this device.",
        details: ["message": "Sign in to iCloud in Settings before using iCloud sync on this device."]
      )
    case .restricted:
      return FlutterError(
        code: "restricted",
        message: "This device restricts iCloud access. Check Screen Time, parental controls, or device management restrictions.",
        details: ["message": "This device restricts iCloud access. Check Screen Time, parental controls, or device management restrictions."]
      )
    case .temporarilyUnavailable:
      return FlutterError(
        code: "temporarilyUnavailable",
        message: "The user's iCloud account is temporarily unavailable. Try again later.",
        details: ["message": "The user's iCloud account is temporarily unavailable. Try again later."]
      )
    case .couldNotDetermine:
      return FlutterError(
        code: "couldNotDetermine",
        message: "Unable to determine the user's iCloud status right now.",
        details: ["message": "Unable to determine the user's iCloud status right now."]
      )
    case .available:
      return FlutterError(
        code: "available",
        message: "iCloud is available.",
        details: nil
      )
    @unknown default:
      return FlutterError(
        code: "unknown",
        message: "Unable to determine the user's iCloud status right now.",
        details: ["message": "Unable to determine the user's iCloud status right now."]
      )
    }
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

private extension Date {
  var iso8601String: String {
    ISO8601DateFormatter().string(from: self)
  }
}
