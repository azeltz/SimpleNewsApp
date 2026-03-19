//
//  SubscriptionLoginView.swift
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/18/26.
//

import SwiftUI
import WebKit

struct SubscriptionLoginView: View {
    let source: SubscriptionSource
    @ObservedObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SubscriptionWebView(
                url: source.loginURL,
                dataStore: store.dataStore(for: source),
                onNavigated: { url in
                    // Auto-dismiss when the user navigates away from the login page
                    if !isLoginPage(url) {
                        Task { @MainActor in
                            await store.refreshLoginStatus(for: source)
                            dismiss()
                        }
                    }
                }
            )
            .navigationTitle(source.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        Task { @MainActor in
                            await store.refreshLoginStatus(for: source)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    /// Heuristic: the page is still a login page if the URL path contains common
    /// login-related segments.
    private func isLoginPage(_ url: URL) -> Bool {
        let path = url.absoluteString.lowercased()
        let loginIndicators = ["login", "signin", "sign-in", "sign_in", "auth", "authenticate", "sso"]
        return loginIndicators.contains { path.contains($0) }
    }
}

// MARK: - WKWebView wrapper using a persistent data store

private struct SubscriptionWebView: UIViewRepresentable {
    let url: URL
    let dataStore: WKWebsiteDataStore
    let onNavigated: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigated: onNavigated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Use a real-ish user agent so paywalled sites don't block the login
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigated: (URL) -> Void
        private var hasDetectedLoginURL = false

        init(onNavigated: @escaping (URL) -> Void) {
            self.onNavigated = onNavigated
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            // Skip the very first load (the login page itself)
            if !hasDetectedLoginURL {
                hasDetectedLoginURL = true
                return
            }
            onNavigated(url)
        }
    }
}
