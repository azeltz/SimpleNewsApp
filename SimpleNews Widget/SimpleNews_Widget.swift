//
//  SimpleNews_Widget.swift
//  SimpleNews Widget
//
//  Created by Amir Zeltzer on 3/18/26.
//

import WidgetKit
import SwiftUI

// MARK: - Shared DTO for decoding backend articles

struct WidgetArticleDTO: Codable {
    let id: String?
    let title: String?
    let source: String?
    let publishedAt: String?
    let imageURL: String?
}

struct WidgetArticlesResponse: Codable {
    let articles: [WidgetArticleDTO]
}

// MARK: - Headline Entry

struct HeadlineEntry: TimelineEntry {
    let date: Date
    let headlines: [HeadlineItem]
    let isPlaceholder: Bool

    struct HeadlineItem {
        let id: String
        let title: String
        let source: String?
    }

    static let placeholder = HeadlineEntry(
        date: Date(),
        headlines: [
            HeadlineItem(id: "1", title: "Loading headlines...", source: nil),
        ],
        isPlaceholder: true
    )
}

// MARK: - Headlines Timeline Provider

struct HeadlineTimelineProvider: TimelineProvider {
    typealias Entry = HeadlineEntry

    func placeholder(in context: Context) -> HeadlineEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadlineEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        fetchHeadlines { entry in completion(entry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadlineEntry>) -> Void) {
        fetchHeadlines { entry in
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchHeadlines(completion: @escaping (HeadlineEntry) -> Void) {
        var components = URLComponents(string: "https://rss-aggregator.simplenews.workers.dev/api/news")!
        components.queryItems = [URLQueryItem(name: "userId", value: "widget")]
        let url = components.url!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                let data = data,
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                completion(HeadlineEntry(date: Date(), headlines: [], isPlaceholder: false))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(WidgetArticlesResponse.self, from: data)
                let items = decoded.articles
                    .compactMap { dto -> HeadlineEntry.HeadlineItem? in
                        guard let id = dto.id, let title = dto.title, !title.isEmpty else { return nil }
                        return HeadlineEntry.HeadlineItem(id: id, title: title, source: dto.source)
                    }
                    .prefix(5)

                completion(HeadlineEntry(
                    date: Date(),
                    headlines: Array(items),
                    isPlaceholder: false
                ))
            } catch {
                completion(HeadlineEntry(date: Date(), headlines: [], isPlaceholder: false))
            }
        }.resume()
    }
}

// MARK: - iOS Headlines Widget View

struct HeadlinesWidgetView: View {
    let entry: HeadlineEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        #if os(iOS)
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        #endif
        case .accessoryRectangular:
            lockScreenRectangularView
        case .accessoryInline:
            lockScreenInlineView
        case .accessoryCircular:
            lockScreenCircularView
        default:
            lockScreenRectangularView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "newspaper.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("SimpleNews")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            if let first = entry.headlines.first {
                Text(first.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(4)

                if let source = first.source {
                    Spacer()
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No headlines")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "simplenews://home"))
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "newspaper.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("SimpleNews")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(entry.headlines.prefix(3).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        if let source = item.source {
                            Text(source)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if entry.headlines.isEmpty {
                Text("No headlines available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "simplenews://home"))
    }

    // MARK: - Large Widget

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "newspaper.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("SimpleNews")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(entry.headlines.prefix(5).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    if let source = item.source {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if item.id != entry.headlines.prefix(5).last?.id {
                    Divider()
                }
            }

            if entry.headlines.isEmpty {
                Spacer()
                Text("No headlines available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "simplenews://home"))
    }

    // MARK: - Lock Screen Widgets

    private var lockScreenRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "newspaper.fill")
                    .font(.caption2)
                Text("SimpleNews")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            if let first = entry.headlines.first {
                Text(first.title)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .widgetURL(URL(string: "simplenews://home"))
    }

    private var lockScreenInlineView: some View {
        Group {
            if let first = entry.headlines.first {
                Text(first.title)
            } else {
                Text("SimpleNews")
            }
        }
        .widgetURL(URL(string: "simplenews://home"))
    }

    private var lockScreenCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "newspaper.fill")
                .font(.title3)
        }
        .widgetURL(URL(string: "simplenews://home"))
    }
}

// MARK: - Widget Definition

struct SimpleNews_Widget: Widget {
    let kind: String = "SimpleNews_Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: HeadlineTimelineProvider()
        ) { entry in
            HeadlinesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SimpleNews Headlines")
        .description("Top headlines at a glance.")
        #if os(iOS)
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular,
        ])
        #endif
    }
}

// MARK: - Previews

#if DEBUG && os(iOS)
#Preview("Small", as: .systemSmall) {
    SimpleNews_Widget()
} timeline: {
    HeadlineEntry(
        date: .now,
        headlines: [
            .init(id: "1", title: "NASA's Artemis III Mission Set to Land Astronauts on the Moon", source: "NASA News"),
        ],
        isPlaceholder: false
    )
}

#Preview("Medium", as: .systemMedium) {
    SimpleNews_Widget()
} timeline: {
    HeadlineEntry(
        date: .now,
        headlines: [
            .init(id: "1", title: "NASA's Artemis III Mission Set to Land Astronauts on the Moon", source: "NASA News"),
            .init(id: "2", title: "Tech Giants Report Record Quarterly Earnings", source: "Reuters"),
            .init(id: "3", title: "Climate Summit Reaches Historic Agreement", source: "BBC"),
        ],
        isPlaceholder: false
    )
}
#endif
