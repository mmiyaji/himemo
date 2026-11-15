import Foundation
import Flutter
import LocalAuthentication
import Security
import UIKit

/// Device-local storage for the Sync v2 admin key. Items are bound to the
/// currently enrolled biometric set and are never synced or backed up.
final class SyncV2BiometricKeyStore {
  private static let service = "org.ruhenheim.himemo.sync-v2-biometric-key"
  private static let queue = DispatchQueue(label: "org.ruhenheim.himemo.sync-v2-biometric-keychain")

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "org.ruhenheim.himemo/sync_v2_biometrics",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "availability":
        let context = LAContext()
        var error: NSError?
        result(context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
      case "write":
        guard let args = call.arguments as? [String: Any],
              let generationId = args["generationId"] as? String,
              Self.isValidGenerationId(generationId),
              let keyBase64 = args["keyBase64"] as? String,
              let keyData = Data(base64Encoded: keyBase64), keyData.count == 32 else {
          result(Self.error("failed")); return
        }
        Self.authenticate(reason: "Authorize HiMemo Sync key storage") { context, authError in
          guard let context else { result(Self.flutterError(authError)); return }
          guard UIApplication.shared.applicationState != .background else {
            result(Self.error("cancelled")); return
          }
          Self.queue.async {
            let access = SecAccessControlCreateWithFlags(
              kCFAllocatorDefault,
              kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
              .biometryCurrentSet,
              nil
            )
            guard let access else { DispatchQueue.main.async { result(Self.error("failed")) }; return }
            let query: [String: Any] = [
              kSecClass as String: kSecClassGenericPassword,
              kSecAttrService as String: Self.service,
              kSecAttrAccount as String: generationId,
              kSecUseAuthenticationContext as String: context,
            ]
            let updateStatus = SecItemUpdate(
              query as CFDictionary,
              [kSecValueData as String: keyData] as CFDictionary
            )
            let status: OSStatus
            if updateStatus == errSecItemNotFound || updateStatus == errSecAuthFailed {
              // Only replace an absent or already-invalidated biometric item.
              // A valid existing item is never deleted after a failed update.
              if updateStatus == errSecAuthFailed {
                var staleQuery = query
                staleQuery.removeValue(forKey: kSecUseAuthenticationContext as String)
                let deleteStatus = SecItemDelete(staleQuery as CFDictionary)
                guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                  DispatchQueue.main.async { result(Self.error(Self.keychainErrorCode(deleteStatus))) }
                  return
                }
              }
              var item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.service,
                kSecAttrAccount as String: generationId,
                kSecValueData as String: keyData,
                kSecAttrAccessControl as String: access,
              ]
              // Keep the newly-authenticated context available to Keychain if
              // adding the protected item requires authorization.
              item[kSecUseAuthenticationContext as String] = context
              let addStatus = SecItemAdd(item as CFDictionary, nil)
              if addStatus == errSecDuplicateItem {
                // Some iOS versions report an invalidated item as not found
                // on update while retaining its uniqueness reservation.
                // This branch is reachable only after update found no usable item.
                var staleQuery = query
                staleQuery.removeValue(forKey: kSecUseAuthenticationContext as String)
                let deleteStatus = SecItemDelete(staleQuery as CFDictionary)
                if deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound {
                  status = SecItemAdd(item as CFDictionary, nil)
                } else {
                  status = deleteStatus
                }
              } else {
                status = addStatus
              }
            } else {
              status = updateStatus
            }
            DispatchQueue.main.async {
              result(status == errSecSuccess ? nil : Self.error(Self.keychainErrorCode(status)))
            }
          }
        }
      case "read":
        guard let args = call.arguments as? [String: Any],
              let generationId = args["generationId"] as? String,
              Self.isValidGenerationId(generationId) else {
          result(Self.error("failed")); return
        }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
          result(Self.flutterError(authError)); return
        }
        Self.queue.async {
          var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: generationId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: "Unlock HiMemo Sync key",
          ]
          query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIAllow
          var item: CFTypeRef?
          let status = SecItemCopyMatching(query as CFDictionary, &item)
          let response: Any
          if status == errSecItemNotFound {
            response = NSNull()
          } else if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            response = data.base64EncodedString()
          } else {
            let code = Self.keychainErrorCode(status)
            DispatchQueue.main.async { result(Self.error(code)) }
            return
          }
          DispatchQueue.main.async { result(response) }
        }
      case "delete":
        guard let args = call.arguments as? [String: Any],
              let generationId = args["generationId"] as? String,
              Self.isValidGenerationId(generationId) else {
          result(Self.error("failed")); return
        }
        Self.queue.async {
          let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: generationId,
          ]
          let status = SecItemDelete(query as CFDictionary)
          DispatchQueue.main.async {
            result(status == errSecSuccess || status == errSecItemNotFound ? nil : Self.error("failed"))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func authenticate(
    reason: String,
    completion: @escaping (LAContext?, NSError?) -> Void
  ) {
    let context = LAContext()
    context.localizedFallbackTitle = ""
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      completion(nil, error); return
    }
    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
      DispatchQueue.main.async { completion(success ? context : nil, error as NSError?) }
    }
  }

  private static func isValidGenerationId(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 128 && value.rangeOfCharacter(from: .controlCharacters) == nil
  }

  private static func keychainErrorCode(_ status: OSStatus) -> String {
    if status == errSecUserCanceled { return "cancelled" }
    if status == errSecInteractionNotAllowed || status == errSecNotAvailable {
      return "unavailable"
    }
    if status == errSecAuthFailed { return "invalidated" }
    return "failed"
  }

  private static func flutterError(_ error: NSError?) -> FlutterError {
    guard let errorCode = error?.code else { return Self.error("failed") }
    let code: String
    switch errorCode {
    case LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue,
         LAError.userFallback.rawValue:
      code = "cancelled"
    case LAError.biometryNotAvailable.rawValue, LAError.biometryNotEnrolled.rawValue,
         LAError.biometryLockout.rawValue, LAError.passcodeNotSet.rawValue:
      code = "unavailable"
    default:
      code = "failed"
    }
    return Self.error(code)
  }

  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }
}
