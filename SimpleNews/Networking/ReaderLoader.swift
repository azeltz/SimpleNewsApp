//
//  ReaderLoader.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 2/17/26.
//

import Foundation
import Observation
import Readability
import ReadabilityUI

// MARK: - HTML image cleanup

enum HTMLImageCleaner {
    /// Returns a copy of `html` with the hero image removed from the body,
    /// and optionally all remaining `<img>` tags stripped.
    ///
    /// - Parameters:
    ///   - html: The full HTML string (including `<html>` wrapper).
    ///   - heroURL: The article's hero/cover image URL to always remove.
    ///   - hideAllImages: When `true`, every `<img>` tag is hidden.
    static func cleaned(html: String, heroURL: URL?, hideAllImages: Bool) -> String {
        var result = html

        // 1) Always strip the hero image from the body so it isn't shown twice.
        if let hero = heroURL {
            let heroStr = hero.absoluteString
            // Remove <img> tags whose src contains the hero URL
            if let regex = try? NSRegularExpression(
                pattern: "<img[^>]*src=[\"'][^\"']*\(NSRegularExpression.escapedPattern(for: heroStr))[^\"']*[\"'][^>]*/?>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // 2) Optionally hide all remaining images.
        if hideAllImages {
            if let regex = try? NSRegularExpression(
                pattern: "<img[^>]*/?>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        return result
    }
}

@MainActor
class ReaderLoader: ObservableObject {
    @Published var readerHTML: String?
    @Published var isLoading = false
    @Published var error: String?

    /// When `true`, the generated HTML will include inline JS that hides the
    /// first `<img>` in the body on page load (prevents hero image duplication).
    var hideFirstImage = false

    /// Set when Readability fails — indicates the page could not be
    /// extracted and the view should show feed text + open-in-browser prompt.
    @Published var extractionFailed = false

    func load(from url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        extractionFailed = false
        defer { isLoading = false }

        // Resolve the final URL first by following HTTP redirects.
        // This handles Google News intermediate pages, WSJ verify-device
        // redirects, and similar short-hop redirects.
        let resolvedURL = await resolveRedirects(url: url)

        do {
            let readability = Readability()
            let result = try await readability.parse(url: resolvedURL)
            // Strip WEBP format hints from image URLs before the HTML
            // reaches WKWebView. Yahoo/yimg uses semicolons in the path
            // (e.g. ";cf=webp") as well as query params.
            let baseHTML: String = result.content
                .replacingOccurrences(of: ";cf=webp", with: "")
                .replacingOccurrences(of: "cf=webp&", with: "")
                .replacingOccurrences(of: "&cf=webp", with: "")
                .replacingOccurrences(of: "?cf=webp", with: "")

            let styledHTML = """
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    :root {
                        color-scheme: light dark;
                    }

                    body {
                        font-family: -apple-system;
                        font-size: 18px;
                        line-height: 1.6;
                        padding: 8px 10px;
                        margin: 0;
                        background-color: transparent; /* key for see-through background */
                    }

                    p {
                        margin: 0 0 0.75em 0;
                    }

                    img {
                        max-width: 100%;
                        height: auto;
                        display: block;
                    }

                    /* Hide broken images instead of showing a broken icon */
                    img[data-failed] {
                        display: none !important;
                    }

                    /* Disable all links so taps don't navigate away */
                    a {
                        color: inherit;
                        text-decoration: none;
                        pointer-events: none;
                    }
                </style>
            </head>
            <body>
            \(baseHTML)
            <script>
            // Fix WEBP image URLs that WKWebView can't decode.
            // Yahoo/yimg CDN: strip cf=webp to get JPEG/PNG fallback.
            document.querySelectorAll('img').forEach(function(img) {
                var src = img.src || '';
                if (src.indexOf('cf=webp') !== -1) {
                    img.src = src.replace(/;cf=webp/g, '').replace(/[?&]cf=webp/g, '').replace(/&$/, '');
                }
                // Hide images that fail to load
                img.onerror = function() {
                    this.setAttribute('data-failed', '1');
                    this.style.display = 'none';
                };
            });
            // Clean up non-article content that Readability sometimes leaves.
            (function() {
                // 1) Hide junk container elements everywhere
                document.querySelectorAll('figure, figcaption, video, audio, iframe, header, nav, aside').forEach(function(el) {
                    el.style.display = 'none';
                });

                // 2) Check if an element is inside something already hidden
                function isInsideHidden(el) {
                    var p = el.parentElement;
                    while (p && p !== document.body) {
                        if (p.style.display === 'none') return true;
                        var tag = p.tagName.toLowerCase();
                        if (tag === 'figure' || tag === 'figcaption') return true;
                        p = p.parentElement;
                    }
                    return false;
                }

                // 3) Find the first <p> that is real article body text
                var allP = document.querySelectorAll('p');
                var firstRealP = null;
                for (var i = 0; i < allP.length; i++) {
                    if (isInsideHidden(allP[i])) continue;
                    var t = (allP[i].textContent || '').trim();
                    // Must be long enough and look like prose (contains spaces between words)
                    if (t.length >= 100 && (t.match(/ /g) || []).length >= 8) {
                        firstRealP = allP[i];
                        break;
                    }
                }

                // 4) Hide everything before the first real paragraph
                if (firstRealP) {
                    // Collect all ancestors of firstRealP so we never hide them
                    var ancestors = new Set();
                    var a = firstRealP;
                    while (a) { ancestors.add(a); a = a.parentElement; }

                    var all = document.body.querySelectorAll('*');
                    for (var i = 0; i < all.length; i++) {
                        var node = all[i];
                        if (node === firstRealP) break;
                        if (ancestors.has(node)) continue;
                        // Check if this node is before firstRealP in document order
                        if (node.compareDocumentPosition(firstRealP) & Node.DOCUMENT_POSITION_FOLLOWING) {
                            node.style.display = 'none';
                        }
                    }
                }

                // 5) Hide junk AFTER the article body: ads, paywall, footers, etc.
                // Walk every visible element and hide those matching known junk patterns.
                var junkPatterns = [
                    /^advertisement$/i,
                    /^skip\\s*advertisement$/i,
                    /^sponsored\\s*(content|by)/i,
                    /^related\\s*(content|articles|stories)/i,
                    /^further\\s*reading$/i,
                    /^more\\s*(stories|articles|from|in\\b)/i,
                    /^videos?$/i,
                    /^recommended$/i,
                    /^trending\\s*(now)?$/i,
                    /^you\\s*(may|might)\\s*(also)?\\s*like/i,
                    /^follow\\s+(us|.+on)/i,
                    /^sign\\s*up/i,
                    /thank\\s*you\\s*for\\s*your\\s*patience/i,
                    /already\\s*a\\s*subscriber/i,
                    /want\\s*all\\s*of\\s*the\\s*times/i,
                    /you\\s*have\\s*a\\s*preview/i,
                    /subscriber[s]?[,.]?\\s*(log\\s*in|sign\\s*in)/i,
                    /^copyright\\s/i,
                    /^\\u00a9\\s/i,
                    /^credit[.\\s]*\\.\\.\\./i,
                    /^credit\\s/i,
                    /for\\s*the\\s*new\\s*york\\s*times$/i,
                    /^photo\\s*(credit|by)/i,
                    /^all\\s*rights\\s*reserved/i,
                    /^want\\s*all\\s*of\\s*/i
                ];

                document.querySelectorAll('p, div, span, h2, h3, h4, h5, section, li').forEach(function(el) {
                    if (el.style.display === 'none') return;
                    if (el.children.length > 3) return;
                    var t = (el.textContent || '').trim();
                    if (t.length === 0 || t.length > 200) return;
                    for (var j = 0; j < junkPatterns.length; j++) {
                        if (junkPatterns[j].test(t)) {
                            el.style.display = 'none';
                            break;
                        }
                    }
                });
            })();
            \(hideFirstImage ? """
            // Hide the first <img> in the body to avoid duplicating the hero
            // image that is already shown as a native SwiftUI view above.
            (function() {
                var first = document.body.querySelector('img');
                if (first) { first.style.display = 'none'; }
            })();
            """ : "")
            </script>
            </body>
            </html>
            """

            self.readerHTML = styledHTML

        } catch {
            // Readability failed (JS-rendered sites like Ynet).
            // Try extracting article body from JSON-LD structured data
            // in the raw HTML as a last resort before giving up.
            if let extracted = await extractFromMetadata(url: url) {
                self.readerHTML = extracted
            } else {
                // No extraction possible — the view will show feed text
                // and prompt the user to open in browser.
                self.extractionFailed = true
                self.readerHTML = nil
            }
        }
    }

    // MARK: - Metadata extraction fallback

    /// Attempts to extract article text from the raw HTML using JSON-LD
    /// structured data or Open Graph meta tags. Returns styled HTML if
    /// extraction succeeds, or nil if no usable content is found.
    private func extractFromMetadata(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        else { return nil }

        // 1. Try JSON-LD articleBody
        if let articleBody = extractJSONLDBody(from: html), articleBody.count >= 100 {
            return wrapInReaderHTML(articleBody)
        }

        // 2. Try og:description (if substantial enough)
        if let ogDesc = extractMetaContent(property: "og:description", from: html), ogDesc.count >= 80 {
            return wrapInReaderHTML(ogDesc)
        }

        return nil
    }

    /// Extracts the `articleBody` field from a JSON-LD `<script>` block.
    private func extractJSONLDBody(from html: String) -> String? {
        let pattern = #"<script[^>]*type="application/ld\+json"[^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            let jsonStr = nsHTML.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) else { continue }

            // Handle both single object and array of objects
            let objects: [[String: Any]]
            if let dict = json as? [String: Any] {
                objects = [dict]
            } else if let arr = json as? [[String: Any]] {
                objects = arr
            } else {
                continue
            }

            for obj in objects {
                if let body = obj["articleBody"] as? String, !body.isEmpty {
                    return body
                }
            }
        }
        return nil
    }

    /// Extracts the `content` attribute from a `<meta>` tag with the given `property`.
    private func extractMetaContent(property: String, from html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let pattern = #"<meta[^>]*property="\#(escaped)"[^>]*content="([^"]*)"[^>]*/?\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)) else { return nil }
        let content = nsHTML.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    // MARK: - Redirect resolution

    /// Follows HTTP redirects (and checks for JS-based meta-refresh redirects)
    /// to resolve the final destination URL. This handles:
    /// - Google News intermediate redirect pages
    /// - WSJ "verify your device" interstitials
    /// - Other short-hop redirect chains
    private func resolveRedirects(url: URL, maxHops: Int = 5) async -> URL {
        // Use a session that does NOT auto-follow redirects so we can inspect each hop.
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: RedirectBlocker.shared, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var current = url
        for _ in 0..<maxHops {
            var request = URLRequest(url: current, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else { break }

            // HTTP redirect (301, 302, 303, 307, 308)
            if (300...399).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current) {
                current = next.absoluteURL
                continue
            }

            // Check for JS/meta-refresh redirect in the HTML (e.g. Google News)
            if http.statusCode == 200 {
                let limit = min(data.count, 8192)
                if let html = String(data: data[0..<limit], encoding: .utf8) ?? String(data: data[0..<limit], encoding: .ascii) {
                    if let metaURL = extractMetaRefreshURL(from: html, base: current) {
                        current = metaURL
                        continue
                    }
                }
            }

            break
        }

        return current
    }

    /// Extracts target URL from `<meta http-equiv="refresh" content="0;url=...">`.
    private func extractMetaRefreshURL(from html: String, base: URL) -> URL? {
        let pattern = #"<meta[^>]*http-equiv=[\"']refresh[\"'][^>]*content=[\"']\s*\d+\s*;\s*url=([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let target = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: target, relativeTo: base)?.absoluteURL
    }

    /// Wraps plain text into styled reader HTML.
    private func wrapInReaderHTML(_ text: String) -> String {
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Split on double newlines into paragraphs
        let paragraphs = escapedText
            .components(separatedBy: "\n\n")
            .map { "<p>\($0.trimmingCharacters(in: .whitespacesAndNewlines))</p>" }
            .joined(separator: "\n")

        return """
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                :root { color-scheme: light dark; }
                body {
                    font-family: -apple-system;
                    font-size: 18px;
                    line-height: 1.6;
                    padding: 8px 10px;
                    margin: 0;
                    background-color: transparent;
                }
                p { margin: 0 0 0.75em 0; }
            </style>
        </head>
        <body>
        \(paragraphs)
        </body>
        </html>
        """
    }
}

// MARK: - URLSession delegate that prevents automatic redirect following

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    static let shared = RedirectBlocker()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Return nil to block the redirect — we handle it manually
        completionHandler(nil)
    }
}
