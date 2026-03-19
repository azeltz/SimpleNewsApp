//
//  UserIdManager.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation
import Security

enum UserIdManager {
    private static let keychainService = "com.simplenews.userId"
    private static let keychainAccount = "simpleNewsUserId"

    // Legacy UserDefaults key (used for migration only)
    private static let legacyDefaultsKey = "simpleNewsUserId"

    /// Returns the persistent user ID, creating one on first access.
    /// Stored in the Keychain so it survives backup/restore cycles.
    static var current: String {
        // 1) Try Keychain first
        if let existing = readFromKeychain() {
            return existing
        }

        // 2) Migrate from UserDefaults if present
        if let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey) {
            saveToKeychain(legacy)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return legacy
        }

        // 3) Generate a new ID
        let newId = UUID().uuidString
        saveToKeychain(newId)
        return newId
    }

    // MARK: - Keychain helpers

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
