//
//  AppState.swift
//  SimpleNews
//
//  Observable state for notification deep linking and app-wide routing.
//

import Foundation

@MainActor
final class AppState: ObservableObject {
    /// Set to true when a daily digest notification is tapped.
    /// HomeView observes this to present the AI summary modal.
    @Published var showDailyDigest: Bool = false

    /// Set to an article ID when a breaking news notification is tapped.
    /// HomeView observes this to navigate to the article detail.
    @Published var deepLinkArticleID: String?
}
