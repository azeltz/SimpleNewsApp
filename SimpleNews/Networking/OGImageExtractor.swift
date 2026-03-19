//
//  OGImageExtractor.swift
//  SimpleNews
//
//  Lightweight Open Graph image extractor.
//  Fetches just enough of an article's HTML to find the og:image meta tag.
//

import Foundation

enum OGImageExtractor {

    /// Extracts the `og:image` URL from an article page.
    /// Uses a range request to avoid downloading full pages when the server supports it.
    static func fetchOGImage(for url: URL) async -> URL? {
        // Skip non-HTTP URLs
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        // Ask for just the first 32 KB — enough for <head> on most pages
        request.setValue("bytes=0-32767", forHTTPHeaderField: "Range")
        // Pretend to be a normal browser so servers don't block us
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            // Only parse up to 64 KB even if the server ignored our range header
            let limit = min(data.count, 65_536)
            let slice = data[0..<limit]
            guard let html = String(data: slice, encoding: .utf8)
                    ?? String(data: slice, encoding: .ascii) else { return nil }

            return extractOGImageURL(from: html)
        } catch {
            return nil
        }
    }

    /// Batch-fetch OG images for articles that are missing an imageURL.
    /// Runs up to `concurrency` requests at a time.
    static func enrichArticles(_ articles: [Article], concurrency: Int = 6) async -> [Article] {
        // Only process articles that need an image
        let needsImage = articles.enumerated().filter { $0.element.imageURL == nil }
        guard !needsImage.isEmpty else { return articles }

        var updated = articles

        await withTaskGroup(of: (Int, URL?).self) { group in
            var queued = 0

            for (index, article) in needsImage {
                guard let pageURL = article.url else { continue }

                group.addTask {
                    let imageURL = await fetchOGImage(for: pageURL)
                    return (index, imageURL)
                }
                queued += 1

                // Throttle: wait for one to finish before adding more
                if queued >= concurrency {
                    if let result = await group.next() {
                        if let imgURL = result.1 {
                            updated[result.0].imageURL = imgURL
                        }
                    }
                    queued -= 1
                }
            }

            // Collect remaining results
            for await result in group {
                if let imgURL = result.1 {
                    updated[result.0].imageURL = imgURL
                }
            }
        }

        return updated
    }

    // MARK: - Private

    /// Parses `og:image` content from an HTML string.
    private static func extractOGImageURL(from html: String) -> URL? {
        // Match: <meta property="og:image" content="...">
        // Also handle single quotes and varying attribute order
        let patterns = [
            // property before content
            #"<meta[^>]+property\s*=\s*["']og:image["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            // content before property
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']og:image["']"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let urlString = String(html[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: urlString) {
                    return url
                }
                // Try percent-encoding as fallback
                if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: encoded) {
                    return url
                }
            }
        }

        return nil
    }
}
