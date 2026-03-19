//
//  SubscriptionStore.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/18/26.
//

import Foundation
import WebKit

@MainActor
final class SubscriptionStore: ObservableObject {

    static let shared = SubscriptionStore()

    // MARK: - Published state

    @Published private(set) var builtInSources: [SubscriptionSource] = SubscriptionSource.builtIn
    @Published var customSources: [SubscriptionSource] = []

    /// Tracks which domains are currently logged in (domain → Bool).
    /// Refreshed asynchronously after cookie checks.
    @Published var loginStatus: [String: Bool] = [:]

    var allSources: [SubscriptionSource] {
        builtInSources + customSources
    }

    // MARK: - Storage keys

    private static let customSourcesKey = "custom_subscription_sources"
    private static let storeUUIDPrefix = "subscription_store_uuid_"

    // MARK: - Cached data stores

    /// domain → persistent WKWebsiteDataStore
    private var dataStores: [String: WKWebsiteDataStore] = [:]

    // MARK: - Init

    private init() {
        loadCustomSources()
    }

    // MARK: - Persistent WKWebsiteDataStore per domain

    func dataStore(for source: SubscriptionSource) -> WKWebsiteDataStore {
        if let cached = dataStores[source.domain] {
            return cached
        }
        let uuid = storeUUID(for: source.domain)
        let store = WKWebsiteDataStore(forIdentifier: uuid)
        dataStores[source.domain] = store
        return store
    }

    /// Returns the persistent data store for a domain string, if a matching
    /// subscription source exists and is logged in.
    func dataStoreForDomain(_ domain: String) -> WKWebsiteDataStore? {
        guard let source = allSources.first(where: { domainMatches($0.domain, host: domain) }),
              loginStatus[source.domain] == true else {
            return nil
        }
        return dataStore(for: source)
    }

    // MARK: - Login status

    func isLoggedIn(for source: SubscriptionSource) -> Bool {
        loginStatus[source.domain] ?? false
    }

    func refreshLoginStatus(for source: SubscriptionSource) async {
        let store = dataStore(for: source)
        let cookies = await store.httpCookieStore.allCookies()

        // Filter to cookies that actually belong to this domain.
        let domainCookies = cookies.filter { cookie in
            let cookieDomain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let srcDomain = source.domain.lowercased()
            return cookieDomain == srcDomain ||
                   cookieDomain.hasSuffix("." + srcDomain) ||
                   srcDomain.hasSuffix("." + cookieDomain)
        }

        // Just visiting a login page sets tracking/CSRF cookies even without
        // signing in.  We consider the user "logged in" only when there is a
        // cookie whose name looks like an authentication session token.
        //
        // Strategy: count how many domain cookies look like session/auth
        // cookies.  A single tracking cookie shouldn't flip the status, but
        // a real login typically sets multiple meaningful cookies.

        let authNameIndicators = [
            "session", "sess", "token", "auth", "login", "logged",
            "user", "account", "jwt", "access", "id_token",
            "sso", "remember", "identity", "credential", "subs",
            "nyt-s",     // NYT session cookie
            "nyt-auth",  // NYT
        ]

        // Names that are definitely NOT auth-related (tracking, consent, ads).
        let nonAuthIndicators = [
            "consent", "gdpr", "cookie_policy", "optanon", "_ga", "_gid",
            "fbp", "_fbp", "visitor", "campaign", "tracking", "analytics",
            "permutive", "purr-cache", "nyt-purr", "nyt-geo", "nyt-b",
            "nyt-gdpr", "nyt-mus", "datadome",
        ]

        var namedAuthCount = 0
        var heuristicAuthCount = 0

        for cookie in domainCookies {
            let name = cookie.name.lowercased()

            // Skip known non-auth cookies
            if nonAuthIndicators.contains(where: { name.contains($0) }) {
                continue
            }

            // 1) Name matches a known auth indicator — strong signal
            if authNameIndicators.contains(where: { name.contains($0) }) {
                namedAuthCount += 1
                continue
            }

            // 2) Secure + HttpOnly cookies with expiry > 1 hour and non-trivial
            //    value length — likely session tokens, not CSRF/tracking.
            if cookie.isHTTPOnly && cookie.isSecure,
               let expires = cookie.expiresDate,
               expires.timeIntervalSinceNow > 60 * 60,
               cookie.value.count >= 16 {
                heuristicAuthCount += 1
                continue
            }
        }

        // A named auth cookie is a strong signal. Heuristic-only cookies
        // need at least 2 to avoid false positives from tracking cookies.
        let isLoggedIn = namedAuthCount >= 1 || heuristicAuthCount >= 2
        loginStatus[source.domain] = isLoggedIn
    }

    func refreshAllLoginStatuses() async {
        for source in allSources {
            await refreshLoginStatus(for: source)
        }
    }

    // MARK: - Logout

    func logout(from source: SubscriptionSource) async {
        let store = dataStore(for: source)
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: allTypes)
        await store.removeData(ofTypes: allTypes, for: records)
        loginStatus[source.domain] = false
    }

    // MARK: - Custom sources

    func addCustomSource(_ source: SubscriptionSource) {
        guard !allSources.contains(where: { $0.domain == source.domain }) else { return }
        customSources.append(source)
        saveCustomSources()
    }

    func addCustomSource(domain: String, displayName: String, loginURL: URL) {
        let source = SubscriptionSource(
            id: "custom_\(domain)",
            domain: domain,
            displayName: displayName,
            loginURL: loginURL,
            isCustom: true
        )
        addCustomSource(source)
    }

    func removeCustomSource(_ source: SubscriptionSource) {
        customSources.removeAll { $0.id == source.id }
        saveCustomSources()
        // Clean up stored UUID
        let key = Self.storeUUIDPrefix + source.domain
        UserDefaults.standard.removeObject(forKey: key)
        dataStores.removeValue(forKey: source.domain)
        loginStatus.removeValue(forKey: source.domain)
    }

    /// Returns true if the domain already exists in any source (built-in or custom).
    func hasSource(for domain: String) -> Bool {
        allSources.contains { $0.domain == domain }
    }

    // MARK: - Private helpers

    private func storeUUID(for domain: String) -> UUID {
        let key = Self.storeUUIDPrefix + domain
        if let existing = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let newUUID = UUID()
        UserDefaults.standard.set(newUUID.uuidString, forKey: key)
        return newUUID
    }

    private func loadCustomSources() {
        guard let data = UserDefaults.standard.data(forKey: Self.customSourcesKey),
              let decoded = try? JSONDecoder().decode([SubscriptionSource].self, from: data) else {
            return
        }
        customSources = decoded
    }

    private func saveCustomSources() {
        guard let data = try? JSONEncoder().encode(customSources) else { return }
        UserDefaults.standard.set(data, forKey: Self.customSourcesKey)
    }

    /// Checks if a subscription source's domain matches a URL host.
    /// e.g. source domain "wsj.com" matches host "www.wsj.com" or "accounts.wsj.com".
    private func domainMatches(_ sourceDomain: String, host: String) -> Bool {
        let normalizedHost = host.lowercased()
        let normalizedDomain = sourceDomain.lowercased()
        return normalizedHost == normalizedDomain ||
               normalizedHost.hasSuffix("." + normalizedDomain)
    }
}
