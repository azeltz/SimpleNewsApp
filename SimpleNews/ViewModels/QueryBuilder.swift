//
// QueryBuilder.swift
// SimpleNews
//
// Created by Amir Zeltzer on 2/13/26.
//

struct QueryBuilder {
    static func queryParams(
        settings: AppSettings,
        tagWeights: [String: Double]
    ) -> [String: String] {
        var params: [String: String] = [:]

        // Languages (up to 5)
        if !settings.languages.isEmpty {
            let codes = settings.languages.map { $0.rawValue }.prefix(5)
            params["language"] = codes.joined(separator: ",")
        }

        // Countries (up to 5)
        if !settings.countries.isEmpty {
            let codes = settings.countries.map { $0.rawValue }.prefix(5)
            params["country"] = codes.joined(separator: ",")
        }

        // Interests → category + qInTitle
        let positiveTags = tagWeights
            .filter { $0.value > 0.5 }
            .sorted(by: { $0.value > $1.value })
            .map { $0.key }

        let categoryTags = positiveTags.filter { knownCategories.contains($0.lowercased()) }
        let keywordTags = positiveTags.filter { !knownCategories.contains($0.lowercased()) }

        if !categoryTags.isEmpty {
            let cats = categoryTags.prefix(5).joined(separator: ",")
            params["category"] = cats
        }

        if !keywordTags.isEmpty {
            let q = keywordTags.joined(separator: " OR ")
            params["qInTitle"] = q
        }

        // Remove duplicates on API side
        params["removeduplicate"] = "1"

        // Quality mode: restrict to preferred or core outlets
        if settings.qualityMode {
            // Use user-defined preferred sources first
            let userDomains = settings.preferredSources
                .map { $0.lowercased() }
                .filter { !$0.isEmpty }

            // Fallback to a default core list if user didn't specify any
            let coreDomains: [String] = [
                "bbc.com",
                "nytimes.com",
                "reuters.com",
                "apnews.com",
                "cnn.com"
            ]

            let domainsToUse = userDomains.isEmpty ? coreDomains : userDomains

            // Ask Newsdata for top-quality articles within these domains
            params["prioritydomain"] = "top"
            params["domain"] = domainsToUse.joined(separator: ",")
        }

        return params
    }
}
