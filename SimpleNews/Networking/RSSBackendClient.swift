//
//  RSSBackendClient.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/16/26.
//

import Foundation

struct RSSBackendArticle: Codable {
    let id: String
    let title: String?
    let url: String?
    let description: String?
    let publishedAt: String?
    let source: String?
    let category: String?
    let imageURL: String?
    // feedId exists in JSON but we can ignore or add it later
}

struct RSSBackendResponse: Codable {
    let articles: [RSSBackendArticle]
}

final class RSSBackendClient {
    // TODO: set your actual Worker URL here
    private let baseURL = URL(string: "https://rss-aggregator.simplenews.workers.dev")!

    func fetchArticles() async throws -> [Article] {
        let url = baseURL.appendingPathComponent("api/news")
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(RSSBackendResponse.self, from: data)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // pubDate format varies; this is a common one. You can tweak later.
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        return decoded.articles.map { item in
            let date: Date?
            if let publishedAt = item.publishedAt {
                date = formatter.date(from: publishedAt)
            } else {
                date = nil
            }

            return Article(
                id: item.id,
                title: item.title ?? "Untitled",
                description: item.description,
                content: nil,
                imageURL: URL(string: item.imageURL ?? ""),
                source: item.source,
                category: item.category,
                publishedAt: date,
                url: URL(string: item.url ?? ""),
                isSaved: false,
                liked: nil,
                aiTags: [] // can add later based on feed/source
            )
        }
    }
}
