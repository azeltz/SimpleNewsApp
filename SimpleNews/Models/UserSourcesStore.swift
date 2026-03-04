//
//  UserSourcesStore.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

import Foundation

@MainActor
final class UserSourcesStore: ObservableObject {
    private static let storageKey = "userFeedSources"

    @Published var defaults: [FeedSource]
    @Published var custom: [FeedSource]

    /// All enabled sources (default + custom).
    var activeSources: [FeedSource] {
        (defaults + custom).filter { $0.isEnabled }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(SavedSources.self, from: data) {
            self.defaults = saved.defaults
            self.custom = saved.custom
        } else {
            self.defaults = FeedSource.defaults
            self.custom = []
        }
    }

    // MARK: - Persistence

    private struct SavedSources: Codable {
        let defaults: [FeedSource]
        let custom: [FeedSource]
    }

    private func persist() {
        let payload = SavedSources(defaults: defaults, custom: custom)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Mutations

    func toggle(source: FeedSource) {
        if let i = defaults.firstIndex(where: { $0.id == source.id }) {
            defaults[i].isEnabled.toggle()
        } else if let i = custom.firstIndex(where: { $0.id == source.id }) {
            custom[i].isEnabled.toggle()
        }
        persist()
        Task { await syncFeedsToServer() }
    }

    func addCustomSource(id: String, url: URL, source: String, kind: String) {
        let feed = FeedSource(
            id: id, url: url, source: source, kind: kind,
            isDefault: false, isEnabled: true
        )
        custom.append(feed)
        persist()
        Task { await syncFeedsToServer() }
    }

    func removeCustomSource(id: String) {
        custom.removeAll { $0.id == id }
        persist()
        Task { await syncFeedsToServer() }
    }

    // MARK: - Networking

    func syncFeedsToServer() async {
        let feeds = activeSources
        let userId = UserIdManager.current
        guard var components = URLComponents(string: "https://rss-aggregator.simplenews.workers.dev/feeds") else { return }
        components.queryItems = [URLQueryItem(name: "userId", value: userId)]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct FeedPayload: Codable {
            let id: String
            let url: String
            let source: String
            let kind: String
        }
        struct Body: Codable {
            let feeds: [FeedPayload]
        }

        let payload = Body(feeds: feeds.map {
            FeedPayload(id: $0.id, url: $0.url.absoluteString, source: $0.source, kind: $0.kind)
        })

        request.httpBody = try? JSONEncoder().encode(payload)

        _ = try? await URLSession.shared.data(for: request)
    }
}
