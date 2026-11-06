import CryptoKit
import Foundation
import Security

/// Encrypts undeveloped frames inside the app sandbox (AES-GCM, key kept in the Keychain).
final class Vault {
    static let shared = Vault()

    let root: URL
    private let key: SymmetricKey

    private init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Rollcam", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        key = Vault.loadOrCreateKey(fallbackDirectory: root)
    }

    func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }

    private static let account = "com.ran.rollcam.latent-key"

    private static func loadOrCreateKey(fallbackDirectory: URL) -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }

        // Some sideloading setups have no usable keychain group; fall back to a protected file.
        let fileURL = fallbackDirectory.appendingPathComponent(".latent-key")
        if let data = try? Data(contentsOf: fileURL), data.count == 32 {
            return SymmetricKey(data: data)
        }

        let newKey = SymmetricKey(size: .bits256)
        let raw = newKey.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: raw,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            try? raw.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return newKey
    }
}
