//
//  KeywordTagger.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/23/26.
//
import Foundation

enum TagStatus: String, Codable, CaseIterable {
    case yes = "y"       // use this tag
    case no = "n"        // block this tag
    case undecided = "u" // candidate; ignore for tagging
}

struct TagRule: Codable {
    var tag: String
    var status: TagStatus
    var keywords: [String]
}

struct CategoryTagRules: Codable, Identifiable {
    var id: String { category }
    var category: String
    var tags: [TagRule]
}

struct KeywordRuleSet: Codable {
    var categories: [CategoryTagRules]
}

/// Handles keyword-based tags + JSON persistence.
final class KeywordTagger {

    static let shared = KeywordTagger()

    private(set) var rules: KeywordRuleSet

    private init() {
        // Load user-edited rules if available
        if let url = KeywordTagger.userRulesURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(KeywordRuleSet.self, from: data) {
            self.rules = KeywordTagger.deduplicateCategories(decoded)
        } else if let bundledURL = Bundle.main.url(forResource: "keyword_rules", withExtension: "json"),
                  let data = try? Data(contentsOf: bundledURL),
                  let decoded = try? JSONDecoder().decode(KeywordRuleSet.self, from: data) {
            self.rules = KeywordTagger.deduplicateCategories(decoded)
        } else {
            self.rules = KeywordRuleSet(categories: [])
        }
    }

    /// Merge duplicate category entries so ForEach IDs are unique.
    private static func deduplicateCategories(_ ruleSet: KeywordRuleSet) -> KeywordRuleSet {
        var merged: [String: CategoryTagRules] = [:]
        var order: [String] = []

        for cat in ruleSet.categories {
            if var existing = merged[cat.category] {
                // Append new tags, skipping duplicates
                for tag in cat.tags where !existing.tags.contains(where: { $0.tag == tag.tag }) {
                    existing.tags.append(tag)
                }
                merged[cat.category] = existing
            } else {
                merged[cat.category] = cat
                order.append(cat.category)
            }
        }

        return KeywordRuleSet(categories: order.compactMap { merged[$0] })
    }

    // MARK: - Tagging

    /// Given coarse categories + text, return up to maxTags matched tags.
    func tags(forCategories categories: [String], text: String, maxTags: Int = 5) -> [String] {
        return tagsWithCategory(forCategories: categories, text: text, maxTags: maxTags).tags
    }

    /// Returns both the best-matching category and the matched tags.
    /// The category is the one with the most keyword hits.
    func tagsWithCategory(forCategories categories: [String], text: String, maxTags: Int = 5) -> (category: String?, tags: [String]) {
        let lower = text.lowercased()
        var result: [String] = []
        var hitsByCategory: [String: Int] = [:]

        for category in categories {
            guard let catRules = rules.categories.first(where: { $0.category == category }) else {
                continue
            }
            for rule in catRules.tags {
                guard rule.status == .yes else { continue }
                let matched = rule.keywords.contains { kw in
                    Self.keywordMatches(kw.lowercased(), in: lower)
                }
                if matched {
                    hitsByCategory[category, default: 0] += 1
                    if !result.contains(rule.tag) {
                        result.append(rule.tag)
                        if result.count >= maxTags {
                            let bestCategory = hitsByCategory.max(by: { $0.value < $1.value })?.key
                            return (bestCategory, result)
                        }
                    }
                }
            }
        }

        let bestCategory = hitsByCategory.max(by: { $0.value < $1.value })?.key
        return (bestCategory, result)
    }

    /// Word-boundary-aware match for short keywords (<=4 chars) to avoid
    /// false positives like "eu" matching "lineup" or "ace" matching "place".
    /// Longer keywords use simple substring matching.
    private static func keywordMatches(_ keyword: String, in text: String) -> Bool {
        if keyword.count <= 4 {
            // Use regex word boundaries for short keywords
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            return text.range(of: pattern, options: .regularExpression) != nil
        } else {
            return text.contains(keyword)
        }
    }

    // MARK: - Editing API (for Settings UI)

    func allCategoryRules() -> [CategoryTagRules] {
        rules.categories.sorted { $0.category < $1.category }
    }

    func setStatus(category: String, tag: String, status: TagStatus) {
        for i in rules.categories.indices where rules.categories[i].category == category {
            for j in rules.categories[i].tags.indices where rules.categories[i].tags[j].tag == tag {
                rules.categories[i].tags[j].status = status
            }
        }
        saveUserRules()
    }

    // Optional: add new tag (for future if you want to create tags from UI)
    func addTag(category: String, tag: String, keywords: [String]) {
        if let idx = rules.categories.firstIndex(where: { $0.category == category }) {
            if !rules.categories[idx].tags.contains(where: { $0.tag == tag }) {
                let rule = TagRule(tag: tag, status: .undecided, keywords: keywords)
                rules.categories[idx].tags.append(rule)
                saveUserRules()
            }
        } else {
            let rule = TagRule(tag: tag, status: .undecided, keywords: keywords)
            let cat = CategoryTagRules(category: category, tags: [rule])
            rules.categories.append(cat)
            saveUserRules()
        }
    }

    // MARK: - Persistence

    private func saveUserRules() {
        guard let url = KeywordTagger.userRulesURL else { return }
        do {
            let data = try JSONEncoder().encode(rules)
            try data.write(to: url, options: [.atomic])
        } catch {
            Log.tagging.error("KeywordTagger save error: \(error)")
        }
    }

    private static var userRulesURL: URL? {
        do {
            return try FileManager.default
                .url(for: .documentDirectory, in: .userDomainMask,
                     appropriateFor: nil, create: true)
                .appendingPathComponent("keyword_rules_user.json")
        } catch {
            return nil
        }
    }
}
