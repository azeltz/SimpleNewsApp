//
// Article.swift
// SimpleNews
//
// Created by Amir Zeltzer on 2/13/26.
//

import Foundation

struct Article: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let description: String?
    let content: String?
    var imageURL: URL?
    let source: String?
    let category: String?
    let publishedAt: Date?
    let url: URL?
    var isSaved: Bool
    var liked: Bool?
    var aiTags: [String]
    // Fallback image discovered by the reader
    var readerImageURL: URL?
}

// MARK: - Language + display helpers

private func articleIsHebrew(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        if scalar.value >= 0x0590 && scalar.value <= 0x05FF {
            return true
        }
    }
    return false
}

// Map internal English categories to Hebrew display names
private let hebrewCategoryDisplay: [String: String] = [
    "Politics": "פוליטיקה",
    "War & conflict": "מלחמה ועימותים",
    "Crime & law": "פשע וחוק",
    "Business": "עסקים",
    "Finance": "פיננסים",
    "Technology": "טכנולוגיה",
    "Science": "מדע",
    "Climate": "אקלים",
    "Health": "בריאות",
    "Education": "חינוך",
    "Sports": "ספורט",
    "Entertainment": "בידור",
    "Travel": "תיירות",
    "Real estate": "נדל\"ן",
    "Jobs & careers": "עבודה וקריירה",
    "Food": "אוכל",
    "Fitness": "כושר",
    "Wellness": "רווחה",
    "Relationships": "מערכות יחסים",
    "Home & DIY": "בית ו-DIY",
    "Fashion & beauty": "אופנה וטיפוח",
    "Parenting": "הורות",
    "Pets": "חיות מחמד",
    "Crypto": "קריפטו",
    "Gaming": "גיימינג",
    "US": "ארה\"ב",
    "Europe": "אירופה",
    "Asia": "אסיה",
    "Middle East": "המזרח התיכון",
    "Africa": "אפריקה",
    "Latin America": "אמריקה הלטינית",
    "World": "עולם"
]

// Optional: map internal tag IDs to Hebrew display
private let hebrewTagDisplay: [String: String] = [
    // Example – add more as you define them:
    "israel_gaza_war": "המלחמה בעזה",
]

extension Article {

    var isHebrew: Bool {
        let combined = title + " " + (description ?? "")
        return articleIsHebrew(combined)
    }

    private func displayCategory(_ raw: String) -> String {
        guard isHebrew, let he = hebrewCategoryDisplay[raw] else {
            return raw
        }
        return he
    }

    private func displayTag(_ raw: String) -> String {
        if isHebrew, let he = hebrewTagDisplay[raw] {
            return he
        }
        return raw
    }

    /// Coarse category + up to 4 AI tags, used for UI chips.
    var tags: [String] {
        var result: [String] = []

        if let category = category?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !category.isEmpty {

            // Use raw category for lookup, then convert to display text.
            result.append(displayCategory(category))
        }

        let extra = aiTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)

        result.append(contentsOf: extra.map { displayTag($0) })
        return result
    }
}
