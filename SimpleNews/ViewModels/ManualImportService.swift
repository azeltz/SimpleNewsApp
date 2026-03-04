//
//  ManualImportService.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation

enum ManualImportService {
    /// Fetches a URL and extracts basic metadata to create an Article.
    static func importArticle(from urlString: String, titleOverride: String? = nil) async throws -> Article {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""

        let title = titleOverride ?? extractMeta(from: html, pattern: #"<meta\s+property="og:title"\s+content="([^"]+)""#)
                     ?? extractMeta(from: html, pattern: #"<title[^>]*>([^<]+)</title>"#)
                     ?? "Imported article"

        let description = extractMeta(from: html, pattern: #"<meta\s+(?:name="description"|property="og:description")\s+content="([^"]+)""#)

        let imageString = extractMeta(from: html, pattern: #"<meta\s+property="og:image"\s+content="([^"]+)""#)
        let imageURL = imageString.flatMap { URL(string: $0) }

        return Article(
            id: "imported_\(UUID().uuidString)",
            title: title.decodedHTMLEntities,
            description: description?.decodedHTMLEntities,
            content: nil,
            imageURL: imageURL,
            source: url.host ?? "Imported",
            category: "Imported",
            publishedAt: Date(),
            url: url,
            isSaved: false,
            liked: nil,
            aiTags: ["Imported"]
        )
    }

    private static func extractMeta(from html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
