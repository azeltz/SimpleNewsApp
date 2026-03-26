//
// Settings.swift
// SimpleNews
//
// Created by Amir Zeltzer on 2/13/26.
//

import Foundation

struct AppSettings: Codable, Equatable {
    // Where to get data from
    var enableRSS: Bool = true

    // Display
    var showImages: Bool = true
    var showDescriptions: Bool = true

    // Show topic tags under articles
    var enableTags: Bool = true

    // Sort articles based on user interests (tag weights)
    var sortByInterests: Bool = true

    // Inline reader view toggle
    var enableInLineView: Bool = true

    // Preferred sources (domains, e.g. nytimes.com)
    var preferredSources: [String] = []

    // Ask before removing from Saved
    var confirmUnsaveInSavedTab: Bool = true

    // Social tab + per‑app visibility
    var showSocialTab: Bool = true
    var showInstagram: Bool = true
    var showX: Bool = true
    var showReddit: Bool = true
    var showTikTok: Bool = true
    var showLinkedIn: Bool = true

    // Rich link previews (oEmbed)
    var enableRichLinkPreviews: Bool = true

    // Reading & Export
    var includeImageInExport: Bool = true
    var hideArticleBodyImages: Bool = false

    // AI Summary card on home screen
    var enableAISummary: Bool = true

    // Onboarding
    var hasCompletedOnboarding: Bool = false

    // Google News favorites dynamic feed
    var enableGoogleNewsFavorites: Bool = true
    /// User-entered Google News keywords (favorites editor).
    var googleNewsUserKeywords: [String] = []
    /// Whether to include built‑in fixed favorites (teams/topics) in Google News.
    /// Defaults to false so new users start with a clean keyword list.
    var enableFixedGoogleNewsFavorites: Bool = false
    /// Last combined keyword list successfully synced to the backend (fixed favorites + user keywords).
    var lastSyncedGoogleNewsKeywords: [String] = []

    // Notifications
    var enableDailyDigest: Bool = false
    var dailyDigestHour: Int = 8
    var dailyDigestMinute: Int = 0
    var enableBreakingAlerts: Bool = false
    var breakingAlertSources: [String] = []

    // Background refresh
    var enableBackgroundRefresh: Bool = true

    // Blocked tags – articles matching any of these are hidden from Home
    var blockedTags: [String] = []

    // Read/unread tracking
    var enableReadTracking: Bool = false
}
