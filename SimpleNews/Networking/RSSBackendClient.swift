//
//  RSSBackendClient.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/16/26.
//

import Foundation

struct RSSBackendArticle: Codable {
    let id: String
    let title: String?
    let url: String?
    let description: String?
    let publishedAt: String?
    let source: String?
    let category: String?
    let imageURL: String?
    let sourceURL: String?
    // feedId exists in JSON but we can ignore or add it later
}

struct RSSBackendResponse: Codable {
    let articles: [RSSBackendArticle]
}

final class RSSBackendClient {
    // TODO: set your actual Worker URL here
    private let baseURL = URL(string: "https://rss-aggregator.simplenews.workers.dev")!

    func fetchArticles() async throws -> [Article] {
        let url = baseURL.appendingPathComponent("api/news")
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(RSSBackendResponse.self, from: data)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // pubDate format varies; this is a common one. You can tweak later.
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        func isGoogleNewsHost(_ host: String?) -> Bool {
            guard let host = host?.lowercased() else { return false }
            // Handle news.google.com and regional subdomains like news.google.co.uk
            if host == "news.google.com" || host.hasSuffix(".news.google.com") { return true }
            // Some feeds may come as news.google.<tld>
            if host.hasPrefix("news.google.") { return true }
            return false
        }

        func unwrapGoogleNewsRedirect(_ raw: String?) -> URL? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            guard let url = URL(string: raw) else { return URL(string: raw) }

            // For Google News links, the real target is often in the `url` or `u` query parameter
            if isGoogleNewsHost(url.host) {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    if let target = comps.queryItems?.first(where: { $0.name == "url" || $0.name == "u" })?.value,
                       let unwrapped = URL(string: target) {
                        return unwrapped
                    }
                }
            }
            return url
        }

        func readableHost(from url: URL?) -> String? {
            guard let host = url?.host?.lowercased() else { return nil }
            if isGoogleNewsHost(host) { return nil }
            if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
            return host
        }

        func decodeHTMLEntities(_ text: String) -> String {
            // Use NSAttributedString to decode entities even if it's not full HTML
            let wrapped = text.contains("<") ? text : "<span>\(text)</span>"
            guard let data = wrapped.data(using: .utf8) else { return text }
            if let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            ) {
                let s = attributed.string
                // Clean common artifacts
                let cleaned = s.replacingOccurrences(of: "\u{00A0}", with: " ") // non‑breaking space
                return cleaned
            }
            return text
        }

        func cleanDescription(_ htmlish: String?) -> String? {
            guard let htmlish, !htmlish.isEmpty else { return htmlish }
            var text = htmlish

            // Remove common Google News boilerplate anchors and font tags heuristically
            text = text.replacingOccurrences(of: "<a[^>]*>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "</a>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "<font[^>]*>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "</font>", with: "", options: .regularExpression)

            // Replace <br> and variants with newlines
            text = text.replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)

            // Decode HTML entities using NSAttributedString, which also strips remaining tags
            var decoded = decodeHTMLEntities(text)

            // Remove leftover artifacts and collapse whitespace
            decoded = decoded
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
                .replacingOccurrences(of: "\t+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // If it's still suspiciously HTML‑like, strip any remaining tags defensively
            if decoded.contains("<") && decoded.contains(">") {
                decoded = decoded.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                decoded = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return decoded.isEmpty ? nil : decoded
        }

        return decoded.articles.map { item in
            let date: Date?
            if let publishedAt = item.publishedAt {
                date = formatter.date(from: publishedAt)
            } else {
                date = nil
            }

            let finalURL = unwrapGoogleNewsRedirect(item.url)

            let hostDisplay = readableHost(from: finalURL)

            let finalSource: String? = {
                // If the link is a Google News redirect, prefer the provided source field if present
                if isGoogleNewsHost(URL(string: item.url ?? "")?.host), let s = item.source?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    return s
                }
                // Otherwise, prefer the backend-provided source if non-empty
                if let s = item.source?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    return s
                }
                // Fallback to readable host from final URL
                return hostDisplay
            }()

            let finalDescription = cleanDescription(item.description)

            return Article(
                id: item.id,
                title: item.title ?? "Untitled",
                description: finalDescription,
                content: nil,
                imageURL: URL(string: item.imageURL ?? ""),
                source: finalSource,
                category: item.category,
                publishedAt: date,
                url: finalURL,
                isSaved: false,
                liked: nil,
                aiTags: [] // can add later based on feed/source
            )
        }
    }
}

