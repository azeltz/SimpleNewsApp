//
//  ArticleGroup.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation

struct ArticleGroup: Identifiable {
    var id: String
    var canonicalTitle: String
    var primaryArticle: Article
    var allArticles: [Article]
}

// MARK: - Grouping logic

enum ArticleGrouper {
    /// Groups articles by similar titles and domains.
    static func group(_ articles: [Article]) -> [ArticleGroup] {
        var groups: [String: [Article]] = [:]
        var keyOrder: [String] = []

        for article in articles {
            let key = normalizedKey(for: article)
            if groups[key] == nil {
                keyOrder.append(key)
            }
            groups[key, default: []].append(article)
        }

        return keyOrder.compactMap { key -> ArticleGroup? in
            guard var cluster = groups[key], !cluster.isEmpty else { return nil }

            // Sort by most recent first
            cluster.sort { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            let primary = cluster[0]

            return ArticleGroup(
                id: key,
                canonicalTitle: primary.title,
                primaryArticle: primary,
                allArticles: cluster
            )
        }
    }

    // MARK: - Normalization

    private static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "in", "on", "at",
        "to", "for", "of", "and", "or", "but", "with", "by", "from",
        "that", "this", "it", "its", "has", "have", "had", "be", "been",
        "will", "would", "could", "should", "may", "might", "can",
        "not", "no", "do", "does", "did", "as", "so", "if", "up"
    ]

    private static func normalizedKey(for article: Article) -> String {
        let titleNorm = normalize(article.title)
        let domain = article.url?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        // Use a hash of the normalized title combined with nothing from domain
        // so articles from different sources with the same title cluster together
        let combined = titleNorm
        // Simple hash-like key: use the normalized text itself (truncated for efficiency)
        let truncated = String(combined.prefix(120))
        return truncated.isEmpty ? UUID().uuidString : truncated
    }

    private static func normalize(_ text: String) -> String {
        let lower = text.lowercased()
        // Remove punctuation
        let cleaned = lower.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        let str = String(String.UnicodeScalarView(cleaned))
        // Remove stop words
        let words = str.split(separator: " ").filter { !stopWords.contains(String($0)) }
        return words.joined(separator: " ")
    }
}
