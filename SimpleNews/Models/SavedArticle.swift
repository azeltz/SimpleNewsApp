//
//  SavedArticle.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/13/26.
//

import Foundation

struct SavedArticle: Identifiable, Codable, Equatable {
    let id: String           // stable ID for saved entry
    let title: String
    let description: String?
    let imageURL: URL?
    let source: String?
    let publishedAt: Date?
    let url: URL?            // used to match with live feed

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String?,
        imageURL: URL?,
        source: String?,
        publishedAt: Date?,
        url: URL?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.source = source
        self.publishedAt = publishedAt
        self.url = url
    }

    init(from article: Article) {
        self.init(
            title: article.title,
            description: article.description,
            imageURL: article.imageURL,
            source: article.source,
            publishedAt: article.publishedAt,
            url: article.url
        )
    }
}
