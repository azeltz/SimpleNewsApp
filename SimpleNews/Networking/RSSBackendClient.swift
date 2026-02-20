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
    let sourceURL: String?
    // feedId exists in JSON but we can ignore or add it later
}

struct RSSBackendResponse: Codable {
    let articles: [RSSBackendArticle]
    let lastSnapshotAt: String?
}

final class RSSBackendClient {
    private let baseURL = URL(string: "https://rss-aggregator.simplenews.workers.dev")!

    // MARK: - Public API

    /// Fetches articles from /api/news and returns both the mapped articles and the lastSnapshotAt timestamp (if present).
    func fetchArticles() async throws -> (articles: [Article], lastSnapshotAt: Date?) {
        let url = baseURL.appendingPathComponent("api/news")
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(RSSBackendResponse.self, from: data)

        let articles = mapBackendArticles(decoded.articles)
        let snapshotDate = decodeLastSnapshot(decoded.lastSnapshotAt)
        return (articles, snapshotDate)
    }

    /// Updates the dynamic Google News keywords stored in the Worker via POST /keywords.
    func updateKeywords(_ keywords: [String]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("keywords"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Codable { let keywords: [String] }
        let payload = Payload(keywords: keywords)
        request.httpBody = try JSONEncoder().encode(payload)

        _ = try await URLSession.shared.data(for: request)
    }

    /// Optional: one-off Google News search via POST /api/search-news.
    func searchNews(keywords: [String]) async throws -> [Article] {
        guard !keywords.isEmpty else { return [] }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/search-news"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Codable { let keywords: [String] }
        let payload = Payload(keywords: keywords)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(RSSBackendResponse.self, from: data)
        return mapBackendArticles(decoded.articles)
    }

    // MARK: - Mapping helpers

    private func decodeLastSnapshot(_ isoString: String?) -> Date? {
        guard let isoString = isoString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: isoString) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }

    private func mapBackendArticles(_ backendArticles: [RSSBackendArticle]) -> [Article] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        func isGoogleNewsHost(_ host: String?) -> Bool {
            guard let host = host?.lowercased() else { return false }
            if host == "news.google.com" || host.hasSuffix(".news.google.com") { return true }
            if host.hasPrefix("news.google.") { return true }
            return false
        }

        func unwrapGoogleNewsRedirect(_ raw: String?) -> URL? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            guard let url = URL(string: raw) else { return URL(string: raw) }

            if isGoogleNewsHost(url.host) {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    if let target = comps.queryItems?.first(where: { $0.name == "url" || $0.name == "u" })?.value,
                       let unwrapped = URL(string: target) {
                        return unwrapped
                    }
                }
            }

            return url
        }

        func readableHost(from url: URL?) -> String? {
            guard let host = url?.host?.lowercased() else { return nil }
            if isGoogleNewsHost(host) { return nil }
            if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
            return host
        }

        func cleanDescription(_ htmlish: String?) -> String? {
            guard let htmlish, !htmlish.isEmpty else { return htmlish }
            var decoded = htmlish.decodedHTMLEntities
            decoded = decoded
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return decoded.isEmpty ? nil : decoded
        }

        return backendArticles.map { item in
            let date: Date?
            if let publishedAt = item.publishedAt {
                date = formatter.date(from: publishedAt)
            } else {
                date = nil
            }

            let finalURL = unwrapGoogleNewsRedirect(item.url)
            let hostDisplay = readableHost(from: finalURL)

            let finalSource: String? = {
                if isGoogleNewsHost(URL(string: item.url ?? "")?.host),
                   let s = item.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !s.isEmpty {
                    return s
                }
                if let s = item.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !s.isEmpty {
                    return s
                }
                return hostDisplay
            }()

            // Clean description
            var finalDescription = cleanDescription(item.description)

            // If the original link is a Google News URL, hide the description
            if isGoogleNewsHost(URL(string: item.url ?? "")?.host) {
                finalDescription = nil
            }

            return Article(
                id: item.id,
                title: (item.title ?? "Untitled").decodedHTMLEntities,
                description: finalDescription,
                content: nil,
                imageURL: URL(string: item.imageURL ?? ""),
                source: finalSource?.decodedHTMLEntities,
                category: item.category,
                publishedAt: date,
                url: finalURL,
                isSaved: false,
                liked: nil,
                aiTags: []
            )
        }
    }
}
