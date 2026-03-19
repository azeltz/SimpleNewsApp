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

        // Try JSON-LD first (works for JS-rendered pages like MSN)
        let jsonLD = extractJSONLD(from: html)

        let title = titleOverride
            ?? extractMetaContent(from: html, forProperty: "og:title")
            ?? extractMeta(from: html, pattern: #"<title[^>]*>([^<]+)</title>"#)
            ?? jsonLD?["headline"] as? String
            ?? jsonLD?["name"] as? String
            ?? "Imported article"

        let description = extractMetaContent(from: html, forProperty: "og:description")
            ?? extractMetaContent(from: html, forName: "description")
            ?? jsonLD?["description"] as? String

        let imageString = extractMetaContent(from: html, forProperty: "og:image")
            ?? jsonLD?["thumbnailUrl"] as? String
            ?? (jsonLD?["image"] as? [String: Any])?["url"] as? String
            ?? jsonLD?["image"] as? String
        let imageURL = imageString.flatMap { URL(string: $0) }

        let sourceName = extractMetaContent(from: html, forProperty: "og:site_name")
            ?? (jsonLD?["publisher"] as? [String: Any])?["name"] as? String

        return Article(
            id: "imported_\(UUID().uuidString)",
            title: title.decodedHTMLEntities,
            description: description?.decodedHTMLEntities,
            content: nil,
            imageURL: imageURL,
            source: sourceName ?? url.host ?? "Imported",
            category: "Imported",
            publishedAt: Date(),
            url: url,
            isSaved: false,
            liked: nil,
            aiTags: ["Imported"]
        )
    }

    /// Extract the `content` attribute from a `<meta>` tag with the given `property` value.
    /// Handles any attribute ordering (e.g. `content` before `property`).
    private static func extractMetaContent(from html: String, forProperty property: String) -> String? {
        let pattern = #"<meta\s+[^>]*?property\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: property) + #"["'][^>]*?>"#
        guard let tag = extractMeta(from: html, pattern: pattern) else { return nil }
        return extractAttribute(named: "content", from: tag)
    }

    /// Extract the `content` attribute from a `<meta>` tag with the given `name` value.
    private static func extractMetaContent(from html: String, forName name: String) -> String? {
        let pattern = #"<meta\s+[^>]*?name\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: name) + #"["'][^>]*?>"#
        guard let tag = extractMeta(from: html, pattern: pattern) else { return nil }
        return extractAttribute(named: "content", from: tag)
    }

    /// Extract the value of a specific attribute from an HTML tag string.
    private static func extractAttribute(named attr: String, from tag: String) -> String? {
        let pattern = attr + #"\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        let value = String(tag[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Returns the full matched tag (group 0) instead of a capture group.
    private static func extractMeta(from html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { return nil }
        // Return group 1 if it exists, otherwise group 0
        let groupIndex = match.numberOfRanges > 1 ? 1 : 0
        guard let range = Range(match.range(at: groupIndex), in: html) else { return nil }
        let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Parse the first `<script type="application/ld+json">` block.
    private static func extractJSONLD(from html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        for match in matches {
            guard match.numberOfRanges > 1,
                  let jsonRange = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[jsonRange])
            guard let data = jsonString.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }

            // Could be a single object or an array
            if let dict = obj as? [String: Any] {
                // Look for NewsArticle or Article type
                if let type = dict["@type"] as? String,
                   type.contains("Article") || type.contains("NewsArticle") || type.contains("WebPage") {
                    return dict
                }
                // If no specific type match yet, keep as fallback
                return dict
            }
            if let array = obj as? [[String: Any]] {
                // Find the article entry
                for item in array {
                    if let type = item["@type"] as? String,
                       type.contains("Article") || type.contains("NewsArticle") {
                        return item
                    }
                }
                return array.first
            }
        }
        return nil
    }
}
