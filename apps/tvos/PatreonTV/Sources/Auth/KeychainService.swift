//
//  KeychainService.swift
//  PatreonTV
//
//  Thin wrapper over the Security framework. Stores small strings scoped
//  to this app's bundle. Values persist across launches and app updates.
//

import Foundation
import Security
import os.log

struct KeychainService {

    let service: String

    private static let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Keychain")

    /// Returns false if the write failed — callers can surface this instead of
    /// silently appearing signed in until the next launch.
    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        let data = Data(value.utf8)

        // Delete any existing item first.
        remove(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Self.log.error("Keychain write failed for \(key, privacy: .public): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    func remove(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Self.log.error("Keychain delete failed for \(key, privacy: .public): OSStatus \(status)")
        }
    }
}
