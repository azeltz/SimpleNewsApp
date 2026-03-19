//
//  WatchHeadline.swift
//  SimpleNewsWatch
//
//  Lightweight headline model for the Watch app.
//

import Foundation

struct WatchHeadline: Identifiable {
    let id: String
    let title: String
    let source: String?
    let publishedAt: Date?
    let urlString: String?
    let description: String?
    var isSaved: Bool = false
}
