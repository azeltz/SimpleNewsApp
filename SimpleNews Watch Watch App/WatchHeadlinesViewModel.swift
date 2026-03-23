//
//  WatchHeadlinesViewModel.swift
//  SimpleNewsWatch
//
//  Fetches headlines from the RSS backend for display on Apple Watch.
//

import Foundation
import Combine

@MainActor
final class WatchHeadlinesViewModel: ObservableObject {
    @Published var headlines: [WatchHeadline] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// IDs of articles saved on iOS. Updated via WatchConnectivity.
    @Published var savedIDs: Set<String> = []

    /// AI summary text received from the iPhone.
    @Published var aiSummary: String?

    /// Whether the user has enabled AI summary display.
    @Published var enableAISummary: Bool = true

    /// User ID synced from iPhone, used to fetch the same personalized feed.
    @Published var userId: String?

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

    func loadHeadlines() async {
        isLoading = true
        errorMessage = nil

        do {
            var components = URLComponents(string: "https://rss-aggregator.simplenews.workers.dev/api/news")!
            components.queryItems = [URLQueryItem(name: "userId", value: userId ?? "watch")]
            let url = components.url!

            var request = URLRequest(url: url)
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                errorMessage = "Server error"
                isLoading = false
                return
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
            headlines = articlesResponse.articles.prefix(20).compactMap { article in
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
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
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
