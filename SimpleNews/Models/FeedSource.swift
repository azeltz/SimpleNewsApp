//
//  FeedSource.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation

struct FeedSource: Identifiable, Codable, Equatable {
    var id: String
    var url: URL
    var source: String       // domain, e.g. "espn.com"
    var kind: String         // e.g. "top", "important"
    var isDefault: Bool
    var isEnabled: Bool
    var displayName: String?
    var category: String?
}

// MARK: - Source grouping for UI display

extension FeedSource {
    /// Logical section for grouping in onboarding / settings UI.
    enum SourceGroup: String, CaseIterable {
        case general = "General News"
        case sports = "Sports"
        case business = "Business & Finance"
        case tech = "Tech"
        case israel = "Israel"
        case local = "Local & Regional"
    }

    var sourceGroup: SourceGroup {
        switch id {
        // General
        case "nyt_home", "ap_top", "wsj_world", "wsj_politics", "morning_brew":
            return .general
        // Sports
        case "espn_top", "espn_nba", "espn_nfl", "espn_cfb", "espn_cbk",
             "espn_soccer", "espn_tennis", "cbs_top", "nyt_pro_basketball",
             "yahoo_sports", "front_office_sports", "eurohoops",
             "wsj_sports", "opta_analyst", "tamu_news", "sec_news":
            return .sports
        // Business
        case "wsj_us_business", "wsj_markets", "wsj_economy":
            return .business
        // Tech
        case "techcrunch_main", "wsj_tech":
            return .tech
        // Israel
        case "one_main", "ynet_english_news", "ynet_top", "ynet_consistent":
            return .israel
        // Local
        case "local_tx_cities":
            return .local
        default:
            return .general
        }
    }
}

// MARK: - Default feeds (single source of truth)

extension FeedSource {
    /// The canonical default feed list. `UserSourcesStore` uses this as its starting point.
    /// Note: Force unwraps on URL(string:) below are safe — all strings are compile-time
    /// constants verified to be valid URLs.
    // swiftlint:disable force_unwrapping
    static let defaultSources: [FeedSource] = [
        // ESPN
        FeedSource(id: "espn_top",       url: URL(string: "https://www.espn.com/espn/rss/news")!,               source: "espn.com",              kind: "top",        isDefault: true, isEnabled: true,  displayName: "ESPN – Top Headlines"),
        FeedSource(id: "espn_nba",       url: URL(string: "https://www.espn.com/espn/rss/nba/news")!,           source: "espn.com",              kind: "top",        isDefault: true, isEnabled: true,  displayName: "ESPN – NBA"),
        FeedSource(id: "espn_nfl",       url: URL(string: "https://www.espn.com/espn/rss/nfl/news")!,           source: "espn.com",              kind: "top",        isDefault: true, isEnabled: true,  displayName: "ESPN – NFL"),
        FeedSource(id: "espn_cfb",       url: URL(string: "https://www.espn.com/espn/rss/ncf/news")!,           source: "espn.com",              kind: "important",  isDefault: true, isEnabled: true,  displayName: "ESPN – College Football"),
        FeedSource(id: "espn_cbk",       url: URL(string: "https://www.espn.com/espn/rss/ncb/news")!,           source: "espn.com",              kind: "consistent", isDefault: true, isEnabled: true,  displayName: "ESPN – College Basketball"),
        FeedSource(id: "espn_soccer",    url: URL(string: "https://www.espn.com/espn/rss/soccer/news")!,        source: "espn.com",              kind: "consistent", isDefault: true, isEnabled: false, displayName: "ESPN – Soccer"),
        FeedSource(id: "espn_tennis",    url: URL(string: "https://www.espn.com/espn/rss/tennis/news")!,        source: "espn.com",              kind: "periodic",   isDefault: true, isEnabled: false, displayName: "ESPN – Tennis"),
        // CBS Sports
        FeedSource(id: "cbs_top",        url: URL(string: "https://www.cbssports.com/rss/headlines/")!,         source: "cbssports.com",         kind: "top",        isDefault: true, isEnabled: true,  displayName: "CBS Sports"),
        // NYT
        FeedSource(id: "nyt_home",       url: URL(string: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml")!, source: "nytimes.com",   kind: "top",        isDefault: true, isEnabled: true,  displayName: "NYT – Home"),
        FeedSource(id: "nyt_pro_basketball", url: URL(string: "https://rss.nytimes.com/services/xml/rss/nyt/ProBasketball.xml")!, source: "nytimes.com", kind: "important", isDefault: true, isEnabled: true, displayName: "NYT – Pro Basketball"),
        // WSJ
        FeedSource(id: "wsj_world",      url: URL(string: "https://feeds.content.dowjones.io/public/rss/RSSWorldNews")!, source: "wsj.com",       kind: "top",        isDefault: true, isEnabled: true,  displayName: "WSJ – World"),
        FeedSource(id: "wsj_us_business", url: URL(string: "https://feeds.content.dowjones.io/public/rss/WSJcomUSBusiness")!, source: "wsj.com",   kind: "important",  isDefault: true, isEnabled: true,  displayName: "WSJ – US Business"),
        FeedSource(id: "wsj_markets",    url: URL(string: "https://feeds.content.dowjones.io/public/rss/RSSMarketsMain")!, source: "wsj.com",      kind: "consistent", isDefault: true, isEnabled: true,  displayName: "WSJ – Markets"),
        FeedSource(id: "wsj_tech",       url: URL(string: "https://feeds.content.dowjones.io/public/rss/RSSWSJD")!,       source: "wsj.com",      kind: "consistent", isDefault: true, isEnabled: true,  displayName: "WSJ – Tech"),
        FeedSource(id: "wsj_politics",   url: URL(string: "https://feeds.content.dowjones.io/public/rss/socialpoliticsfeed")!, source: "wsj.com",   kind: "consistent", isDefault: true, isEnabled: false, displayName: "WSJ – Politics"),
        FeedSource(id: "wsj_economy",    url: URL(string: "https://feeds.content.dowjones.io/public/rss/socialeconomyfeed")!, source: "wsj.com",    kind: "consistent", isDefault: true, isEnabled: false, displayName: "WSJ – Economy"),
        FeedSource(id: "wsj_sports",     url: URL(string: "https://feeds.content.dowjones.io/public/rss/rsssportsfeed")!, source: "wsj.com",       kind: "important",  isDefault: true, isEnabled: true,  displayName: "WSJ – Sports"),
        // Morning Brew
        FeedSource(id: "morning_brew",   url: URL(string: "https://www.morningbrew.com/feed.xml")!,             source: "morningbrew.com",       kind: "morning_daily", isDefault: true, isEnabled: true, displayName: "Morning Brew"),
        // Israel - One
        FeedSource(id: "one_main",       url: URL(string: "https://www.one.co.il/rss/")!,                      source: "one.co.il",             kind: "top",        isDefault: true, isEnabled: true,  displayName: "ONE"),
        // Yahoo Sports
        FeedSource(id: "yahoo_sports",   url: URL(string: "https://sports.yahoo.com/general/news/rss/")!,      source: "sports.yahoo.com",      kind: "top",        isDefault: true, isEnabled: true,  displayName: "Yahoo Sports"),
        // Front Office Sports
        FeedSource(id: "front_office_sports", url: URL(string: "https://frontofficesports.com/feed/")!,         source: "frontofficesports.com", kind: "periodic",   isDefault: true, isEnabled: false, displayName: "Front Office Sports"),
        // Eurohoops
        FeedSource(id: "eurohoops",      url: URL(string: "https://www.eurohoops.net/en/feed/")!,              source: "eurohoops.net",         kind: "consistent", isDefault: true, isEnabled: true,  displayName: "Eurohoops"),
        // Ynet
        FeedSource(id: "ynet_english_news", url: URL(string: "https://www.ynet.co.il/3rdparty/mobile/rss/ynetnews/3082/")!, source: "ynet.co.il", kind: "important", isDefault: true, isEnabled: true, displayName: "Ynet English"),
        FeedSource(id: "ynet_top",       url: URL(string: "https://www.ynet.co.il/Integration/StoryRss2.xml")!, source: "ynet.co.il",           kind: "top",        isDefault: true, isEnabled: true,  displayName: "Ynet – Top"),
        FeedSource(id: "ynet_consistent", url: URL(string: "https://www.ynet.co.il/Integration/StoryRss3.xml")!, source: "ynet.co.il",          kind: "consistent", isDefault: true, isEnabled: false, displayName: "Ynet – More"),
        // Google News regional / topical
        FeedSource(id: "local_tx_cities", url: URL(string: "https://news.google.com/rss/search?q=%22Dallas+Texas%22+OR+%22Plano+Texas%22+OR+%22College+Station+Texas%22+OR+%22Bryan+Texas%22&hl=en-US&gl=US&ceid=US:en")!, source: "news.google.com", kind: "consistent", isDefault: true, isEnabled: true, displayName: "TX Cities (Google News)"),
        // Opta Analyst
        FeedSource(id: "opta_analyst",   url: URL(string: "https://theanalyst.com/feed/")!,                    source: "theanalyst.com",        kind: "periodic",   isDefault: true, isEnabled: false, displayName: "The Analyst (Opta)"),
        // TechCrunch
        FeedSource(id: "techcrunch_main", url: URL(string: "https://techcrunch.com/feed/")!,                   source: "techcrunch.com",        kind: "consistent", isDefault: true, isEnabled: true,  displayName: "TechCrunch"),
        // Texas A&M
        FeedSource(id: "tamu_news",      url: URL(string: "https://news.google.com/rss/search?q=%22Texas+A%26M%22+OR+%22Aggies%22&hl=en-US&gl=US&ceid=US:en")!, source: "news.google.com", kind: "consistent", isDefault: true, isEnabled: true, displayName: "Texas A&M (Google News)"),
        // SEC
        FeedSource(id: "sec_news",       url: URL(string: "https://news.google.com/rss/search?q=%22SEC%22+OR+%22Southeastern+Conference%22+college+football+OR+college+basketball&hl=en-US&gl=US&ceid=US:en")!, source: "news.google.com", kind: "consistent", isDefault: true, isEnabled: false, displayName: "SEC Sports (Google News)"),
    ]
    // swiftlint:enable force_unwrapping
}
