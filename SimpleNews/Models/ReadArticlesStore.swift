//
//  ReadArticlesStore.swift
//  SimpleNews
//
//  Tracks which articles have been read by the user.
//  Persists a Set<String> of article IDs in UserDefaults.
//

import Foundation

@MainActor
final class ReadArticlesStore: ObservableObject {
    static let shared = ReadArticlesStore()

    private static let storageKey = "read_article_ids"

    @Published private(set) var readIDs: Set<String>

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        self.readIDs = Set(stored)
    }

    func isRead(_ articleID: String) -> Bool {
        readIDs.contains(articleID)
    }

    func markRead(_ articleID: String) {
        guard !readIDs.contains(articleID) else { return }
        readIDs.insert(articleID)
        persist()
    }

    func markUnread(_ articleID: String) {
        guard readIDs.contains(articleID) else { return }
        readIDs.remove(articleID)
        persist()
    }

    func toggleRead(_ articleID: String) {
        if readIDs.contains(articleID) {
            readIDs.remove(articleID)
        } else {
            readIDs.insert(articleID)
        }
        persist()
    }

    func markAllRead(_ articleIDs: [String]) {
        readIDs.formUnion(articleIDs)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(readIDs), forKey: Self.storageKey)
    }
}
