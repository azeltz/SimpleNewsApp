//
//  Article.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation

struct Article: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let content: String?
    let imageURL: URL?
    let source: String?
    let category: String?
    let publishedAt: Date?
    let url: URL?
    var isSaved: Bool
    var liked: Bool?
    var aiTags: [String]
}

extension Article {
    /// Coarse category + up to 4 AI tags, used for UI chips.
    var tags: [String] {
        var result: [String] = []

        if let category = category?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !category.isEmpty {
            result.append(category.capitalized)
        }

        let extra = aiTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)

        result.append(contentsOf: extra)

        return result
    }
}
