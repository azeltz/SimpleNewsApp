//
//  NewsAPIClient.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation

struct NewsdataResponse: Codable {
    let results: [NewsdataArticle]
}

struct NewsdataArticle: Codable {
    let title: String?
    let description: String?
    let content: String?
    let image_url: String?
    let category: [String]?
    let source_id: String?
    let pubDate: String?
    let link: String?
    let tags: [String]?

    func toArticle() -> Article {
        let date: Date?
        if let pubDate = pubDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            date = formatter.date(from: pubDate)
        } else {
            date = nil
        }

        return Article(
            id: UUID().uuidString,
            title: title ?? "Untitled",
            description: description,
            content: content,
            imageURL: URL(string: image_url ?? ""),
            source: source_id,
            category: category?.first,
            publishedAt: date,
            url: URL(string: link ?? ""),
            isSaved: false,
            liked: nil,
            aiTags: tags ?? []
        )
    }
}


final class NewsAPIClient {
    private let apiKey = "pub_8cd7ea8761d74a95bea7b79a5c6cb8dd"
    private let baseURL = URL(string: "https://newsdata.io/api/1/latest")!

    func fetchArticles(params: [String: String]) async throws -> [Article] {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            var queryItems = [URLQueryItem(name: "apikey", value: apiKey)]

            for (key, value) in params {
                queryItems.append(URLQueryItem(name: key, value: value))
            }

            components.queryItems = queryItems

            let url = components.url!
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(NewsdataResponse.self, from: data)
            return decoded.results.map { $0.toArticle() }
        }
    }
