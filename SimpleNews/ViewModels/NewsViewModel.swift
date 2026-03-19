//
//  NewsViewModel.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation
import WebKit

// MARK: - Article Scoring Functions

/// Logarithmic recency score. Returns a value in (0, 1] where 1 = just published.
/// `tauHours` controls how quickly recency decays (lower = faster decay).
private func recencyScore(hoursSincePublished: Double, tauHours: Double = 3.0) -> Double {
    let t = max(0, hoursSincePublished)
    return 1.0 / (1.0 + log(1.0 + t / tauHours))
}

/// Raw interest score: sum of tag weights for all tags on the article, clamped to [-10, 10].
private func interestScoreRaw(articleTags: [String], tagWeights: [String: Double]) -> Double {
    var sum = 0.0
    for tag in articleTags {
        let key = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { continue }
        sum += tagWeights[key, default: 0]
    }
    return max(-10, min(10, sum))
}

/// Normalize interest score from -10..10 to -1..1.
private func normalizedInterestScore(_ raw: Double) -> Double {
    max(-10, min(10, raw)) / 10.0
}

/// Combined article score blending recency and interest with small jitter.
/// Higher values rank higher in the feed.
private func articleScore(
    hoursSincePublished: Double,
    interestRaw: Double,
    preferredSourceBonus: Double = 0,
    wRecency: Double = 0.8,
    wInterest: Double = 0.5
) -> Double {
    let r = recencyScore(hoursSincePublished: hoursSincePublished)
    let k = normalizedInterestScore(interestRaw)
    return wRecency * r + wInterest * k + preferredSourceBonus
}

/// Collect all scorable tag keys for an article (category + aiTags), lowercased.
private func allTagKeys(for article: Article) -> [String] {
    var keys: [String] = []
    if let c = article.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !c.isEmpty {
        keys.append(c)
    }
    for tag in article.aiTags {
        let key = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !key.isEmpty { keys.append(key) }
    }
    return keys
}

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

    /// Articles hidden from Home because they match a blocked tag.
    var blockedArticles: [Article] {
        let blocked = Set(settings.blockedTags.map { $0.lowercased() })
        guard !blocked.isEmpty else { return [] }
        return articles.filter { article in
            let keys = allTagKeys(for: article)
            return keys.contains { blocked.contains($0) }
        }
    }

    /// For each blocked article, return which blocked tags matched.
    func matchingBlockedTags(for article: Article) -> [String] {
        let blocked = Set(settings.blockedTags.map { $0.lowercased() })
        return allTagKeys(for: article).filter { blocked.contains($0) }
    }

    /// Articles visible in Home (excludes blocked-tag articles).
    private var nonBlockedArticles: [Article] {
        let blocked = Set(settings.blockedTags.map { $0.lowercased() })
        guard !blocked.isEmpty else { return articles }
        return articles.filter { article in
            let keys = allTagKeys(for: article)
            return !keys.contains { blocked.contains($0) }
        }
    }

    var filteredArticles: [Article] {
        let base = nonBlockedArticles
        guard !searchText.isEmpty else { return base }
        let query = searchText.lowercased()

        return base.filter { article in
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

    /// Grouped version of filteredArticles for the main list.
    var groupedArticles: [ArticleGroup] {
        ArticleGrouper.group(filteredArticles)
    }

    private func startBackgroundImageFetch(for articles: [Article]) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let enriched = await OGImageExtractor.enrichArticles(articles)
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Merge fetched images into current articles (preserving any
                // changes that happened since the fetch started, e.g. tags).
                for enrichedArticle in enriched {
                    guard enrichedArticle.imageURL != nil else { continue }
                    if let idx = self.articles.firstIndex(where: { $0.id == enrichedArticle.id }),
                       self.articles[idx].imageURL == nil {
                        self.articles[idx].imageURL = enrichedArticle.imageURL
                    }
                }
                ArticlesCacheStorage.save(self.articles)
            }
        }
    }

    private func startBackgroundTagging(for initialArticles: [Article]) {
        // Capture values needed for the background work
        let currentSettings = self.settings
        let currentTagWeights = self.tagWeights

        Task.detached(priority: .utility) { [weak self] in
            var updated = initialArticles
            let allKeywordCategories = KeywordTagger.shared.allCategoryRules().map { $0.category }

            for index in updated.indices {
                let article = updated[index]
                var newArticle = article

                var mlCategories: [String] = []
                var collectedTags: [String] = []

                // 1) ML coarse categories
                if let (_, probs) = CategoryClassifierService.shared.predictCategory(for: article) {
                    let sorted = probs
                        .sorted { $0.value > $1.value }
                        .prefix(3)
                    mlCategories = sorted.map { $0.key }

                    if let first = mlCategories.first {
                        newArticle = Article(
                            id: newArticle.id,
                            title: newArticle.title,
                            description: newArticle.description,
                            content: newArticle.content,
                            imageURL: newArticle.imageURL,
                            source: newArticle.source,
                            category: first,
                            publishedAt: newArticle.publishedAt,
                            url: newArticle.url,
                            isSaved: newArticle.isSaved,
                            liked: newArticle.liked,
                            aiTags: newArticle.aiTags,
                            readerImageURL: newArticle.readerImageURL
                        )
                    }
                }

                // 2) Keyword-based tags
                let textForTags = [
                    article.title,
                    article.description ?? "",
                    article.content ?? ""
                ].joined(separator: " ")

                let baseCategory = newArticle.category ?? ""
                var categoriesForKeywords = mlCategories
                if !baseCategory.isEmpty && !categoriesForKeywords.contains(baseCategory) {
                    categoriesForKeywords.insert(baseCategory, at: 0)
                }
                if categoriesForKeywords.isEmpty {
                    categoriesForKeywords = allKeywordCategories
                }

                let keywordResult = KeywordTagger.shared.tagsWithCategory(
                    forCategories: categoriesForKeywords,
                    text: textForTags,
                    maxTags: 5
                )
                collectedTags.append(contentsOf: keywordResult.tags)

                if newArticle.category == nil || newArticle.category?.isEmpty == true,
                   let kwCategory = keywordResult.category {
                    newArticle = Article(
                        id: newArticle.id,
                        title: newArticle.title,
                        description: newArticle.description,
                        content: newArticle.content,
                        imageURL: newArticle.imageURL,
                        source: newArticle.source,
                        category: kwCategory,
                        publishedAt: newArticle.publishedAt,
                        url: newArticle.url,
                        isSaved: newArticle.isSaved,
                        liked: newArticle.liked,
                        aiTags: newArticle.aiTags,
                        readerImageURL: newArticle.readerImageURL
                    )
                }

                // 3) Assign aiTags
                let dedup = Array(
                    Set(collectedTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                )
                newArticle.aiTags = dedup
                updated[index] = newArticle

                // Incremental UI update on the main actor.
                // Preserve imageURL/readerImageURL from the live array because
                // the background image fetch may have enriched them after tagging started.
                let snapshot = newArticle
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let current = self.articles.firstIndex(where: { $0.id == snapshot.id }) {
                        var merged = snapshot
                        if merged.imageURL == nil {
                            merged.imageURL = self.articles[current].imageURL
                        }
                        if merged.readerImageURL == nil {
                            merged.readerImageURL = self.articles[current].readerImageURL
                        }
                        self.articles[current] = merged
                    }
                }
            }

            // Final re-score with full tags
            let preferred = Set(currentSettings.preferredSources.map { $0.lowercased() })
            let useInterestSort = currentSettings.sortByInterests
            let now = Date()

            let rescored = updated
                .map { article -> (Article, Double) in
                    let hours = max(0, now.timeIntervalSince(article.publishedAt ?? now) / 3600.0)

                    let interestRaw: Double
                    if useInterestSort {
                        interestRaw = interestScoreRaw(
                            articleTags: allTagKeys(for: article),
                            tagWeights: currentTagWeights
                        )
                    } else {
                        interestRaw = 0
                    }

                    let prefBonus: Double = {
                        if let host = article.url?.host?.lowercased(), preferred.contains(host) {
                            return 0.15
                        }
                        return 0
                    }()

                    let score = articleScore(
                        hoursSincePublished: hours,
                        interestRaw: interestRaw,
                        preferredSourceBonus: prefBonus
                    )
                    return (article, score)
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }

            await MainActor.run { [weak self] in
                guard let self else { return }
                // Merge image URLs from the live array since the OG image fetch
                // may have enriched articles while tagging was running.
                var final = rescored
                for i in final.indices {
                    if final[i].imageURL == nil,
                       let live = self.articles.first(where: { $0.id == final[i].id }) {
                        final[i].imageURL = live.imageURL
                        if final[i].readerImageURL == nil {
                            final[i].readerImageURL = live.readerImageURL
                        }
                    }
                }
                self.articles = final
                ArticlesCacheStorage.save(final)
            }
        }
    }

    // Persistent saved articles independent of current feed
    @Published private(set) var savedArticles: [SavedArticle] = {
        let loaded = SavedArticlesStorage.load()
        return loaded.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }()

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

    /// Reload saved articles from persistent storage (e.g. after a Watch sync).
    /// Also syncs the `isSaved` flag on feed articles so the HomeView reflects
    /// articles saved from the Watch.
    func reloadSavedArticles() {
        savedArticles = SavedArticlesStorage.load()
        sortSavedArticles()
        syncSavedFlagsToFeed()
    }

    /// Update `isSaved` on each feed article to match SavedArticlesStorage.
    /// Matches by URL so articles saved from the Watch (which may have different IDs)
    /// are correctly reflected in the HomeView.
    private func syncSavedFlagsToFeed() {
        let savedURLs = Set(savedArticles.compactMap { $0.url?.absoluteString })
        for i in articles.indices {
            if let url = articles[i].url?.absoluteString {
                articles[i].isSaved = savedURLs.contains(url)
            }
        }
    }

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
                syncSavedFlagsToFeed()

                // Kick off OG image fetch for cached articles that still lack images
                let missingImages = cached.filter { $0.imageURL == nil && $0.readerImageURL == nil }
                if !missingImages.isEmpty {
                    startBackgroundImageFetch(for: missingImages)
                }
            }

            // 2) Then refresh in the background.
            await refreshIfAllowed(ignoreCooldown: true)
        }
    }

    /// Status message shown briefly in the toolbar after a refresh attempt.
    @Published var refreshStatusMessage: String?

    func refreshIfAllowed(ignoreCooldown: Bool = false) async {
        if let last = lastFetchDate, !ignoreCooldown {
            let diff = Date().timeIntervalSince(last)
            if diff < 10 * 60 {
                let remaining = Int(ceil((10 * 60 - diff) / 60))
                refreshStatusMessage = "Up to date · refreshes in \(remaining)m"
                // Auto-clear after 3 seconds
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    if self.refreshStatusMessage?.hasPrefix("Up to date") == true {
                        self.refreshStatusMessage = nil
                    }
                }
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

            // Fetch articles from the RSS backend
            let (fetchedRSS, snapshotDate) = try await rssClient.fetchArticles()

            // De-duplicate by URL
            var combined = fetchedRSS
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

            // 2) Score & sort: logarithmic recency + interest weights
            let preferred = Set(currentSettings.preferredSources.map { $0.lowercased() })
            let useInterestSort = currentSettings.sortByInterests
            let now = Date()

            let scored = combined
                .map { article -> (Article, Double) in
                    let hours = max(0, now.timeIntervalSince(article.publishedAt ?? now) / 3600.0)

                    let interestRaw: Double
                    if useInterestSort {
                        interestRaw = interestScoreRaw(
                            articleTags: allTagKeys(for: article),
                            tagWeights: currentTagWeights
                        )
                    } else {
                        interestRaw = 0
                    }

                    let prefBonus: Double = {
                        if let host = article.url?.host?.lowercased(), preferred.contains(host) {
                            return 0.15
                        }
                        return 0
                    }()

                    let score = articleScore(
                        hoursSincePublished: hours,
                        interestRaw: interestRaw,
                        preferredSourceBonus: prefBonus
                    )
                    return (article, score)
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }

            // 3) Show list immediately
            self.articles = scored
            syncSavedFlagsToFeed()
            self.lastFetchDate = Date()
            self.lastSnapshotAt = snapshotDate
            ArticlesCacheStorage.save(scored)

            // 4) Enrich articles with OG images in the background
            startBackgroundImageFetch(for: scored)

            // 5) Enrich with aiTags + final re‑score in the background
            startBackgroundTagging(for: scored)

            isLoading = false
        } catch {
            self.errorMessage = "Failed to load news: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Image propagation

    /// Called when the reader view discovers an image for an article that had none.
    /// Updates both the live feed array and the cache so article rows reflect the image.
    func updateReaderImage(articleID: String, readerImageURL: URL) {
        if let idx = articles.firstIndex(where: { $0.id == articleID }) {
            if articles[idx].imageURL == nil {
                articles[idx].readerImageURL = readerImageURL
                ArticlesCacheStorage.save(articles)
            }
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

        updateTagWeights(for: article, delta: 2.0)
    }

    func dislike(_ article: Article) {
        if let index = articles.firstIndex(of: article) {
            articles[index].liked = false
        }

        updateTagWeights(for: article, delta: -2.0)
    }

    private func updateTagWeights(for article: Article, delta: Double) {
        // Adjust weight for ALL tags (category + AI tags), clamped to [-10, +10]
        for key in allTagKeys(for: article) {
            let current = tagWeights[key, default: 0]
            tagWeights[key] = max(-10, min(10, current + delta))
        }

        TagWeightsStorage.save(tagWeights)
    }

    // MARK: - Editing tags from Settings

    func removeTag(_ tag: String) {
        tagWeights.removeValue(forKey: tag)
        TagWeightsStorage.save(tagWeights)
    }

    func setWeight(_ weight: Double, for tag: String) {
        tagWeights[tag] = max(-10, min(10, weight))
        TagWeightsStorage.save(tagWeights)
    }

    func addTag(_ tag: String) {
        guard !tag.isEmpty else { return }
        let key = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        if tagWeights[key] == nil {
            tagWeights[key] = 5.0
            TagWeightsStorage.save(tagWeights)
        }
    }

    // MARK: - Blocked Tags

    func addBlockedTag(_ tag: String) {
        let key = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        if !settings.blockedTags.contains(key) {
            settings.blockedTags.append(key)
            settings.save()
        }
    }

    func removeBlockedTag(_ tag: String) {
        let key = tag.lowercased()
        settings.blockedTags.removeAll { $0.lowercased() == key }
        settings.save()
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
            Log.data.debug("Cleared WKWebView website data")
        }

        // URLSession / URLCache
        URLCache.shared.removeAllCachedResponses()
        Log.data.debug("Cleared URLCache")

        // Clear article cache file
        ArticlesCacheStorage.clear()
        Log.data.debug("Cleared articles cache")
    }
}

// MARK: - Small helpers

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
