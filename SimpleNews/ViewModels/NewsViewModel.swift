//
//  NewsViewModel.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var tagWeights: [String: Double] = TagWeightsStorage.load()
    @Published var settings: AppSettings = AppSettings.load()

    // Persistent saved articles (independent of current feed)
    @Published private(set) var savedArticles: [SavedArticle] = {
        let loaded = SavedArticlesStorage.load()
        return loaded.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }()

    private let client = NewsAPIClient()
    private let rssClient = RSSBackendClient()
    private var lastFetchDate: Date? = nil

    // MARK: - Saved Articles Storage

    private func sortSavedArticles() {
        savedArticles.sort { a, b in
            switch (a.publishedAt, b.publishedAt) {
            case let (da?, db?):
                return da > db // newer first
            case (nil, nil):
                return a.title < b.title // fallback stable order
            case (nil, _?):
                return false // items with date go first
            case (_?, nil):
                return true
            }
        }
    }

    // MARK: - Lifecycle

    func loadInitial() async {
        if articles.isEmpty {
            await refreshIfAllowed(ignoreCooldown: true)
        }
    }

    func refreshIfAllowed(ignoreCooldown: Bool = false) async {
        if let last = lastFetchDate, !ignoreCooldown {
            let diff = Date().timeIntervalSince(last)
            if diff < 10 * 60 { // 10 minutes
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
            let params = QueryBuilder.queryParams(settings: settings, tagWeights: tagWeights)

            async let newsdataArticles = client.fetchArticles(params: params)
            async let rssArticles = rssClient.fetchArticles()

            let fetchedNewsdata = try await newsdataArticles
            let fetchedRSS = try await rssArticles

            // 1. Combine
            var combined = fetchedRSS + fetchedNewsdata // order doesn't matter

            // 2. De-duplicate by URL
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

            // 2b. Run Core ML tagger for each article to populate article.tags
            var taggedCombined: [Article] = []
            for article in combined {
                var mutable = article
                let modelTags = await NewsTaggerService.shared.tags(for: article)
                print("ML tags for article:", mutable.title, "->", modelTags)
                mutable.aiTags = modelTags
                taggedCombined.append(mutable)
            }

            // 3. Score and sort combined array
            let preferred = Set(settings.preferredSources.map { $0.lowercased() })
            let scored = taggedCombined
                .map { article -> (Article, Double) in
                    let tag = article.category?.lowercased() ?? ""
                    var score = tagWeights[tag, default: 0]
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
                    if aDate != bDate {
                        return aDate > bDate // newer first
                    }
                    return aScore > bScore
                }
                .map { $0.0 }

            self.articles = scored
            self.lastFetchDate = Date()
        } catch {
            self.errorMessage = "Failed to load news: \(error.localizedDescription)"
        }

        isLoading = false
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
            // Add to saved
            let saved = SavedArticle(from: article)
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
        // Prefer explicit category if present
        if let category = article.category, !category.isEmpty {
            tagWeights[category.lowercased(), default: 0] += delta
            TagWeightsStorage.save(tagWeights)
            return
        }

        // Fall back to first AI tag if available
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
}
