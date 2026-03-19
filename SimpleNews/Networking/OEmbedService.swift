//
//  OEmbedService.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/16/26.
//

import Foundation

/// Detects oEmbed-capable URLs and fetches their HTML embed snippets.
enum OEmbedService {

    // MARK: - Provider definitions

    enum Provider: String, CaseIterable {
        case twitter
        case tiktok
        case youtube
        case reddit
        case spotify
        case vimeo

        /// The oEmbed endpoint for this provider.
        func endpointURL(for contentURL: URL) -> URL? {
            let base: String
            var extraItems: [URLQueryItem] = []

            switch self {
            case .twitter:
                base = "https://publish.twitter.com/oembed"
            case .tiktok:
                base = "https://www.tiktok.com/oembed"
            case .youtube:
                base = "https://www.youtube.com/oembed"
                extraItems.append(URLQueryItem(name: "format", value: "json"))
            case .reddit:
                base = "https://www.reddit.com/oembed"
            case .spotify:
                base = "https://open.spotify.com/oembed"
            case .vimeo:
                base = "https://vimeo.com/api/oembed.json"
            }

            guard var components = URLComponents(string: base) else { return nil }
            var items = [URLQueryItem(name: "url", value: contentURL.absoluteString)]
            items.append(contentsOf: extraItems)
            components.queryItems = items
            return components.url
        }
    }

    // MARK: - URL matching

    /// Returns the oEmbed provider for a URL, or `nil` if unsupported.
    static func provider(for url: URL) -> Provider? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()

        // X / Twitter
        if host.hasSuffix("twitter.com") || host.hasSuffix("x.com") {
            return .twitter
        }

        // TikTok
        if host.hasSuffix("tiktok.com") {
            return .tiktok
        }

        // YouTube
        if host.hasSuffix("youtube.com") && path.hasPrefix("/watch") {
            return .youtube
        }
        if host == "youtu.be" {
            return .youtube
        }

        // Reddit (comment threads only)
        if host.hasSuffix("reddit.com") && path.contains("/comments/") {
            return .reddit
        }

        // Spotify
        if host.hasSuffix("open.spotify.com") {
            return .spotify
        }

        // Vimeo
        if host.hasSuffix("vimeo.com") {
            return .vimeo
        }

        return nil
    }

    // MARK: - Fetch

    /// Fetches the oEmbed HTML for a URL. Returns `nil` if the URL is not
    /// supported or the fetch fails.
    static func fetchHTML(for url: URL) async -> String? {
        guard let provider = provider(for: url) else { return nil }
        guard let endpoint = provider.endpointURL(for: url) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let html = json["html"] as? String else {
                return nil
            }

            return html
        } catch {
            return nil
        }
    }
}
