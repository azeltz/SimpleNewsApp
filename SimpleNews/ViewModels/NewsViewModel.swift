//
//  NewsViewModel.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation
import WebKit

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    @Published var tagWeights: [String: Double] = TagWeightsStorage.load()
    @Published var settings: AppSettings = AppSettings.load()

    @Published var searchText: String = ""
    @Published var searchInTitle = true
    @Published var searchInDescription = true
    @Published var searchInTags = true

    /// Last time the Worker snapshot was taken (meta:last_snapshot_at).
    @Published var lastSnapshotAt: Date? = nil
    
    var filteredArticles: [Article] {
        guard !searchText.isEmpty else { return articles }
        let query = searchText.lowercased()

        return articles.filter { article in
            var matches = false

            if searchInTitle {
                matches = matches || article.title.lowercased().contains(query)
            }
            if searchInDescription, let desc = article.description?.lowercased() {
                matches = matches || desc.contains(query)
            }
            if searchInTags {
                let tags = article.tags.joined(separator: " ").lowercased()
                matches = matches || tags.contains(query)
            }

            return matches
        }
    }
    
    private func startBackgroundTagging(for initialArticles: [Article]) {
        Task { [weak self] in
            guard let self else { return }

            var updated = initialArticles

            for index in updated.indices {
                let article = updated[index]
                let tags = await NewsTaggerService.shared.tags(for: article)

                var newArticle = article
                newArticle.aiTags = tags
                updated[index] = newArticle

                if index < self.articles.count,
                   self.articles[index].id == newArticle.id {
                    self.articles[index] = newArticle
                } else if let current = self.articles.firstIndex(where: { $0.id == newArticle.id }) {
                    self.articles[current] = newArticle
                }
            }

            // After all tags are in, re‑score using aiTags + preferred sources.
            let currentSettings = self.settings
            let currentTagWeights = self.tagWeights
            let preferred = Set(currentSettings.preferredSources.map { $0.lowercased() })

            let rescored = updated
                .map { article -> (Article, Double) in
                    // Prefer explicit category; fall back to first aiTag
                    let baseTag: String? = {
                        if let c = article.category, !c.isEmpty { return c }
                        return article.aiTags.first
                    }()

                    var score = 0.0
                    if let tag = baseTag?.lowercased() {
                        score += currentTagWeights[tag, default: 0]
                    }
                    if let host = article.url?.host?.lowercased(),
                       preferred.contains(host) {
                        score += 2.0
                    }
                    return (article, score)
                }
                .sorted { lhs, rhs in
                    let (a, aScore) = lhs
                    let (b, bScore) = rhs
                    let aDate = a.publishedAt ?? .distantPast
                    let bDate = b.publishedAt ?? .distantPast

                    if aDate != bDate { return aDate > bDate }
                    return aScore > bScore
                }
                .map { $0.0 }

            self.articles = rescored
        }
    }

    // Persistent saved articles independent of current feed
    @Published private(set) var savedArticles: [SavedArticle] = {
        let loaded = SavedArticlesStorage.load()
        return loaded.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }()

    private let client = NewsAPIClient()
    private let rssClient = RSSBackendClient()
    private var lastFetchDate: Date? = nil

    /// Fixed favorite teams/players for Google News dynamic keywords.
    let fixedFavoriteKeywords: [String] = [
        "NBA",
        "Dallas Mavericks",
        "Texas A&M Aggies",
        "Maccabi Tel Aviv",
        "מכבי תל אביב",
        "Dallas Cowboys",
        "Manchester United",
        "FC Barcelona",
        "FC Dallas",
        "Deni Avdija",
        "Israel national team",
        "נבחרת ישראל"
    ]

    // MARK: - Saved Articles Storage

    private func sortSavedArticles() {
        savedArticles.sort { a, b in
            switch (a.publishedAt, b.publishedAt) {
            case let (da?, db?):
                return da > db  // newer first
            case (nil, nil):
                return a.title < b.title
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    // MARK: - Lifecycle

    func loadInitial() async {
        if articles.isEmpty {
            // 1) Show last cached list immediately (no spinner).
            let cached = ArticlesCacheStorage.load()
            if !cached.isEmpty {
                self.articles = cached
            }

            // 2) Then refresh in the background.
            await refreshIfAllowed(ignoreCooldown: true)
        }
    }

    func refreshIfAllowed(ignoreCooldown: Bool = false) async {
        if let last = lastFetchDate, !ignoreCooldown {
            let diff = Date().timeIntervalSince(last)
            if diff < 10 * 60 {
                return
            }
        }

        await fetchArticles()
    }

    // MARK: - Fetching

    func fetchArticles() async {
        isLoading = true
        errorMessage = nil

        do {
            // Capture current settings/tagWeights once
            let currentSettings = settings
            let currentTagWeights = tagWeights

            let params = QueryBuilder.queryParams(
                settings: currentSettings,
                tagWeights: currentTagWeights
            )

            // Fetch both feeds in parallel
            async let newsdataArticles = client.fetchArticles(params: params)
            async let rssResult = rssClient.fetchArticles()

            let fetchedNewsdata = try await newsdataArticles
            let (fetchedRSS, snapshotDate) = try await rssResult

            // 1) Combine + de‑duplicate
            var combined = fetchedRSS + fetchedNewsdata
            var seen = Set<URL>()
            combined = combined.filter { article in
                guard let url = article.url else { return true }
                if seen.contains(url) {
                    return false
                } else {
                    seen.insert(url)
                    return true
                }
            }

            // 2) Initial score & sort WITHOUT aiTags (category + preferred sources only)
            let preferred = Set(currentSettings.preferredSources.map { $0.lowercased() })

            let scored = combined
                .map { article -> (Article, Double) in
                    let tag = article.category?.lowercased() ?? ""
                    var score = currentTagWeights[tag, default: 0]
                    if let host = article.url?.host?.lowercased(),
                       preferred.contains(host) {
                        score += 2.0
                    }
                    return (article, score)
                }
                .sorted { lhs, rhs in
                    let (a, aScore) = lhs
                    let (b, bScore) = rhs
                    let aDate = a.publishedAt ?? .distantPast
                    let bDate = b.publishedAt ?? .distantPast
                    if aDate != bDate { return aDate > bDate }
                    return aScore > bScore
                }
                .map { $0.0 }

            // 3) Show list immediately
            self.articles = scored
            self.lastFetchDate = Date()
            self.lastSnapshotAt = snapshotDate
            ArticlesCacheStorage.save(scored)

            // 4) Enrich with aiTags + final re‑score in the background
            startBackgroundTagging(for: scored)

        } catch {
            self.errorMessage = "Failed to load news: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    
    // MARK: - Saved helpers

    func updateSavedReaderImageURL(url: URL?, readerImageURL: URL?) {
        guard let urlString = url?.absoluteString else { return }

        if let index = savedArticles.firstIndex(where: { $0.url?.absoluteString == urlString }) {
            var updated = savedArticles[index]
            updated.readerImageURL = readerImageURL
            savedArticles[index] = updated
            SavedArticlesStorage.save(savedArticles)
        }
    }


    // MARK: - Saved

    func toggleSaved(_ article: Article) {
        // Update live feed flag
        if let index = articles.firstIndex(of: article) {
            articles[index].isSaved.toggle()
        }

        guard let url = article.url else { return }
        let urlString = url.absoluteString

        // Check if already saved by URL
        if let existingIndex = savedArticles.firstIndex(where: { $0.url?.absoluteString == urlString }) {
            // Remove from saved
            savedArticles.remove(at: existingIndex)
        } else {
            // Add to saved (copy over readerImageURL too)
            let saved = SavedArticle(
                id: article.id,
                title: article.title,
                description: article.description,
                imageURL: article.imageURL,
                source: article.source,
                publishedAt: article.publishedAt,
                url: article.url,
                readerImageURL: article.readerImageURL
            )
            savedArticles.append(saved)
            sortSavedArticles()
        }

        SavedArticlesStorage.save(savedArticles)
    }

    // MARK: - Like / Dislike

    func like(_ article: Article) {
        if let index = articles.firstIndex(of: article) {
            articles[index].liked = true
        }

        updateTagWeights(for: article, delta: 1.0)
    }

    func dislike(_ article: Article) {
        if let index = articles.firstIndex(of: article) {
            articles[index].liked = false
        }

        updateTagWeights(for: article, delta: -1.0)
    }

    private func updateTagWeights(for article: Article, delta: Double) {
        if let category = article.category, !category.isEmpty {
            tagWeights[category.lowercased(), default: 0] += delta
            TagWeightsStorage.save(tagWeights)
            return
        }

        if let firstAiTag = article.aiTags.first {
            tagWeights[firstAiTag.lowercased(), default: 0] += delta
            TagWeightsStorage.save(tagWeights)
        }
    }

    // MARK: - Editing tags from Settings

    func removeTag(_ tag: String) {
        tagWeights.removeValue(forKey: tag)
        TagWeightsStorage.save(tagWeights)
    }

    func setWeight(_ weight: Double, for tag: String) {
        tagWeights[tag] = weight
        TagWeightsStorage.save(tagWeights)
    }

    func addTag(_ tag: String) {
        guard !tag.isEmpty else { return }
        if tagWeights[tag] == nil {
            tagWeights[tag] = 1.0
            TagWeightsStorage.save(tagWeights)
        }
    }

    // MARK: - Google News favorites keyword sync

    func combinedGoogleNewsKeywords(from settings: AppSettings) -> [String] {
        let userKeywords = settings.googleNewsUserKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var all: [String] = []
        if settings.enableFixedGoogleNewsFavorites {
            all.append(contentsOf: fixedFavoriteKeywords)
        }
        all.append(contentsOf: userKeywords)

        return all.uniqued().sorted()
    }

    // MARK: - Cache clearing

    func clearCaches() {
        // WKWebView website data (reader + Safari)
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            print("Cleared WKWebView website data")
        }

        // URLSession / URLCache
        URLCache.shared.removeAllCachedResponses()
        print("Cleared URLCache")
    }
}

// MARK: - Small helpers

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
