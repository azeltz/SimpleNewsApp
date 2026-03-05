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

    private func fetchComplicationData(completion: @escaping (ComplicationEntry) -> Void) {
        var components = URLComponents(string: "https://rss-aggregator.simplenews.workers.dev/api/news")!
        components.queryItems = [URLQueryItem(name: "userId", value: "watch")]
        let url = components.url!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

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
                let first = decoded.articles.first(where: { $0.title != nil && !($0.title?.isEmpty ?? true) })

                // Count articles published since midnight (local time)
                let startOfDay = Calendar.current.startOfDay(for: Date())
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

                let newCount = decoded.articles.compactMap { article -> Date? in
                    guard let raw = article.publishedAt else { return nil }
                    return dateFormatter.date(from: raw)
                }.filter { $0 >= startOfDay }.count

                completion(ComplicationEntry(
                    date: Date(),
                    topHeadlineTitle: first?.title,
                    topHeadlineSource: first?.source,
                    topHeadlineID: first?.id,
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

private struct ComplicationArticlesResponse: Codable {
    let articles: [ComplicationArticleDTO]
}

private struct ComplicationArticleDTO: Codable {
    let id: String?
    let title: String?
    let source: String?
    let publishedAt: String?
}

// MARK: - Complication Views

/// Renders the appropriate layout based on widget family.
struct SimpleNewsComplicationView: View {
    let entry: ComplicationEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Launcher: icon-only, tap opens main articles list
            circularView
        case .accessoryCorner:
            // Corner: small icon with date
            cornerView
        case .accessoryRectangular:
            // Top Headline or Daily Summary text
            rectangularView
        case .accessoryInline:
            // Single line of text
            inlineView
        default:
            // Fallback for any other family
            circularView
        }
    }

    // MARK: - Circular (Launcher)

    /// Icon-only launcher. Tap opens the watch app main articles list.
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "newspaper.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .widgetURL(URL(string: "simplenews://home"))
    }

    // MARK: - Corner (Date + Icon)

    /// Small icon/monogram plus today's date.
    /// Tap opens the main articles list.
    private var cornerView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(dayNumber)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(weekdayAbbrev)
                    .font(.system(size: 8, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        // Tap opens main list
        .widgetURL(URL(string: "simplenews://home"))
    }

    // MARK: - Rectangular (Top Headline / Daily Summary)

    /// Shows truncated top headline with source, or Daily Summary with new count.
    /// Tap opens article detail (if headline) or AI summary (if no headline).
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = entry.topHeadlineTitle {
                // Top Headline mode
                HStack(spacing: 4) {
                    Image(systemName: "newspaper.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("SimpleNews")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                if let source = entry.topHeadlineSource {
                    Text(source)
                        .font(.caption2)
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

    /// Single line: truncated headline title or "SimpleNews · N new"
    private var inlineView: some View {
        Group {
            if let title = entry.topHeadlineTitle {
                Text(title)
            } else if entry.newArticleCount > 0 {
                Text("SimpleNews · \(entry.newArticleCount) new")
            } else {
                Text("SimpleNews")
            }
        }
        .widgetURL(complicationDeepLink)
    }

    // MARK: - Helpers

    /// Deep link: article detail if we have a headline ID, otherwise summary
    private var complicationDeepLink: URL {
        if let id = entry.topHeadlineID {
            return URL(string: "simplenews://article/\(id)")!
        }
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
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
        #endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Circular", as: .accessoryCircular) {
    SimpleNewsComplication()
} timeline: {
    ComplicationEntry.placeholder
}

#Preview("Corner", as: .accessoryCorner) {
    SimpleNewsComplication()
} timeline: {
    ComplicationEntry(
        date: Date(),
        topHeadlineTitle: nil,
        topHeadlineSource: nil,
        topHeadlineID: nil,
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
