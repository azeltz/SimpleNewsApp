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

// MARK: - Default feeds matching the backend DEFAULT_FEEDS

extension FeedSource {
    static let defaults: [FeedSource] = [
        FeedSource(id: "ap_top", url: URL(string: "https://rsshub.app/apnews/topics/apf-topnews")!, source: "apnews.com", kind: "top", isDefault: true, isEnabled: true, displayName: "AP News – Top"),
        FeedSource(id: "reuters_world", url: URL(string: "https://rsshub.app/reuters/world")!, source: "reuters.com", kind: "top", isDefault: true, isEnabled: true, displayName: "Reuters – World"),
        FeedSource(id: "bbc_world", url: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!, source: "bbc.com", kind: "top", isDefault: true, isEnabled: true, displayName: "BBC – World"),
        FeedSource(id: "nyt_home", url: URL(string: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml")!, source: "nytimes.com", kind: "top", isDefault: true, isEnabled: true, displayName: "NYT – Home"),
        FeedSource(id: "cnn_top", url: URL(string: "http://rss.cnn.com/rss/cnn_topstories.rss")!, source: "cnn.com", kind: "important", isDefault: true, isEnabled: true, displayName: "CNN – Top"),
        FeedSource(id: "espn_top", url: URL(string: "https://www.espn.com/espn/rss/news")!, source: "espn.com", kind: "consistent", isDefault: true, isEnabled: true, displayName: "ESPN – Top"),
        FeedSource(id: "techcrunch", url: URL(string: "https://techcrunch.com/feed/")!, source: "techcrunch.com", kind: "consistent", isDefault: true, isEnabled: true, displayName: "TechCrunch"),
        FeedSource(id: "ars_tech", url: URL(string: "https://feeds.arstechnica.com/arstechnica/index")!, source: "arstechnica.com", kind: "periodic", isDefault: true, isEnabled: true, displayName: "Ars Technica"),
        FeedSource(id: "haaretz_en", url: URL(string: "https://www.haaretz.com/srv/haaretz-latest-en")!, source: "haaretz.com", kind: "important", isDefault: true, isEnabled: true, displayName: "Haaretz English"),
        FeedSource(id: "ynet_breaking", url: URL(string: "https://www.ynet.co.il/Integration/StoryRss2.xml")!, source: "ynet.co.il", kind: "breaking", isDefault: true, isEnabled: true, displayName: "Ynet Breaking"),
    ]
}
