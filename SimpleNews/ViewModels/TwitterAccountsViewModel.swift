//
//  TwitterAccountsViewModel.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/16/26.
//

import Foundation

@MainActor
final class TwitterAccountsViewModel: ObservableObject {
    private let baseURL = simpleNewsBackendBaseURL

    @Published var accounts: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Load

    func loadAccounts() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let endpoint = baseURL.appendingPathComponent("twitter/accounts")
        var request = URLRequest(url: endpoint)
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                errorMessage = "Failed to load accounts."
                return
            }

            struct AccountsResponse: Codable {
                let accounts: [String]
            }

            let decoded = try JSONDecoder().decode(AccountsResponse.self, from: data)
            accounts = decoded.accounts
        } catch {
            errorMessage = "Failed to load accounts."
        }
    }

    // MARK: - Add

    func addAccount(_ handle: String) {
        let cleaned = handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !cleaned.isEmpty else { return }
        guard !accounts.contains(where: { $0.lowercased() == cleaned.lowercased() }) else { return }

        accounts.append(cleaned)
        Task { await saveAccounts() }
    }

    // MARK: - Remove

    func removeAccounts(at offsets: IndexSet) {
        accounts.remove(atOffsets: offsets)
        Task { await saveAccounts() }
    }

    func removeAccount(_ handle: String) {
        accounts.removeAll { $0.lowercased() == handle.lowercased() }
        Task { await saveAccounts() }
    }

    // MARK: - Save

    private func saveAccounts() async {
        let endpoint = baseURL.appendingPathComponent("twitter/accounts")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UserIdManager.current, forHTTPHeaderField: "X-SimpleNews-UserId")

        struct Payload: Codable { let accounts: [String] }
        guard let body = try? JSONEncoder().encode(Payload(accounts: accounts)) else { return }
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Log.network.error("TwitterAccountsViewModel: save failed with status \(http.statusCode)")
            }
        } catch {
            Log.network.error("TwitterAccountsViewModel: save failed: \(error.localizedDescription)")
        }
    }
}
