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
    let publishedTs: Double?  // Unix timestamp in milliseconds
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

/// Central backend base URL used across the app.
let simpleNewsBackendBaseURL = URL(string: "https://rss-aggregator.simplenews.workers.dev")!

final class RSSBackendClient {
    private let baseURL = simpleNewsBackendBaseURL

    // MARK: - Public API

    /// Fetches articles from /api/news and returns both the mapped articles and the lastSnapshotAt timestamp (if present).
    func fetchArticles() async throws -> (articles: [Article], lastSnapshotAt: Date?) {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/news"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "userId", value: UserIdManager.current)]
        let url = components.url!
        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

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

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
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

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

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
        // Primary format: RFC 822 with two-digit day and numeric timezone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        // ESPN uses single-digit day and timezone abbreviation (e.g. "Wed, 4 Mar 2026 19:25:19 EST")
        let formatterSingleDay = DateFormatter()
        formatterSingleDay.locale = Locale(identifier: "en_US_POSIX")
        formatterSingleDay.timeZone = TimeZone(secondsFromGMT: 0)
        formatterSingleDay.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"

        func isGoogleNewsHost(_ host: String?) -> Bool {
            guard let host = host?.lowercased() else { return false }
            if host == "news.google.com" || host.hasSuffix(".news.google.com") { return true }
            if host.hasPrefix("news.google.") { return true }
            return false
        }

        func unwrapGoogleNewsRedirect(_ raw: String?) -> URL? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            guard let url = URL(string: raw) else {
                // Try percent-encoding the raw string as a fallback
                return raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                    .flatMap { URL(string: $0) }
            }

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
            var decoded = htmlish.strippedHTMLTags.decodedHTMLEntities
            decoded = decoded
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return decoded.isEmpty ? nil : decoded
        }

        let now = Date()

        func sanitizedImageURL(_ raw: String?) -> URL? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            if let url = URL(string: raw) { return url }
            // Percent-encode as a fallback for URLs with spaces or special chars
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                .flatMap { URL(string: $0) }
            if encoded == nil {
                Log.network.warning("RSSBackendClient: could not parse imageURL: \(raw)")
            }
            return encoded
        }

        return backendArticles.map { item in
            var date: Date?
            if let ts = item.publishedTs, ts > 0 {
                date = Date(timeIntervalSince1970: ts / 1000.0)
            } else if var publishedAt = item.publishedAt {
                // Strip CDATA wrapper if present (some Ynet feeds)
                // "<![CDATA[" is 9 chars, "]]>" is 3 chars → minimum valid length is 12
                if publishedAt.hasPrefix("<![CDATA[") && publishedAt.hasSuffix("]]>") && publishedAt.count >= 12 {
                    publishedAt = String(publishedAt.dropFirst(9).dropLast(3))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                date = formatter.date(from: publishedAt)
                    ?? formatterSingleDay.date(from: publishedAt)
            } else {
                date = nil
            }

            // Fix future dates — feeds often mislabel EDT as EST (off by 1 hour).
            // If the date is in the future but within 1 hour, shift it back by
            // 1 hour so the article keeps its real relative ordering instead of
            // all appearing as "now".
            if let d = date, d > now {
                let drift = d.timeIntervalSince(now)
                if drift <= 3600 {
                    date = d.addingTimeInterval(-3600)
                } else {
                    date = now
                }
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
                imageURL: sanitizedImageURL(item.imageURL),
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
