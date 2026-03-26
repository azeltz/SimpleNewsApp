//
//  WatchHeadlinesViewModel.swift
//  SimpleNewsWatch
//
//  Fetches headlines from the RSS backend for display on Apple Watch.
//  Includes a lightweight disk cache so headlines are available offline.
//

import SwiftUI

@MainActor
@Observable
final class WatchHeadlinesViewModel {
    var headlines: [WatchHeadline] = []
    var isLoading: Bool = false
    var errorMessage: String?

    /// IDs of articles saved on iOS. Updated via WatchConnectivity.
    var savedIDs: Set<String> = []

    /// AI summary text received from the iPhone.
    var aiSummary: String?

    /// Whether the user has enabled AI summary display.
    var enableAISummary: Bool = true

    /// User ID synced from iPhone, used to fetch the same personalized feed.
    var userId: String?

    /// Maximum number of automatic retries on network failure.
    private let maxRetries = 2

    // MARK: - Saved state

    /// Toggle a headline's saved state locally and update savedIDs.
    func markSaved(id: String, isSaved: Bool) {
        if isSaved {
            savedIDs.insert(id)
        } else {
            savedIDs.remove(id)
        }
        refreshSavedFlags()
    }

    /// Recompute isSaved on all headlines from the current savedIDs set.
    func refreshSavedFlags() {
        for i in headlines.indices {
            headlines[i].isSaved = savedIDs.contains(headlines[i].id)
        }
    }

    // MARK: - Load headlines (with retry + offline cache)

    func loadHeadlines() async {
        // 1) Show cached headlines immediately if the live list is empty.
        if headlines.isEmpty {
            let cached = WatchHeadlineCache.load()
            if !cached.isEmpty {
                headlines = cached
                refreshSavedFlags()
            }
        }

        isLoading = true
        errorMessage = nil

        // 2) Fetch from network with automatic retry on transient errors.
        var lastError: Error?
        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Brief back-off between retries (1s, 2s).
                try? await Task.sleep(for: .seconds(attempt))
            }

            do {
                let fetched = try await fetchFromNetwork()
                headlines = fetched
                refreshSavedFlags()
                WatchHeadlineCache.save(fetched)
                errorMessage = nil
                isLoading = false
                return
            } catch {
                lastError = error
            }
        }

        // All retries exhausted — show error only if we have no cached data.
        if headlines.isEmpty {
            errorMessage = "Failed to load: \(lastError?.localizedDescription ?? "Unknown error")"
        }
        isLoading = false
    }

    // MARK: - Network fetch

    private func fetchFromNetwork() async throws -> [WatchHeadline] {
        guard var components = URLComponents(string: "https://rss-aggregator.amiracle.workers.dev/api/news") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "userId", value: userId ?? "watch")]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let articlesResponse = try JSONDecoder().decode(WatchArticlesResponse.self, from: data)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        // ESPN uses single-digit day and timezone abbreviation
        let dateFormatterAlt = DateFormatter()
        dateFormatterAlt.locale = Locale(identifier: "en_US_POSIX")
        dateFormatterAlt.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatterAlt.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"

        let now = Date()
        return articlesResponse.articles.prefix(20).compactMap { article in
            guard let title = article.title, !title.isEmpty else { return nil }
            var date: Date? = article.publishedAt.flatMap { raw in
                var str = raw
                if str.hasPrefix("<![CDATA[") && str.hasSuffix("]]>") {
                    str = String(str.dropFirst(9).dropLast(3))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return dateFormatter.date(from: str) ?? dateFormatterAlt.date(from: str)
            }

            // Fix future dates — feeds often mislabel EDT as EST (off by 1 hour).
            if let d = date, d > now {
                let drift = d.timeIntervalSince(now)
                if drift <= 3600 {
                    date = d.addingTimeInterval(-3600)
                } else {
                    date = now
                }
            }

            let id = article.id ?? UUID().uuidString
            return WatchHeadline(
                id: id,
                title: title,
                source: article.source,
                publishedAt: date,
                urlString: article.url,
                description: article.description,
                isSaved: savedIDs.contains(id)
            )
        }
    }
}

// MARK: - Response models (matches RSSBackendClient format)

private struct WatchArticlesResponse: Codable {
    let articles: [WatchArticleDTO]
}

private struct WatchArticleDTO: Codable {
    let id: String?
    let title: String?
    let source: String?
    let publishedAt: String?
    let url: String?
    let description: String?
}

// MARK: - Lightweight disk cache for offline headline display

enum WatchHeadlineCache {
    private static let cacheKey = "cachedWatchHeadlines"

    struct CachedHeadline: Codable {
        let id: String
        let title: String
        let source: String?
        let publishedAt: Date?
        let urlString: String?
        let description: String?
    }

    static func save(_ headlines: [WatchHeadline]) {
        let codable = headlines.map {
            CachedHeadline(
                id: $0.id, title: $0.title, source: $0.source,
                publishedAt: $0.publishedAt, urlString: $0.urlString,
                description: $0.description
            )
        }
        guard let data = try? JSONEncoder().encode(codable) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    static func load() -> [WatchHeadline] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedHeadline].self, from: data) else {
            return []
        }
        // Discard cache older than 24 hours.
        if let newest = cached.compactMap(\.publishedAt).max(),
           Date().timeIntervalSince(newest) > 24 * 3600 {
            return []
        }
        return cached.map {
            WatchHeadline(
                id: $0.id, title: $0.title, source: $0.source,
                publishedAt: $0.publishedAt, urlString: $0.urlString,
                description: $0.description, isSaved: false
            )
        }
    }
}

