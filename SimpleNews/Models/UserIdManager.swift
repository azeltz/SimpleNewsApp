//
//  UserIdManager.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation

enum UserIdManager {
    private static let key = "simpleNewsUserId"

    /// Returns the persistent user ID, creating one on first access.
    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}
