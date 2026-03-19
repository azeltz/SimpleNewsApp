//
//  ArticlesCacheStorage.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/20/26.
//

import Foundation

struct ArticlesCacheStorage {
    private static let url = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("latest_articles.json")

    /// Maximum number of articles to retain on disk.
    /// Keeps the cache file small and Documents & Data footprint low.
    static let maxRetainedArticles = 200

    /// Maximum age for cached articles (7 days). Older articles are pruned on save.
    static let maxRetentionInterval: TimeInterval = 7 * 24 * 60 * 60

    static func load() -> [Article] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([Article].self, from: data)
        } catch {
            Log.data.error("ArticlesCacheStorage: decode failed – \(error)")
            return []
        }
    }

    static func save(_ articles: [Article]) {
        // Prune: keep only articles within the retention window, capped at maxRetainedArticles
        let cutoff = Date().addingTimeInterval(-maxRetentionInterval)
        let pruned = articles
            .filter { ($0.publishedAt ?? .distantPast) > cutoff }
            .prefix(maxRetainedArticles)

        guard let data = try? JSONEncoder().encode(Array(pruned)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Remove all cached articles from disk.
    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
