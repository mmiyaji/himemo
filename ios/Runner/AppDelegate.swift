import UIKit
import Flutter
import CloudKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let widgetChannelName = "org.ruhenheim.himemo/widget"
  private let cloudKitChannelName = "org.ruhenheim.himemo/cloudkit"
  private let quickCaptureUrl = "himemo://widget-capture"
  private let cloudKitContainerIdentifier = "iCloud.org.ruhenheim.himemo"
  private let cloudKitRecordType = "HiMemoSyncBundle"
  private let cloudKitAssetField = "bundleAsset"
  private let cloudKitDeviceIdField = "deviceId"
  private let cloudKitNoteCountField = "noteCount"
  private let cloudKitAttachmentCountField = "attachmentCount"
  private let cloudKitExportedAtField = "exportedAt"

  private var widgetChannel: FlutterMethodChannel?
  private var cloudKitChannel: FlutterMethodChannel?
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
      cloudKitChannel = FlutterMethodChannel(
        name: cloudKitChannelName,
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
          return
        }
        result(FlutterMethodNotImplemented)
      }

      cloudKitChannel?.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(FlutterMethodNotImplemented)
          return
        }
        self.handleCloudKitMethod(call: call, result: result)
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

  private var cloudKitContainer: CKContainer {
    CKContainer(identifier: cloudKitContainerIdentifier)
  }

  private var privateDatabase: CKDatabase {
    cloudKitContainer.privateCloudDatabase
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
        result: result
      )
    case "cloudKitDownloadLatestBundle":
      downloadLatestCloudKitBundle(result: result)
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
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func checkCloudKitAccountStatus(result: @escaping FlutterResult) {
    cloudKitContainer.accountStatus { status, error in
      DispatchQueue.main.async {
        if let error {
          result(self.flutterError(from: error))
          return
        }

        let payload: [String: Any]
        switch status {
        case .available:
          payload = [
            "status": "available",
            "message": "iCloud is available on this device."
          ]
        case .noAccount:
          payload = [
            "status": "noAccount",
            "message": "Sign in to iCloud in the Settings app before enabling iCloud sync on this device."
          ]
        case .restricted:
          payload = [
            "status": "restricted",
            "message": "This device restricts iCloud access. Check Screen Time, parental controls, or device management restrictions."
          ]
        case .temporarilyUnavailable:
          payload = [
            "status": "temporarilyUnavailable",
            "message": "The user's iCloud account is temporarily unavailable. Try again later."
          ]
        case .couldNotDetermine:
          payload = [
            "status": "couldNotDetermine",
            "message": "Unable to determine the user's iCloud status right now."
          ]
        @unknown default:
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
    withAvailableCloudKit(result: result) {
      self.fetchCloudKitRecords(limit: 1) { records, error in
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
    withAvailableCloudKit(result: result) {
      self.fetchCloudKitRecords(limit: max(limit, 1)) { records, error in
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
    result: @escaping FlutterResult
  ) {
    withAvailableCloudKit(result: result) {
      let recordID = CKRecord.ID(recordName: "sync-\(UUID().uuidString)")
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
      record[self.cloudKitAssetField] = CKAsset(fileURL: temporaryURL)

      self.privateDatabase.save(record) { savedRecord, error in
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
    withAvailableCloudKit(result: result) {
      self.fetchCloudKitRecords(limit: 1) { records, error in
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
    withAvailableCloudKit(result: result) {
      self.privateDatabase.fetch(withRecordID: CKRecord.ID(recordName: recordName)) { record, error in
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

  private func withAvailableCloudKit(
    result: @escaping FlutterResult,
    action: @escaping () -> Void
  ) {
    cloudKitContainer.accountStatus { status, error in
      if let error {
        DispatchQueue.main.async {
          result(self.flutterError(from: error))
        }
        return
      }
      guard status == .available else {
        DispatchQueue.main.async {
          result(self.flutterErrorForAccountStatus(status))
        }
        return
      }
      action()
    }
  }

  private func fetchCloudKitRecords(
    limit: Int,
    completion: @escaping ([CKRecord], Error?) -> Void
  ) {
    let query = CKQuery(
      recordType: cloudKitRecordType,
      predicate: NSPredicate(value: true)
    )
    query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

    let operation = CKQueryOperation(query: query)
    operation.resultsLimit = limit
    var records: [CKRecord] = []
    operation.recordFetchedBlock = { record in
      records.append(record)
    }
    operation.queryCompletionBlock = { _, error in
      completion(records, error)
    }
    privateDatabase.add(operation)
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

  private func serializeRecord(_ record: CKRecord) -> [String: Any] {
    let noteCount = (record[cloudKitNoteCountField] as? NSNumber)?.intValue
    let attachmentCount = (record[cloudKitAttachmentCountField] as? NSNumber)?.intValue
    let assetFileName =
      ((record[cloudKitAssetField] as? CKAsset)?.fileURL?.lastPathComponent) ??
      record.recordID.recordName

    return [
      "recordName": record.recordID.recordName,
      "fileName": assetFileName,
      "modifiedAt": record.modificationDate?.iso8601String as Any,
      "sizeBytes": bundleFileSize(for: record) as Any,
      "noteCount": noteCount as Any,
      "attachmentCount": attachmentCount as Any,
      "deviceId": record[cloudKitDeviceIdField] as? String as Any,
    ]
  }

  private func bundleFileSize(for record: CKRecord) -> Int? {
    guard
      let asset = record[cloudKitAssetField] as? CKAsset,
      let fileURL = asset.fileURL,
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
    else {
      return nil
    }
    return values.fileSize
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
