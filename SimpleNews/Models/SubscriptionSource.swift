//
//  SubscriptionSource.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/18/26.
//

import Foundation

struct SubscriptionSource: Identifiable, Codable, Equatable {
    let id: String
    let domain: String
    let displayName: String
    let loginURL: URL
    let isCustom: Bool
}

extension SubscriptionSource {
    /// Built-in paywalled sources. Add new entries here to ship more defaults.
    static let builtIn: [SubscriptionSource] = [
        SubscriptionSource(
            id: "wsj",
            domain: "wsj.com",
            displayName: "Wall Street Journal",
            loginURL: URL(string: "https://accounts.wsj.com/login")!,
            isCustom: false
        ),
        SubscriptionSource(
            id: "nytimes",
            domain: "nytimes.com",
            displayName: "New York Times",
            loginURL: URL(string: "https://myaccount.nytimes.com/auth/login")!,
            isCustom: false
        ),
    ]
}
