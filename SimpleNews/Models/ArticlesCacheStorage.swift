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

    static func load() -> [Article] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Article].self, from: data)) ?? []
    }

    static func save(_ articles: [Article]) {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
