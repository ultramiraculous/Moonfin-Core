import Flutter
import Foundation
import Security

/// One keychain item every Apple TV user can read, for what all of them should
/// see: the saved servers and accounts, and the PINs guarding them. Everything
/// else the app keeps is separate for each Apple TV user.
@MainActor
final class AppleTvSharedStoreChannel: NSObject {
    private let channel: FlutterMethodChannel

    private static let service = "org.moonfin.app.shared"
    private static let account = "device"

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "moonfin/appletv_shared_store", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseUserIndependentKeychain: kCFBooleanTrue as Any,
        ]
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "read":
            result(Self.read())
        case "write":
            guard let value = call.arguments as? String else {
                result(FlutterError(code: "invalid_value", message: nil, details: nil))
                return
            }
            let status = Self.write(value)
            if status == errSecSuccess {
                result(nil)
            } else {
                result(FlutterError(
                    code: "keychain_\(status)", message: nil, details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// The stored text, an empty string when nothing is stored yet, or an
    /// error when the shared keychain can't be used, such as in a build
    /// signed without the User Management entitlement.
    private static func read() -> Any? {
        var query = baseQuery
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        case errSecItemNotFound:
            return ""
        default:
            return FlutterError(code: "keychain_\(status)", message: nil, details: nil)
        }
    }

    private static func write(_ value: String) -> OSStatus {
        let data = Data(value.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var add = baseQuery
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }
}
