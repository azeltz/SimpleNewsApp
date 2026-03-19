//
//  SourcesViewModel.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/16/26.
//

import Foundation

/// A single source returned by GET /sources.
struct ServerSource: Identifiable, Codable {
    let id: String
    let url: String
    let source: String
    let kind: String
    let kindLabel: String
    let description: String
    var enabled: Bool
}

@MainActor
final class SourcesViewModel: ObservableObject {
    private let baseURL = simpleNewsBackendBaseURL

    @Published var sources: [ServerSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Sources grouped by the `source` domain field.
    var groupedSources: [(domain: String, sources: [Int])] {
        var domainOrder: [String] = []
        var domainIndices: [String: [Int]] = [:]
        for (index, src) in sources.enumerated() {
            if domainIndices[src.source] == nil {
                domainOrder.append(src.source)
            }
            domainIndices[src.source, default: []].append(index)
        }
        return domainOrder.map { domain in
            (domain: domain, sources: domainIndices[domain]!)
        }
    }

    var allEnabled: Bool {
        !sources.isEmpty && sources.allSatisfy { $0.enabled }
    }

    // MARK: - Debounce

    private var saveTask: Task<Void, Never>?

    // MARK: - Load

    func loadSources() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var request = URLRequest(url: baseURL.appendingPathComponent("sources"))
        request.httpMethod = "GET"
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Server returned an error. Tap to retry."
                return
            }
            struct SourcesResponse: Codable { let sources: [ServerSource] }
            let decoded = try JSONDecoder().decode(SourcesResponse.self, from: data)
            sources = decoded.sources
        } catch {
            errorMessage = "Could not load sources. Tap to retry."
        }
    }

    // MARK: - Toggle

    func toggle(at index: Int) {
        guard sources.indices.contains(index) else { return }
        sources[index].enabled.toggle()
        scheduleSave()
    }

    func setAll(enabled: Bool) {
        for i in sources.indices {
            sources[i].enabled = enabled
        }
        scheduleSave()
    }

    // MARK: - Save (debounced)

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await saveFeedsToServer()
        }
    }

    private func saveFeedsToServer() async {
        let enabledIds = sources.filter { $0.enabled }.map { ["id": $0.id] }
        let payload: [String: Any] = ["feeds": enabledIds]

        var request = URLRequest(url: baseURL.appendingPathComponent("feeds"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            // After successful save, trigger a background feed refresh
            await fetchUser(force: false)
        } catch {
            Log.network.error("SourcesViewModel: save failed – \(error)")
        }
    }

    // MARK: - Fetch User (trigger backend refresh)

    func fetchUser(force: Bool) async {
        var request = URLRequest(url: baseURL.appendingPathComponent("fetch-user"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        if force {
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["force": true])
        } else {
            request.httpBody = try? JSONSerialization.data(withJSONObject: [:] as [String: String])
        }

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            Log.network.error("SourcesViewModel: fetchUser failed – \(error)")
        }
    }
}
