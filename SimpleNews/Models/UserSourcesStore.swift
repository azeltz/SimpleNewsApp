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
            // Restore saved preferences (respecting the user's enabled/disabled choices)
            self.defaults = saved.defaults
            self.custom = saved.custom
        } else {
            // First install: all default sources enabled
            self.defaults = FeedSource.defaultSources.map { src in
                var s = src
                s.isEnabled = true
                return s
            }
            self.custom = []
        }
    }

    // MARK: - Persistence

    private struct SavedSources: Codable {
        let defaults: [FeedSource]
        let custom: [FeedSource]
    }

    func persist() {
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
            id: id,
            url: url,
            source: source,
            kind: kind,
            isDefault: false,
            isEnabled: true
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
        let enabledIds = activeSources.map { ["id": $0.id] }
        let payload: [String: Any] = ["feeds": enabledIds]

        let url = simpleNewsBackendBaseURL.appendingPathComponent("feeds")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                Log.network.error("UserSourcesStore: sync failed with status \(http.statusCode)")
            }
        } catch {
            Log.network.error("UserSourcesStore: sync failed: \(error.localizedDescription)")
        }
    }
}
