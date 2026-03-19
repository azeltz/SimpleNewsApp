//
//  TwitterFeedViewModel.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/16/26.
//

import Foundation

struct TweetEmbed: Identifiable {
    let id: String          // tweet URL string
    let url: URL
    let embedHTML: String
}

@MainActor
final class TwitterFeedViewModel: ObservableObject {
    private let baseURL = simpleNewsBackendBaseURL

    @Published var tweets: [TweetEmbed] = []
    @Published var hasAccounts = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Public API

    func loadTweets() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Check if the user has any accounts configured
            hasAccounts = try await fetchHasAccounts()

            let tweetURLs = try await fetchTweetURLs()
            if tweetURLs.isEmpty {
                tweets = []
                return
            }

            // Fetch oEmbed HTML for each tweet URL concurrently
            let results = await withTaskGroup(of: TweetEmbed?.self, returning: [TweetEmbed].self) { group in
                for url in tweetURLs {
                    group.addTask {
                        guard let html = await OEmbedService.fetchHTML(for: url) else { return nil }
                        return TweetEmbed(id: url.absoluteString, url: url, embedHTML: html)
                    }
                }

                var embeds: [TweetEmbed] = []
                for await result in group {
                    if let embed = result {
                        embeds.append(embed)
                    }
                }
                return embeds
            }

            // Preserve the original order from the API (O(n) lookup via dictionary)
            let urlOrderMap = Dictionary(uniqueKeysWithValues: tweetURLs.enumerated().map { ($0.element.absoluteString, $0.offset) })
            tweets = results.sorted { a, b in
                (urlOrderMap[a.id] ?? Int.max) < (urlOrderMap[b.id] ?? Int.max)
            }
        } catch {
            errorMessage = "Failed to load tweets."
        }
    }

    // MARK: - Networking

    private func fetchHasAccounts() async throws -> Bool {
        let endpoint = baseURL.appendingPathComponent("twitter/accounts")
        var request = URLRequest(url: endpoint)
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return false
        }

        struct AccountsResponse: Codable { let accounts: [String] }
        let decoded = try JSONDecoder().decode(AccountsResponse.self, from: data)
        return !decoded.accounts.isEmpty
    }

    private func fetchTweetURLs() async throws -> [URL] {
        let endpoint = baseURL.appendingPathComponent("api/tweets")
        var request = URLRequest(url: endpoint)
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct TweetsResponse: Codable {
            struct Tweet: Codable {
                let url: String
                let source: String?
            }
            let tweets: [Tweet]
        }

        let decoded = try JSONDecoder().decode(TweetsResponse.self, from: data)
        return decoded.tweets.compactMap { URL(string: $0.url) }
    }
}
