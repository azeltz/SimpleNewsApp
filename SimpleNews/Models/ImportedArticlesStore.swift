//
//  ImportedArticlesStore.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation

@MainActor
final class ImportedArticlesStore: ObservableObject {
    private static let storageKey = "importedArticles"

    @Published var articles: [Article] = []

    init() {
        load()
    }

    func add(_ article: Article) {
        articles.insert(article, at: 0)
        save()
    }

    func remove(at offsets: IndexSet) {
        articles.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Article].self, from: data) else { return }
        articles = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
