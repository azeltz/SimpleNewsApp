//
//  SimpleNewsComplication.swift
//  SimpleNews Watch
//
//  watchOS WidgetKit complications using a single timeline provider
//  that renders different layouts depending on the widget family.
//
//  Family mapping:
//  - accessoryCorner / accessoryCircular → Launcher (icon/monogram, tap opens main list)
//  - accessoryRectangular → Top Headline or Daily Summary text
//  - accessoryInline → Short headline text
//
//  Deep links:
//  - simplenews://home         → opens main articles list
//  - simplenews://summary      → opens AI Daily Summary view
//  - simplenews://article/<id> → opens specific article detail
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let topHeadlineTitle: String?
    let topHeadlineSource: String?
    let topHeadlineID: String?
    let newArticleCount: Int
    let isPlaceholder: Bool

    static let placeholder = ComplicationEntry(
        date: Date(),
        topHeadlineTitle: "Loading headlines...",
        topHeadlineSource: nil,
        topHeadlineID: nil,
        newArticleCount: 0,
        isPlaceholder: true
    )
}

// MARK: - Single Timeline Provider

struct SimpleNewsComplicationProvider: TimelineProvider {
    typealias Entry = ComplicationEntry

    func placeholder(in context: Context) -> ComplicationEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        fetchComplicationData { entry in
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        fetchComplicationData { entry in
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private static let emptyEntry = ComplicationEntry(
        date: Date(), topHeadlineTitle: nil, topHeadlineSource: nil,
        topHeadlineID: nil, newArticleCount: 0, isPlaceholder: false
    )

    private func fetchComplicationData(completion: @escaping (ComplicationEntry) -> Void) {
        guard var components = URLComponents(string: "https://rss-aggregator.amiracle.workers.dev/api/news") else {
            completion(Self.emptyEntry); return
        }
        components.queryItems = [URLQueryItem(name: "userId", value: "watch")]
        guard let url = components.url else {
            completion(Self.emptyEntry); return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        // Load blocked tags from the shared App Group container
        let blockedTags: Set<String> = {
            guard let shared = UserDefaults(suiteName: "group.com.simplenews.shared"),
                  let tags = shared.stringArray(forKey: "blockedTags") else { return [] }
            return Set(tags.map { $0.lowercased() })
        }()

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                let data = data,
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                completion(ComplicationEntry(
                    date: Date(),
                    topHeadlineTitle: nil,
                    topHeadlineSource: nil,
                    topHeadlineID: nil,
                    newArticleCount: 0,
                    isPlaceholder: false
                ))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ComplicationArticlesResponse.self, from: data)

                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

                let dateFormatterAlt = DateFormatter()
                dateFormatterAlt.locale = Locale(identifier: "en_US_POSIX")
                dateFormatterAlt.timeZone = TimeZone(secondsFromGMT: 0)
                dateFormatterAlt.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"

                let now = Date()
                let startOfDay = Calendar.current.startOfDay(for: now)

                // Parse dates with the future-date fix, filter blocked tags
                let articlesWithDates: [(ComplicationArticleDTO, Date?)] = decoded.articles.compactMap { article in
                    // Filter out articles matching blocked tags
                    if let category = article.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                       !category.isEmpty,
                       blockedTags.contains(category) {
                        return nil
                    }

                    var date: Date? = article.publishedAt.flatMap { raw in
                        var str = raw
                        if str.hasPrefix("<![CDATA[") && str.hasSuffix("]]>") {
                            str = String(str.dropFirst(9).dropLast(3))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        return dateFormatter.date(from: str) ?? dateFormatterAlt.date(from: str)
                    }

                    // Fix future dates (EDT/EST mislabeling)
                    if let d = date, d > now {
                        let drift = d.timeIntervalSince(now)
                        if drift <= 3600 {
                            date = d.addingTimeInterval(-3600)
                        } else {
                            date = now
                        }
                    }

                    return (article, date)
                }

                let first = articlesWithDates.first(where: { $0.0.title != nil && !($0.0.title?.isEmpty ?? true) })
                let newCount = articlesWithDates.compactMap { $0.1 }.filter { $0 >= startOfDay }.count

                completion(ComplicationEntry(
                    date: Date(),
                    topHeadlineTitle: first?.0.title,
                    topHeadlineSource: first?.0.source,
                    topHeadlineID: first?.0.id,
                    newArticleCount: newCount,
                    isPlaceholder: false
                ))
            } catch {
                completion(ComplicationEntry(
                    date: Date(),
                    topHeadlineTitle: nil,
                    topHeadlineSource: nil,
                    topHeadlineID: nil,
                    newArticleCount: 0,
                    isPlaceholder: false
                ))
            }
        }.resume()
    }
}

private struct ComplicationArticlesResponse: Codable, Sendable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.articles = try container.decode([ComplicationArticleDTO].self, forKey: .articles)
    }

    let articles: [ComplicationArticleDTO]
}

private struct ComplicationArticleDTO: Codable, Sendable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
    }

    let id: String?
    let title: String?
    let source: String?
    let publishedAt: String?
    let category: String?
}

// MARK: - Complication Views

/// Renders the appropriate layout based on widget family.
struct SimpleNewsComplicationView: View {
    let entry: ComplicationEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                cornerView
            case .accessoryRectangular:
                rectangularView
            case .accessoryInline:
                inlineView
            default:
                cornerView
            }
        }
        .privacySensitive(false)
    }

    // MARK: - Corner (Icon + Headline)

    /// Small icon in the corner slot with headline text curving around the watch face.
    /// The `widgetLabel` renders as the curved outer text.
    private var cornerView: some View {
        Image(systemName: "newspaper.fill")
            .font(.title3)
            .widgetAccentable()
            .widgetLabel {
                if let title = entry.topHeadlineTitle {
                    Text(summarize(title, maxLength: 20))
                } else {
                    Text("SimpleNews")
                }
            }
            .widgetURL(complicationDeepLink)
    }

    // MARK: - Rectangular (Top Headline / Daily Summary)

    /// Shows truncated top headline with source, or Daily Summary with new count.
    /// Tap opens article detail (if headline) or AI summary (if no headline).
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = entry.topHeadlineTitle {
                // Top Headline mode
                HStack(spacing: 3) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 8))
                        .widgetAccentable()
                    Text("SimpleNews")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(summarize(title, maxLength: 50))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if let source = entry.topHeadlineSource {
                    Text(source)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                // Daily Summary mode
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text("SimpleNews Summary")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                if entry.newArticleCount > 0 {
                    Text("Daily Digest · \(entry.newArticleCount) new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Daily Digest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(complicationDeepLink)
    }

    // MARK: - Inline

    /// Single line: summarized headline or "SimpleNews"
    private var inlineView: some View {
        ViewThatFits {
            if let title = entry.topHeadlineTitle {
                Text(summarize(title, maxLength: 35))
            } else {
                Text("SimpleNews")
            }
        }
        .widgetURL(complicationDeepLink)
    }

    // MARK: - Helpers

    /// Condenses a headline to fit within a character limit.
    ///
    /// Processing order:
    /// 1. Strip label prefixes before a colon ("Elite longevity: Flacco..." → "Flacco...")
    /// 2. Remove appositional/parenthetical clauses (", 41," or "(AP)" etc.)
    /// 3. Collapse filler words ("agrees to a contract with" → "agrees to deal")
    /// 4. Truncate at the last word boundary if still too long
    private func summarize(_ text: String, maxLength: Int) -> String {
        var h = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Strip short prefix labels before a colon
        if h.count > maxLength,
           let colonRange = h.range(of: ": "),
           h.distance(from: h.startIndex, to: colonRange.lowerBound) < 25 {
            let after = String(h[colonRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty { h = after }
        }

        // 2) Strip leading and trailing quotes/brackets
        let quoteChars = CharacterSet(charactersIn: "'\"\u{2018}\u{2019}\u{201C}\u{201D}")
        while let first = h.unicodeScalars.first, quoteChars.contains(first) || first == "(" {
            h = String(h.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        while let last = h.unicodeScalars.last, quoteChars.contains(last) {
            h = String(h.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        // 3) Remove appositional clauses: ", 41," or ", age 23," or "(AP)" etc.
        //    Matches ", <short text>," where the inner text is ≤15 chars
        h = h.replacingOccurrences(
            of: #",\s[^,]{1,15},"#,
            with: "",
            options: .regularExpression
        )
        // Remove inline parentheticals like "(AP)" or "(report)"
        h = h.replacingOccurrences(
            of: #"\s*\([^)]{1,20}\)"#,
            with: "",
            options: .regularExpression
        )

        // 4) Collapse verbose contract/deal phrasing
        let dealPatterns: [(String, String)] = [
            (#"agrees to (?:a )?(?:\d+[ -]year )?\$?[\d.]+ (?:million |billion )?(?:contract|deal|extension)(?: with .+)?"#, "agrees to deal"),
            (#"agrees to (?:a )?(?:contract|deal|extension) with .+"#, "agrees to deal"),
            (#"agrees to (?:terms|a deal|contract) with the (.+)"#, "agrees to $1 deal"),
            (#"has been (?:traded|sent) to the (.+?)(?:\s+(?:for|in exchange).*)?"#, "traded to $1"),
            (#"is expected to (?:sign|join|agree)"#, "expected to sign"),
            (#"sources? (?:say|said|tell|told) "#, ""),
            (#"according to (?:a |multiple )?(?:sources?|reports?|ESPN)"#, ""),
        ]
        for (pattern, replacement) in dealPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                h = regex.stringByReplacingMatches(
                    in: h,
                    range: NSRange(h.startIndex..., in: h),
                    withTemplate: replacement
                )
            }
        }

        // Clean up double spaces and trailing punctuation artifacts
        while h.contains("  ") {
            h = h.replacingOccurrences(of: "  ", with: " ")
        }
        h = h.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.trimmingCharacters(in: CharacterSet(charactersIn: ",.;: "))

        guard h.count > maxLength else { return h }

        // 5) Truncate at last word boundary
        let cutoff = h.index(h.startIndex, offsetBy: maxLength - 1)
        let sub = h[h.startIndex..<cutoff]
        if let lastSpace = sub.lastIndex(of: " ") {
            return String(h[h.startIndex..<lastSpace]) + "…"
        }
        return String(sub) + "…"
    }

    /// Deep link: article detail if we have a headline ID, otherwise summary
    private var complicationDeepLink: URL {
        if let id = entry.topHeadlineID,
           let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "simplenews://article/\(encoded)") {
            return url
        }
        // Safe: static string, always valid
        return URL(string: "simplenews://summary")!
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: entry.date)
    }

    private var weekdayAbbrev: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: entry.date).uppercased()
    }
}

// MARK: - Widget Definition

struct SimpleNewsComplication: Widget {
    let kind: String = "SimpleNewsComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SimpleNewsComplicationProvider()
        ) { entry in
            SimpleNewsComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SimpleNews")
        .description("Quick access to headlines, daily summary, or launch SimpleNews.")
        #if os(watchOS)
        .supportedFamilies([
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
        #endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Corner", as: .accessoryCorner) {
    SimpleNewsComplication()
} timeline: {
    ComplicationEntry(
        date: Date(),
        topHeadlineTitle: "NASA's Artemis III Mission Set to Land Astronauts on the Moon",
        topHeadlineSource: "NASA News",
        topHeadlineID: "artemis-3",
        newArticleCount: 5,
        isPlaceholder: false
    )
}

#Preview("Rectangular - Headline", as: .accessoryRectangular) {
    SimpleNewsComplication()
} timeline: {
    ComplicationEntry(
        date: Date(),
        topHeadlineTitle: "NASA's Artemis III Mission Set to Land Astronauts on the Moon",
        topHeadlineSource: "NASA News",
        topHeadlineID: "artemis-3",
        newArticleCount: 12,
        isPlaceholder: false
    )
}

#Preview("Rectangular - Summary", as: .accessoryRectangular) {
    SimpleNewsComplication()
} timeline: {
    ComplicationEntry(
        date: Date(),
        topHeadlineTitle: nil,
        topHeadlineSource: nil,
        topHeadlineID: nil,
        newArticleCount: 8,
        isPlaceholder: false
    )
}

#Preview("Inline", as: .accessoryInline) {
    SimpleNewsComplication()
} timeline: {
    ComplicationEntry(
        date: Date(),
        topHeadlineTitle: "Tech Giants Report Record Quarterly Earnings",
        topHeadlineSource: "Reuters",
        topHeadlineID: "tech-earnings",
        newArticleCount: 3,
        isPlaceholder: false
    )
}
#endif
