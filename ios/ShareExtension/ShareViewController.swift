import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let appGroupIdentifier = "group.org.ruhenheim.himemo"
  private let pendingFileName = "pending_quick_capture.json"
  private let appURL = URL(string: "himemo://widget-capture")!
  private let maxImageBytes = 25 * 1024 * 1024
  private let maxAudioBytes = 50 * 1024 * 1024
  private let maxVideoBytes = 200 * 1024 * 1024

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    Task { await handleShare() }
  }

  private func handleShare() async {
    let payload = await buildPayload()
    do {
      try writePendingPayload(payload)
      extensionContext?.open(appURL) { [weak self] _ in
        self?.extensionContext?.completeRequest(returningItems: nil)
      }
    } catch {
      extensionContext?.cancelRequest(withError: error)
    }
  }

  private func buildPayload() async -> [String: Any] {
    var textItems: [String] = []
    var files: [[String: String]] = []
    var rejectedFiles: [[String: String]] = []

    let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    for item in inputItems {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
           let text = await loadText(from: provider),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          textItems.append(text)
          continue
        }

        guard let type = supportedType(for: provider) else {
          continue
        }
        guard let copied = await copyProvider(provider, as: type) else {
          rejectedFiles.append([
            "name": provider.suggestedName ?? "Shared file",
            "mimeType": type.mimeType,
            "reason": "unreadable"
          ])
          continue
        }
        if copied.rejectedReason == nil {
          files.append(copied.payload)
        } else {
          rejectedFiles.append([
            "name": copied.payload["name"] ?? "Shared file",
            "mimeType": copied.payload["mimeType"] ?? type.mimeType,
            "reason": copied.rejectedReason ?? "unreadable"
          ])
        }
      }
    }

    return [
      "source": "share",
      "text": textItems.joined(separator: "\n\n"),
      "files": files,
      "rejectedFiles": rejectedFiles
    ]
  }

  private func loadText(from provider: NSItemProvider) async -> String? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
        if let text = item as? String {
          continuation.resume(returning: text)
        } else if let data = item as? Data {
          continuation.resume(returning: String(data: data, encoding: .utf8))
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private func copyProvider(
    _ provider: NSItemProvider,
    as type: SharedType,
  ) async -> (payload: [String: String], rejectedReason: String?)? {
    await withCheckedContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, _ in
        guard let self, let url else {
          continuation.resume(returning: nil)
          return
        }
        let name = provider.suggestedName ?? url.lastPathComponent
        do {
          let values = try url.resourceValues(forKeys: [.fileSizeKey])
          if let fileSize = values.fileSize, fileSize > type.maxBytes {
            continuation.resume(returning: ([
              "name": name,
              "mimeType": type.mimeType,
            ], "This file is too large."))
            return
          }

          let destination = try self.destinationURL(for: name)
          if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
          }
          try FileManager.default.copyItem(at: url, to: destination)
          let mimeType = self.mimeTypeForSharedURL(url, fallback: type.mimeType)
          continuation.resume(returning: ([
            "path": destination.path,
            "name": name,
            "mimeType": mimeType,
          ], nil))
        } catch {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private func destinationURL(for fileName: String) throws -> URL {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      throw ShareExtensionError.missingAppGroup
    }
    let directory = container.appendingPathComponent("shared_imports", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeName = fileName
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
    return directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
  }

  private func writePendingPayload(_ payload: [String: Any]) throws {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      throw ShareExtensionError.missingAppGroup
    }
    let data = try JSONSerialization.data(withJSONObject: payload)
    try data.write(to: container.appendingPathComponent(pendingFileName), options: .atomic)
  }

  private func supportedType(for provider: NSItemProvider) -> SharedType? {
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
      return SharedType(
        identifier: UTType.image.identifier,
        mimeType: "image/jpeg",
        maxBytes: maxImageBytes
      )
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
      return SharedType(
        identifier: UTType.movie.identifier,
        mimeType: "video/quicktime",
        maxBytes: maxVideoBytes
      )
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
      return SharedType(
        identifier: UTType.audio.identifier,
        mimeType: "audio/mp4",
        maxBytes: maxAudioBytes
      )
    }
    return nil
  }

  private func mimeTypeForSharedURL(_ url: URL, fallback: String) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "gif":
      return "image/gif"
    case "webp":
      return "image/webp"
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
      return fallback
    }
  }
}

private struct SharedType {
  let identifier: String
  let mimeType: String
  let maxBytes: Int
}

private enum ShareExtensionError: Error {
  case missingAppGroup
}
