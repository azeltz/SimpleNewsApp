//
// SavedArticlesStorage.swift
// SimpleNews
//
// Created by Amir Zeltzer on 2/13/26.
//

import Foundation

private let savedArticlesKey = "savedArticles"

struct SavedArticlesStorage {
    static func load() -> [SavedArticle] {
        guard let data = UserDefaults.standard.data(forKey: savedArticlesKey) else {
            return []
        }
        if let decoded = try? JSONDecoder().decode([SavedArticle].self, from: data) {
            return decoded
        }
        return []
    }

    static func save(_ articles: [SavedArticle]) {
        if let data = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(data, forKey: savedArticlesKey)
        }
    }
}
