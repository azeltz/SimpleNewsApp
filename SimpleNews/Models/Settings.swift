// Settings.swift

import Foundation

enum NewsLanguage: String, CaseIterable, Identifiable, Codable {
    case en  // English
    case he  // Hebrew
    case es  // Spanish
    case fr  // French
    case de  // German
    case it  // Italian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .he: return "Hebrew"
        case .es: return "Spanish"
        case .fr: return "French"
        case .de: return "German"
        case .it: return "Italian"
        }
    }
}

enum NewsCountry: String, CaseIterable, Identifiable, Codable {
    case us
    case il
    case gb
    case ca
    case au
    case de

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: return "United States"
        case .il: return "Israel"
        case .gb: return "United Kingdom"
        case .ca: return "Canada"
        case .au: return "Australia"
        case .de: return "Germany"
        }
    }
}

let knownCategories: Set<String> = [
    "top", "business", "entertainment", "environment", "food",
    "health", "politics", "science", "sports", "technology", "world"
]

struct AppSettings: Codable {
    // Where to get data from
    var enableNewsdata: Bool = true
    var enableRSS: Bool = true

    // Multiple languages and countries (Newsdata supports up to 5 each)
    var languages: [NewsLanguage] = [.en]
    var countries: [NewsCountry] = [.us]

    // Display
    var showImages: Bool = true
    var showDescriptions: Bool = true

    // Show topic tags under articles
    var enableTags: Bool = true

    // Inline reader view toggle
    var enableInLineView: Bool = true

    // Preferred sources (domains, e.g. nytimes.com, apnews.com)
    var preferredSources: [String] = []

    // Only top outlets (stricter sorting)
    var qualityMode: Bool = false

    // Ask before removing from Saved
    var confirmUnsaveInSavedTab: Bool = true

    // Social tab + per‑app visibility
    var showSocialTab: Bool = true
    var showInstagram: Bool = true
    var showX: Bool = true
    var showReddit: Bool = true
    var showTikTok: Bool = true
    var showLinkedIn: Bool = true
}
