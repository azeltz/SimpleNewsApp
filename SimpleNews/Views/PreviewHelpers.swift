//
//  PreviewHelpers.swift
//  SimpleNews
//
//  Sample data and mock dependencies for SwiftUI previews.
//

#if DEBUG
import SwiftUI

// MARK: - Sample Articles

enum PreviewData {
    static let sampleArticle = Article(
        id: "preview-1",
        title: "NASA's Artemis III Mission Set to Land Astronauts on the Moon",
        description: "NASA announced that the Artemis III crew will attempt a lunar landing in late 2026, marking humanity's return to the Moon after more than 50 years.",
        content: "NASA announced that the Artemis III crew will attempt a lunar landing in late 2026, marking humanity's return to the Moon after more than 50 years. The mission will use the SpaceX Starship as the human landing system.",
        imageURL: URL(string: "https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?w=400"),
        source: "NASA News",
        category: "Science",
        publishedAt: Date().addingTimeInterval(-3600),
        url: URL(string: "https://nasa.gov/artemis-iii"),
        isSaved: false,
        liked: nil,
        aiTags: ["Space", "NASA", "Moon"],
        readerImageURL: nil
    )

    static let sampleArticle2 = Article(
        id: "preview-2",
        title: "Tech Giants Report Record Quarterly Earnings",
        description: "Major technology companies exceeded Wall Street expectations with strong revenue growth driven by AI-related products and cloud services.",
        content: nil,
        imageURL: URL(string: "https://images.unsplash.com/photo-1518770660439-4636190af475?w=400"),
        source: "Reuters",
        category: "Technology",
        publishedAt: Date().addingTimeInterval(-7200),
        url: URL(string: "https://reuters.com/tech-earnings"),
        isSaved: true,
        liked: true,
        aiTags: ["AI", "Earnings"],
        readerImageURL: nil
    )

    static let sampleArticle3 = Article(
        id: "preview-3",
        title: "Champions League Quarter-Finals Draw Revealed",
        description: "UEFA has confirmed the matchups for the Champions League quarter-finals, with several high-profile clashes expected.",
        content: nil,
        imageURL: nil,
        source: "ESPN",
        category: "Sports",
        publishedAt: Date().addingTimeInterval(-10800),
        url: URL(string: "https://espn.com/champions-league"),
        isSaved: false,
        liked: nil,
        aiTags: ["Football", "UEFA"],
        readerImageURL: nil
    )

    static let sampleArticles: [Article] = [sampleArticle, sampleArticle2, sampleArticle3]

    static let sampleGroup = ArticleGroup(
        id: "group-1",
        canonicalTitle: sampleArticle.title,
        primaryArticle: sampleArticle,
        allArticles: [sampleArticle]
    )

    static let sampleMultiGroup = ArticleGroup(
        id: "group-2",
        canonicalTitle: sampleArticle2.title,
        primaryArticle: sampleArticle2,
        allArticles: [sampleArticle2, sampleArticle3]
    )

    static let sampleGroups: [ArticleGroup] = [sampleGroup, sampleMultiGroup]

    static let sampleSavedArticle = SavedArticle(
        id: "saved-1",
        title: sampleArticle.title,
        description: sampleArticle.description,
        imageURL: sampleArticle.imageURL,
        source: sampleArticle.source,
        publishedAt: sampleArticle.publishedAt,
        url: sampleArticle.url
    )
}

// MARK: - Preview Environment Wrapper

/// Wraps a view with all necessary environment objects for previews.
struct PreviewWrapper<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var usageTracker = UsageTracker()
    @StateObject private var importedStore = ImportedArticlesStore()
    @StateObject private var sourcesStore = UserSourcesStore()

    var body: some View {
        content
            .environmentObject(settingsStore)
            .environmentObject(usageTracker)
            .environmentObject(importedStore)
            .environmentObject(sourcesStore)
    }
}
#endif
